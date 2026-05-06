import Foundation
import GRDB

enum CSVMigration {
    struct Result: Equatable {
        var clients: Int
        var projects: Int
        var tasks: Int
        var entries: Int
        var favorites: Int
        var skippedFavorites: Int
    }

    static func legacyCSVsExist(in directory: URL) -> Bool {
        let fm = FileManager.default
        for name in ["clients.csv", "tasks.csv", "entries.csv", "favorites.csv"] {
            if fm.fileExists(atPath: directory.appending(path: name).path) { return true }
        }
        return false
    }

    @discardableResult
    static func importIfNeeded(from directory: URL, into db: HoursDatabase) throws -> Result? {
        guard legacyCSVsExist(in: directory) else { return nil }

        let existingEntries = try db.dbQueue.read { try EntryRecord.fetchCount($0) }
        guard existingEntries == 0 else { return nil }

        let result = try db.dbQueue.write { db in
            try doImport(in: db, directory: directory)
        }
        try moveLegacyToBackup(in: directory)
        try writeMarker(in: directory, result: result)
        return result
    }

    private static func doImport(in db: Database, directory: URL) throws -> Result {
        let now = ISO8601Stamp.now()

        let clientsRows = parseCSV(at: directory.appending(path: "clients.csv"))
        let tasksRows   = parseCSV(at: directory.appending(path: "tasks.csv"))
        let entriesRows = parseCSV(at: directory.appending(path: "entries.csv"))
        let favRows     = parseCSV(at: directory.appending(path: "favorites.csv"))

        var clientIds: [String: Int64] = [:]
        var projectIds: [ProjectKey: Int64] = [:]   // keyed by (clientId, name)
        var taskIds: [TaskKey: Int64] = [:]

        var stats = Result(clients: 0, projects: 0, tasks: 0, entries: 0,
                           favorites: 0, skippedFavorites: 0)

        // Clients + projects from clients.csv
        for cols in clientsRows {
            guard cols.count >= 2 else { continue }
            let clientName = cols[0]
            let projectName = cols[1]
            guard !clientName.isEmpty, !projectName.isEmpty else { continue }
            let cid = try findOrCreateClient(name: clientName, ids: &clientIds, now: now, in: db, stats: &stats)
            _ = try findOrCreateProject(clientId: cid, name: projectName,
                                        ids: &projectIds, now: now, in: db, stats: &stats)
        }

        // Entries — authoritative source for client-scoped tasks
        for cols in entriesRows {
            guard cols.count >= 9 else { continue }
            let id = cols[0], date = cols[1], clientName = cols[2], projectName = cols[3], taskName = cols[4]
            guard !id.isEmpty, !date.isEmpty,
                  !clientName.isEmpty, !projectName.isEmpty, !taskName.isEmpty else { continue }
            let cid = try findOrCreateClient(name: clientName, ids: &clientIds, now: now, in: db, stats: &stats)
            let pid = try findOrCreateProject(clientId: cid, name: projectName,
                                              ids: &projectIds, now: now, in: db, stats: &stats)
            let tid = try findOrCreateTask(clientId: cid, name: taskName,
                                           ids: &taskIds, now: now, in: db, stats: &stats)
            let entry = EntryRecord(
                id: id,
                date: date,
                clientId: cid,
                projectId: pid,
                taskId: tid,
                seconds: Int(cols[5]) ?? 0,
                notes: cols[6],
                startedAt: cols[7].isEmpty ? nil : cols[7],
                stoppedAt: cols[8].isEmpty ? nil : cols[8],
                createdAt: now,
                updatedAt: now
            )
            try entry.insert(db)
            stats.entries += 1
        }

        // Favorites — drop any that reference clients/projects we don't know
        for cols in favRows {
            guard cols.count >= 3 else { continue }
            let clientName = cols[0], projectName = cols[1], taskName = cols[2]
            guard !clientName.isEmpty, !projectName.isEmpty, !taskName.isEmpty else { continue }
            guard let cid = clientIds[clientName],
                  let pid = projectIds[ProjectKey(clientId: cid, name: projectName)] else {
                stats.skippedFavorites += 1
                continue
            }
            let tid = try findOrCreateTask(clientId: cid, name: taskName,
                                           ids: &taskIds, now: now, in: db, stats: &stats)
            var fav = FavoriteRecord(id: nil, clientId: cid, projectId: pid, taskId: tid,
                                     createdAt: now, updatedAt: now)
            do {
                try fav.insert(db)
                stats.favorites += 1
            } catch {
                // Duplicate favorite — ignore.
                stats.skippedFavorites += 1
            }
        }

        // tasks.csv — only contributes names to clients that already have at least one task
        let extraTaskNames = tasksRows.compactMap { $0.first }.filter { !$0.isEmpty }
        for clientName in clientIds.keys {
            guard let cid = clientIds[clientName] else { continue }
            let hasAny = taskIds.keys.contains(where: { $0.clientId == cid })
            guard hasAny else { continue }
            for name in extraTaskNames {
                let key = TaskKey(clientId: cid, name: name)
                if taskIds[key] != nil { continue }
                _ = try findOrCreateTask(clientId: cid, name: name,
                                         ids: &taskIds, now: now, in: db, stats: &stats)
            }
        }

        return stats
    }

    private struct ProjectKey: Hashable { let clientId: Int64; let name: String }
    private struct TaskKey: Hashable { let clientId: Int64; let name: String }

    private static func findOrCreateClient(
        name: String, ids: inout [String: Int64], now: String,
        in db: Database, stats: inout Result
    ) throws -> Int64 {
        if let id = ids[name] { return id }
        var rec = ClientRecord(id: nil, name: name, createdAt: now, updatedAt: now)
        try rec.insert(db)
        let id = rec.id!
        ids[name] = id
        stats.clients += 1
        return id
    }

    private static func findOrCreateProject(
        clientId: Int64, name: String,
        ids: inout [ProjectKey: Int64], now: String,
        in db: Database, stats: inout Result
    ) throws -> Int64 {
        let key = ProjectKey(clientId: clientId, name: name)
        if let id = ids[key] { return id }
        var rec = ProjectRecord(id: nil, clientId: clientId, name: name,
                                createdAt: now, updatedAt: now)
        try rec.insert(db)
        let id = rec.id!
        ids[key] = id
        stats.projects += 1
        return id
    }

    private static func findOrCreateTask(
        clientId: Int64, name: String,
        ids: inout [TaskKey: Int64], now: String,
        in db: Database, stats: inout Result
    ) throws -> Int64 {
        let key = TaskKey(clientId: clientId, name: name)
        if let id = ids[key] { return id }
        var rec = TaskRecord(id: nil, clientId: clientId, name: name,
                             createdAt: now, updatedAt: now)
        try rec.insert(db)
        let id = rec.id!
        ids[key] = id
        stats.tasks += 1
        return id
    }

    private static func parseCSV(at url: URL) -> [[String]] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let rows = CSV.parse(text)
        guard rows.count > 1 else { return [] }
        return Array(rows.dropFirst())
    }

    private static func moveLegacyToBackup(in directory: URL) throws {
        let backup = directory.appending(path: "legacy-csv-backup")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        for name in ["clients.csv", "tasks.csv", "entries.csv", "favorites.csv"] {
            let src = directory.appending(path: name)
            let dst = backup.appending(path: name)
            if FileManager.default.fileExists(atPath: src.path) {
                try? FileManager.default.removeItem(at: dst)
                try FileManager.default.moveItem(at: src, to: dst)
            }
        }
    }

    private static func writeMarker(in directory: URL, result: Result) throws {
        let marker = directory.appending(path: ".migrated")
        let summary = """
        migrated_at=\(ISO8601Stamp.now())
        clients=\(result.clients)
        projects=\(result.projects)
        tasks=\(result.tasks)
        entries=\(result.entries)
        favorites=\(result.favorites)
        skipped_favorites=\(result.skippedFavorites)
        """
        try summary.write(to: marker, atomically: true, encoding: .utf8)
    }

    static func deleteBackupIfMarkerPresent(in directory: URL) {
        let marker = directory.appending(path: ".migrated")
        let backup = directory.appending(path: "legacy-csv-backup")
        let fm = FileManager.default
        guard fm.fileExists(atPath: marker.path),
              fm.fileExists(atPath: backup.path) else { return }
        try? fm.removeItem(at: backup)
    }
}

private enum ISO8601Stamp {
    static func now() -> String {
        DateFormat.timestamp(from: .now)
    }
}
