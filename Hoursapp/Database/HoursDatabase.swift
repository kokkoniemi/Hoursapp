import Foundation
import GRDB

final class HoursDatabase: @unchecked Sendable {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    convenience init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "hoursapp.sqlite")
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        let queue = try DatabaseQueue(path: url.path, configuration: config)
        try self.init(dbQueue: queue)
    }

    static func inMemory() throws -> HoursDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: config)
        return try HoursDatabase(dbQueue: queue)
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        Migrations.register(in: &m)
        return m
    }
}
