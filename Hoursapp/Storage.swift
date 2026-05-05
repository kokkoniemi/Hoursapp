import Foundation
import Observation

@MainActor
@Observable
final class Storage {
    static let shared = Storage()

    private(set) var clients: [ClientProject] = []
    private(set) var tasks: [TaskType] = []
    private(set) var entries: [Entry] = []

    private let directory: URL
    private let clientsURL: URL
    private let tasksURL: URL
    private let entriesURL: URL

    private var saveClientsTask: Task<Void, Never>?
    private var saveTasksTask: Task<Void, Never>?
    private var saveEntriesTask: Task<Void, Never>?

    private static let clientsHeader = ["client", "project"]
    private static let tasksHeader = ["task"]
    private static let entriesHeader = ["id", "date", "client", "project", "task", "seconds", "notes", "started_at", "stopped_at"]

    init(directory: URL = URL(filePath: NSHomeDirectory()).appending(path: ".hourapp")) {
        self.directory = directory
        self.clientsURL = directory.appending(path: "clients.csv")
        self.tasksURL = directory.appending(path: "tasks.csv")
        self.entriesURL = directory.appending(path: "entries.csv")
    }

    func bootstrap() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try ensureFile(at: clientsURL, header: Self.clientsHeader)
        try ensureFile(at: tasksURL, header: Self.tasksHeader)
        try ensureFile(at: entriesURL, header: Self.entriesHeader)
        clients = try loadClients()
        tasks = try loadTasks()
        entries = try loadEntries()
    }

    func uniqueClientNames() -> [String] {
        Array(Set(clients.map(\.client))).sorted()
    }

    func projects(for client: String) -> [String] {
        clients.filter { $0.client == client }.map(\.project).sorted()
    }

    func taskNames() -> [String] { tasks.map(\.name).sorted() }

    func entries(on day: String) -> [Entry] {
        entries.filter { $0.date == day }
    }

    func runningEntry() -> Entry? {
        entries.first(where: { $0.isRunning })
    }

    func addClient(_ pair: ClientProject) {
        guard !clients.contains(pair) else { return }
        clients.append(pair)
        scheduleSaveClients()
    }

    func addTask(_ task: TaskType) {
        guard !tasks.contains(task) else { return }
        tasks.append(task)
        scheduleSaveTasks()
    }

    func upsertEntry(_ entry: Entry) {
        if let i = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[i] = entry
        } else {
            entries.append(entry)
        }
        scheduleSaveEntries()
    }

    func deleteEntry(id: String) {
        entries.removeAll(where: { $0.id == id })
        scheduleSaveEntries()
    }

    private func ensureFile(at url: URL, header: [String]) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try CSV.encode([header]).write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func loadClients() throws -> [ClientProject] {
        try parseRows(at: clientsURL).compactMap { cols in
            guard cols.count >= 2 else { return nil }
            return ClientProject(client: cols[0], project: cols[1])
        }
    }

    private func loadTasks() throws -> [TaskType] {
        try parseRows(at: tasksURL).compactMap { cols in
            guard let first = cols.first, !first.isEmpty else { return nil }
            return TaskType(name: first)
        }
    }

    private func loadEntries() throws -> [Entry] {
        try parseRows(at: entriesURL).compactMap { cols in
            guard cols.count >= 9 else { return nil }
            return Entry(
                id: cols[0],
                date: cols[1],
                client: cols[2],
                project: cols[3],
                task: cols[4],
                seconds: Int(cols[5]) ?? 0,
                notes: cols[6],
                startedAt: cols[7].isEmpty ? nil : cols[7],
                stoppedAt: cols[8].isEmpty ? nil : cols[8]
            )
        }
    }

    private func parseRows(at url: URL) throws -> [[String]] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let rows = CSV.parse(text)
        guard rows.count > 1 else { return [] }
        return Array(rows.dropFirst())
    }

    private func scheduleSaveClients() {
        saveClientsTask?.cancel()
        let snapshot = clients
        let url = clientsURL
        saveClientsTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { return }
            await self?.write(rows: [Self.clientsHeader] + snapshot.map { [$0.client, $0.project] }, to: url)
        }
    }

    private func scheduleSaveTasks() {
        saveTasksTask?.cancel()
        let snapshot = tasks
        let url = tasksURL
        saveTasksTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { return }
            await self?.write(rows: [Self.tasksHeader] + snapshot.map { [$0.name] }, to: url)
        }
    }

    private func scheduleSaveEntries() {
        saveEntriesTask?.cancel()
        let snapshot = entries
        let url = entriesURL
        saveEntriesTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { return }
            let rows: [[String]] = [Self.entriesHeader] + snapshot.map { e in
                [e.id, e.date, e.client, e.project, e.task, String(e.seconds), e.notes, e.startedAt ?? "", e.stoppedAt ?? ""]
            }
            await self?.write(rows: rows, to: url)
        }
    }

    func flushPendingWrites() async {
        await saveClientsTask?.value
        await saveTasksTask?.value
        await saveEntriesTask?.value
    }

    private func write(rows: [[String]], to url: URL) {
        let text = CSV.encode(rows)
        let tmp = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).tmp")
        do {
            try text.write(to: tmp, atomically: true, encoding: .utf8)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            NSLog("Hoursapp storage write failed for \(url.lastPathComponent): \(error)")
            try? FileManager.default.removeItem(at: tmp)
        }
    }
}
