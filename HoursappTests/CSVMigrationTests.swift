import Testing
import Foundation
import GRDB
@testable import Hoursapp

@Suite("CSVMigration importer")
struct CSVMigrationTests {
    private static func makeDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "hoursapp-csvmig-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func write(_ rows: [[String]], to url: URL) throws {
        try CSV.encode(rows).write(to: url, atomically: true, encoding: .utf8)
    }

    private static func seed(
        in dir: URL,
        clients: [[String]] = [],
        tasks: [[String]] = [],
        entries: [[String]] = [],
        favorites: [[String]] = []
    ) throws {
        try write([["client", "project"]] + clients,
                  to: dir.appending(path: "clients.csv"))
        try write([["task"]] + tasks,
                  to: dir.appending(path: "tasks.csv"))
        try write([["id","date","client","project","task","seconds","notes","started_at","stopped_at"]] + entries,
                  to: dir.appending(path: "entries.csv"))
        try write([["client","project","task"]] + favorites,
                  to: dir.appending(path: "favorites.csv"))
    }

    @Test("imports a simple dataset and preserves entry UUIDs")
    func basicImport() throws {
        let dir = Self.makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Self.seed(
            in: dir,
            clients: [["Acme", "Site"]],
            tasks: [["Design"]],
            entries: [
                ["abc-123", "2026-05-06", "Acme", "Site", "Design", "1800",
                 "kickoff, with comma", "2026-05-06T09:00:00Z", "2026-05-06T09:30:00Z"]
            ],
            favorites: [["Acme", "Site", "Design"]]
        )

        let db = try HoursDatabase.inMemory()
        let result = try CSVMigration.importIfNeeded(from: dir, into: db)
        let r = try #require(result)
        #expect(r.clients == 1)
        #expect(r.projects == 1)
        #expect(r.tasks == 1)
        #expect(r.entries == 1)
        #expect(r.favorites == 1)
        #expect(r.skippedFavorites == 0)

        try db.dbQueue.read { db in
            let entry = try EntryRecord.fetchOne(db)
            let e = try #require(entry)
            #expect(e.id == "abc-123")
            #expect(e.notes == "kickoff, with comma")
            #expect(e.seconds == 1800)
        }
    }

    @Test("same task name under two clients yields two distinct rows")
    func taskNamesAreClientScoped() throws {
        let dir = Self.makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Self.seed(
            in: dir,
            clients: [["Acme", "Site"], ["Beta", "App"]],
            tasks: [],
            entries: [
                ["e1", "2026-05-06", "Acme", "Site", "Design", "60", "", "", "2026-05-06T09:00:00Z"],
                ["e2", "2026-05-06", "Beta", "App",  "Design", "90", "", "", "2026-05-06T10:00:00Z"]
            ],
            favorites: []
        )

        let db = try HoursDatabase.inMemory()
        let result = try CSVMigration.importIfNeeded(from: dir, into: db)
        let r = try #require(result)
        #expect(r.tasks == 2)

        try db.dbQueue.read { db in
            let count = try TaskRecord.fetchCount(db)
            #expect(count == 2)
            let names = try TaskRecord
                .order(TaskRecord.Columns.clientId)
                .fetchAll(db)
                .map(\.name)
            #expect(names == ["Design", "Design"])
        }
    }

    @Test("tasks.csv hint does not pollute clients without entries for that task")
    func tasksCSVHintIsBoundedToActiveClients() throws {
        let dir = Self.makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Acme has an entry; Beta exists in clients.csv but has no entries → no tasks
        try Self.seed(
            in: dir,
            clients: [["Acme", "Site"], ["Beta", "App"]],
            tasks: [["LegacyTask"]],
            entries: [
                ["e1", "2026-05-06", "Acme", "Site", "Design", "60", "", "", "2026-05-06T09:00:00Z"]
            ],
            favorites: []
        )

        let db = try HoursDatabase.inMemory()
        _ = try CSVMigration.importIfNeeded(from: dir, into: db)

        try db.dbQueue.read { db in
            let acmeTasks = try TaskRecord
                .filter(TaskRecord.Columns.clientId == 1)  // Acme inserted first
                .order(TaskRecord.Columns.name)
                .fetchAll(db)
                .map(\.name)
            #expect(acmeTasks == ["Design", "LegacyTask"])

            let betaTasks = try TaskRecord
                .filter(TaskRecord.Columns.clientId == 2)
                .fetchCount(db)
            #expect(betaTasks == 0, "Beta has no entries → no tasks attached")
        }
    }

    @Test("favorites referencing unknown clients are skipped")
    func favoritesWithUnknownReferencesAreSkipped() throws {
        let dir = Self.makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Self.seed(
            in: dir,
            clients: [["Acme", "Site"]],
            tasks: [],
            entries: [
                ["e1", "2026-05-06", "Acme", "Site", "Design", "60", "", "", "2026-05-06T09:00:00Z"]
            ],
            favorites: [
                ["Acme", "Site", "Design"],
                ["Ghost", "Phantom", "Unreal"]
            ]
        )

        let db = try HoursDatabase.inMemory()
        let result = try CSVMigration.importIfNeeded(from: dir, into: db)
        let r = try #require(result)
        #expect(r.favorites == 1)
        #expect(r.skippedFavorites == 1)
    }

    @Test("import is a no-op when DB already has entries")
    func idempotentOnNonEmptyDB() throws {
        let dir = Self.makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Self.seed(in: dir, clients: [["Acme", "Site"]], tasks: [],
                      entries: [["e1", "2026-05-06", "Acme", "Site", "Design",
                                 "60", "", "", "2026-05-06T09:00:00Z"]],
                      favorites: [])

        let db = try HoursDatabase.inMemory()
        _ = try CSVMigration.importIfNeeded(from: dir, into: db)
        // Re-create CSVs (the importer moved them to backup) and try again.
        try Self.seed(in: dir, clients: [["Acme", "Site"]], tasks: [],
                      entries: [["e2", "2026-05-06", "Acme", "Site", "Design",
                                 "60", "", "", "2026-05-06T09:00:00Z"]],
                      favorites: [])
        let second = try CSVMigration.importIfNeeded(from: dir, into: db)
        #expect(second == nil)
        try db.dbQueue.read { db in
            let n = try EntryRecord.fetchCount(db)
            #expect(n == 1)
        }
    }

    @Test("legacy CSVs are moved to backup and marker file written")
    func backupAndMarker() throws {
        let dir = Self.makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Self.seed(in: dir, clients: [["Acme", "Site"]], tasks: [],
                      entries: [["e1", "2026-05-06", "Acme", "Site", "Design",
                                 "60", "", "", "2026-05-06T09:00:00Z"]],
                      favorites: [])

        let db = try HoursDatabase.inMemory()
        _ = try CSVMigration.importIfNeeded(from: dir, into: db)

        let fm = FileManager.default
        for name in ["clients.csv", "tasks.csv", "entries.csv", "favorites.csv"] {
            #expect(!fm.fileExists(atPath: dir.appending(path: name).path))
            #expect(fm.fileExists(atPath: dir.appending(path: "legacy-csv-backup").appending(path: name).path))
        }
        #expect(fm.fileExists(atPath: dir.appending(path: ".migrated").path))
    }

    @Test("running entry (empty stopped_at) survives import")
    func runningEntryRoundTrips() throws {
        let dir = Self.makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Self.seed(in: dir, clients: [["Acme", "Site"]], tasks: [],
                      entries: [["run-1", "2026-05-06", "Acme", "Site", "Design",
                                 "0", "", "2026-05-06T09:00:00Z", ""]],
                      favorites: [])

        let db = try HoursDatabase.inMemory()
        _ = try CSVMigration.importIfNeeded(from: dir, into: db)

        try db.dbQueue.read { db in
            let e = try #require(try EntryRecord.fetchOne(db))
            #expect(e.id == "run-1")
            #expect(e.startedAt == "2026-05-06T09:00:00Z")
            #expect(e.stoppedAt == nil)
        }
    }

    @Test("deleteBackupIfMarkerPresent clears the backup folder")
    func backupCleanup() throws {
        let dir = Self.makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Self.seed(in: dir, clients: [["Acme", "Site"]], tasks: [],
                      entries: [["e1", "2026-05-06", "Acme", "Site", "Design",
                                 "60", "", "", "2026-05-06T09:00:00Z"]],
                      favorites: [])

        let db = try HoursDatabase.inMemory()
        _ = try CSVMigration.importIfNeeded(from: dir, into: db)

        let backup = dir.appending(path: "legacy-csv-backup")
        #expect(FileManager.default.fileExists(atPath: backup.path))

        CSVMigration.deleteBackupIfMarkerPresent(in: dir)
        #expect(!FileManager.default.fileExists(atPath: backup.path))
    }
}
