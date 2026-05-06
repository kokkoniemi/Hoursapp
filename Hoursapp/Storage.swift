import Foundation
import GRDB
import Observation

@MainActor
@Observable
final class Storage {
    static let shared = Storage()

    private(set) var clients: [ClientProject] = []
    private(set) var tasks: [TaskType] = []
    private(set) var entries: [Entry] = []
    private(set) var favorites: [Favorite] = []

    private let directory: URL?
    private var database: HoursDatabase!

    init(directory: URL? = URL(filePath: NSHomeDirectory()).appending(path: ".hoursapp")) {
        self.directory = directory
    }

    init(database: HoursDatabase) {
        self.directory = nil
        self.database = database
        refreshAll()
    }

    func bootstrap() throws {
        if database == nil {
            guard let directory else {
                preconditionFailure("Storage initialized without directory or database")
            }
            database = try HoursDatabase(directory: directory)
        }
        refreshAll()
    }

    /// Synchronous SQLite writes don't need flushing; kept as a no-op for
    /// callers that still `await` it (AppDelegate, tests).
    func flushPendingWrites() async { }

    // MARK: - Read helpers (in-memory)

    func uniqueClientNames() -> [String] {
        Array(Set(clients.map(\.client))).sorted()
    }

    func projects(for client: String) -> [String] {
        clients.filter { $0.client == client }.map(\.project).sorted()
    }

    func taskNames(for client: String) -> [String] {
        tasks.filter { $0.client == client }.map(\.name).sorted()
    }

    func entries(on day: String) -> [Entry] {
        entries.filter { $0.date == day }
    }

    func runningEntry() -> Entry? {
        entries.first(where: { $0.isRunning })
    }

    func isFavorite(client: String, project: String, task: String) -> Bool {
        favorites.contains(Favorite(client: client, project: project, task: task))
    }

    func mostRecentEntry() -> Entry? { entries.last }

    func mostRecentEntry(client: String) -> Entry? {
        entries.last(where: { $0.client == client })
    }

    func mostRecentEntry(client: String, project: String) -> Entry? {
        entries.last(where: { $0.client == client && $0.project == project })
    }

    func runningStartedAtDate() -> Date? {
        guard let started = runningEntry()?.startedAt else { return nil }
        return DateFormat.timestampFormatter.date(from: started)
    }

    func displayedSeconds(for entry: Entry, at now: Date = .now) -> Int {
        guard entry.isRunning,
              let started = entry.startedAt,
              let startDate = DateFormat.timestampFormatter.date(from: started) else {
            return entry.seconds
        }
        return entry.seconds + max(0, Int(now.timeIntervalSince(startDate)))
    }

    func todayTotalSeconds(at now: Date = .now) -> Int {
        let today = DateFormat.day(from: now)
        return entries.filter { $0.date == today }
            .reduce(0) { $0 + displayedSeconds(for: $1, at: now) }
    }

    // MARK: - Mutations

    func addClient(_ pair: ClientProject) {
        let now = DateFormat.timestamp(from: .now)
        do {
            try database.dbQueue.write { db in
                let cid = try Self.findOrCreateClient(name: pair.client, in: db, now: now)
                _ = try Self.findOrCreateProject(clientId: cid, name: pair.project, in: db, now: now)
            }
        } catch {
            NSLog("Hoursapp addClient failed: \(error)")
        }
        refreshAll()
    }

    func addTask(name: String, for client: String) {
        let now = DateFormat.timestamp(from: .now)
        do {
            try database.dbQueue.write { db in
                let cid = try Self.findOrCreateClient(name: client, in: db, now: now)
                _ = try Self.findOrCreateTask(clientId: cid, name: name, in: db, now: now)
            }
        } catch {
            NSLog("Hoursapp addTask failed: \(error)")
        }
        refreshAll()
    }

    func addFavorite(_ favorite: Favorite) {
        let now = DateFormat.timestamp(from: .now)
        do {
            try database.dbQueue.write { db in
                let cid = try Self.findOrCreateClient(name: favorite.client, in: db, now: now)
                let pid = try Self.findOrCreateProject(clientId: cid, name: favorite.project, in: db, now: now)
                let tid = try Self.findOrCreateTask(clientId: cid, name: favorite.task, in: db, now: now)
                var rec = FavoriteRecord(id: nil, clientId: cid, projectId: pid, taskId: tid,
                                         createdAt: now, updatedAt: now)
                do {
                    try rec.insert(db)
                } catch DatabaseError.SQLITE_CONSTRAINT {
                    // Already exists — ignore.
                }
            }
        } catch {
            NSLog("Hoursapp addFavorite failed: \(error)")
        }
        refreshAll()
    }

    func removeFavorite(_ favorite: Favorite) {
        do {
            try database.dbQueue.write { db in
                try db.execute(sql: """
                    DELETE FROM favorites
                    WHERE id IN (
                        SELECT f.id FROM favorites f
                        JOIN clients c  ON c.id = f.client_id
                        JOIN projects p ON p.id = f.project_id
                        JOIN tasks t    ON t.id = f.task_id
                        WHERE c.name = ? AND p.name = ? AND t.name = ?
                    )
                """, arguments: [favorite.client, favorite.project, favorite.task])
            }
        } catch {
            NSLog("Hoursapp removeFavorite failed: \(error)")
        }
        refreshFavorites()
    }

    func upsertEntry(_ entry: Entry) {
        let now = DateFormat.timestamp(from: .now)
        do {
            try database.dbQueue.write { db in
                let cid = try Self.findOrCreateClient(name: entry.client, in: db, now: now)
                let pid = try Self.findOrCreateProject(clientId: cid, name: entry.project, in: db, now: now)
                let tid = try Self.findOrCreateTask(clientId: cid, name: entry.task, in: db, now: now)

                let existing = try EntryRecord.fetchOne(db, key: entry.id)
                let createdAt = existing?.createdAt ?? now

                let rec = EntryRecord(
                    id: entry.id,
                    date: entry.date,
                    clientId: cid,
                    projectId: pid,
                    taskId: tid,
                    seconds: entry.seconds,
                    notes: entry.notes,
                    startedAt: entry.startedAt,
                    stoppedAt: entry.stoppedAt,
                    createdAt: createdAt,
                    updatedAt: now
                )

                if existing == nil {
                    try rec.insert(db)
                } else {
                    try rec.update(db)
                }
            }
        } catch {
            NSLog("Hoursapp upsertEntry failed: \(error)")
        }
        refreshAll()
    }

    func deleteEntry(id: String) {
        do {
            try database.dbQueue.write { db in
                _ = try EntryRecord.filter(EntryRecord.Columns.id == id).deleteAll(db)
            }
        } catch {
            NSLog("Hoursapp deleteEntry failed: \(error)")
        }
        refreshEntries()
    }

    func startTimer(client: String, project: String, task: String, on date: String) {
        let now = DateFormat.timestamp(from: .now)
        do {
            try database.dbQueue.write { db in
                try Self.stopRunningEntry(in: db, atTimestamp: now)

                let cid = try Self.findOrCreateClient(name: client, in: db, now: now)
                let pid = try Self.findOrCreateProject(clientId: cid, name: project, in: db, now: now)
                let tid = try Self.findOrCreateTask(clientId: cid, name: task, in: db, now: now)

                if var existing = try EntryRecord
                    .filter(EntryRecord.Columns.date == date)
                    .filter(EntryRecord.Columns.clientId == cid)
                    .filter(EntryRecord.Columns.projectId == pid)
                    .filter(EntryRecord.Columns.taskId == tid)
                    .fetchOne(db) {
                    existing.startedAt = now
                    existing.stoppedAt = nil
                    existing.updatedAt = now
                    try existing.update(db)
                } else {
                    let new = EntryRecord(
                        id: UUID().uuidString,
                        date: date,
                        clientId: cid,
                        projectId: pid,
                        taskId: tid,
                        seconds: 0,
                        notes: "",
                        startedAt: now,
                        stoppedAt: nil,
                        createdAt: now,
                        updatedAt: now
                    )
                    try new.insert(db)
                }
            }
        } catch {
            NSLog("Hoursapp startTimer failed: \(error)")
        }
        refreshAll()
    }

    func stopTimer() {
        let now = DateFormat.timestamp(from: .now)
        do {
            try database.dbQueue.write { db in
                try Self.stopRunningEntry(in: db, atTimestamp: now)
            }
        } catch {
            NSLog("Hoursapp stopTimer failed: \(error)")
        }
        refreshEntries()
    }

    func discardRunningIdle(seconds: Int) {
        let nowDate = Date.now
        let nowText = DateFormat.timestamp(from: nowDate)
        do {
            try database.dbQueue.write { db in
                guard var running = try Self.fetchRunningEntry(in: db),
                      let started = running.startedAt,
                      let startDate = DateFormat.timestampFormatter.date(from: started) else { return }
                let bumped = startDate.addingTimeInterval(TimeInterval(seconds))
                let safe = min(bumped, nowDate)
                running.startedAt = DateFormat.timestamp(from: safe)
                running.updatedAt = nowText
                try running.update(db)
            }
        } catch {
            NSLog("Hoursapp discardRunningIdle failed: \(error)")
        }
        refreshEntries()
    }

    func stopTimerDiscardingIdle(seconds: Int) {
        discardRunningIdle(seconds: seconds)
        stopTimer()
    }

    // MARK: - Internal DB helpers (called inside a write transaction)

    private static func stopRunningEntry(in db: Database, atTimestamp now: String) throws {
        guard var running = try fetchRunningEntry(in: db) else { return }
        let nowDate = Date.now
        if let started = running.startedAt,
           let startDate = DateFormat.timestampFormatter.date(from: started) {
            running.seconds += max(0, Int(nowDate.timeIntervalSince(startDate)))
        }
        running.stoppedAt = now
        running.updatedAt = now
        try running.update(db)
    }

    private static func fetchRunningEntry(in db: Database) throws -> EntryRecord? {
        try EntryRecord
            .filter(sql: "stopped_at IS NULL")
            .fetchOne(db)
    }

    private static func findOrCreateClient(name: String, in db: Database, now: String) throws -> Int64 {
        if let existing = try ClientRecord.filter(ClientRecord.Columns.name == name).fetchOne(db) {
            return existing.id!
        }
        var rec = ClientRecord(id: nil, name: name, createdAt: now, updatedAt: now)
        try rec.insert(db)
        return rec.id!
    }

    private static func findOrCreateProject(
        clientId: Int64, name: String, in db: Database, now: String
    ) throws -> Int64 {
        if let existing = try ProjectRecord
            .filter(ProjectRecord.Columns.clientId == clientId)
            .filter(ProjectRecord.Columns.name == name)
            .fetchOne(db) {
            return existing.id!
        }
        var rec = ProjectRecord(id: nil, clientId: clientId, name: name,
                                createdAt: now, updatedAt: now)
        try rec.insert(db)
        return rec.id!
    }

    private static func findOrCreateTask(
        clientId: Int64, name: String, in db: Database, now: String
    ) throws -> Int64 {
        if let existing = try TaskRecord
            .filter(TaskRecord.Columns.clientId == clientId)
            .filter(TaskRecord.Columns.name == name)
            .fetchOne(db) {
            return existing.id!
        }
        var rec = TaskRecord(id: nil, clientId: clientId, name: name,
                             createdAt: now, updatedAt: now)
        try rec.insert(db)
        return rec.id!
    }

    // MARK: - Refresh

    private func refreshAll() {
        refreshClients()
        refreshTasks()
        refreshEntries()
        refreshFavorites()
    }

    private func refreshClients() {
        clients = (try? database.dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT c.name AS client, p.name AS project
                FROM projects p
                JOIN clients c ON c.id = p.client_id
                ORDER BY p.ROWID
            """).map { row in
                ClientProject(client: row["client"], project: row["project"])
            }
        }) ?? []
    }

    private func refreshTasks() {
        tasks = (try? database.dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT c.name AS client, t.name AS name
                FROM tasks t
                JOIN clients c ON c.id = t.client_id
                ORDER BY t.ROWID
            """).map { row in
                TaskType(client: row["client"], name: row["name"])
            }
        }) ?? []
    }

    private func refreshEntries() {
        entries = (try? database.dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT e.id, e.date,
                       c.name AS client,
                       p.name AS project,
                       t.name AS task,
                       e.seconds, e.notes, e.started_at, e.stopped_at
                FROM entries e
                JOIN clients c  ON c.id = e.client_id
                JOIN projects p ON p.id = e.project_id
                JOIN tasks t    ON t.id = e.task_id
                ORDER BY e.ROWID
            """).map { row in
                Entry(
                    id: row["id"],
                    date: row["date"],
                    client: row["client"],
                    project: row["project"],
                    task: row["task"],
                    seconds: row["seconds"],
                    notes: row["notes"],
                    startedAt: row["started_at"],
                    stoppedAt: row["stopped_at"]
                )
            }
        }) ?? []
    }

    private func refreshFavorites() {
        favorites = (try? database.dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT c.name AS client, p.name AS project, t.name AS task
                FROM favorites f
                JOIN clients c  ON c.id = f.client_id
                JOIN projects p ON p.id = f.project_id
                JOIN tasks t    ON t.id = f.task_id
                ORDER BY f.ROWID
            """).map { row in
                Favorite(client: row["client"], project: row["project"], task: row["task"])
            }
        }) ?? []
    }
}
