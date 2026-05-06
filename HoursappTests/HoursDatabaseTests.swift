import Testing
import Foundation
import GRDB
@testable import Hoursapp

@Suite("HoursDatabase migrator + schema")
struct HoursDatabaseTests {
    private static func makeDB() throws -> HoursDatabase {
        try HoursDatabase.inMemory()
    }

    private static let now = "2026-05-06T10:00:00Z"

    @Test("v1 migration creates all expected tables")
    func migratorCreatesTables() throws {
        let db = try Self.makeDB()
        try db.dbQueue.read { db in
            for name in ["clients", "projects", "tasks", "entries", "favorites"] {
                let exists = try db.tableExists(name)
                #expect(exists, "expected table \(name)")
            }
        }
    }

    @Test("clients.name is unique")
    func clientNameUnique() throws {
        let db = try Self.makeDB()
        try db.dbQueue.write { db in
            var c1 = ClientRecord(id: nil, name: "Acme", createdAt: Self.now, updatedAt: Self.now)
            try c1.insert(db)
        }
        #expect(throws: DatabaseError.self) {
            try db.dbQueue.write { db in
                var c2 = ClientRecord(id: nil, name: "Acme", createdAt: Self.now, updatedAt: Self.now)
                try c2.insert(db)
            }
        }
    }

    @Test("same task name allowed under two different clients")
    func taskNamesAreClientScoped() throws {
        let db = try Self.makeDB()
        try db.dbQueue.write { db in
            var c1 = ClientRecord(id: nil, name: "Acme", createdAt: Self.now, updatedAt: Self.now)
            try c1.insert(db)
            var c2 = ClientRecord(id: nil, name: "Beta", createdAt: Self.now, updatedAt: Self.now)
            try c2.insert(db)

            var t1 = TaskRecord(id: nil, clientId: c1.id!, name: "Design",
                                createdAt: Self.now, updatedAt: Self.now)
            try t1.insert(db)
            var t2 = TaskRecord(id: nil, clientId: c2.id!, name: "Design",
                                createdAt: Self.now, updatedAt: Self.now)
            try t2.insert(db)

            #expect(t1.id != t2.id)
            let count = try TaskRecord.fetchCount(db)
            #expect(count == 2)
        }
    }

    @Test("duplicate task name under same client rejected")
    func taskNameUniquePerClient() throws {
        let db = try Self.makeDB()
        var clientId: Int64 = 0
        try db.dbQueue.write { db in
            var c = ClientRecord(id: nil, name: "Acme", createdAt: Self.now, updatedAt: Self.now)
            try c.insert(db)
            clientId = c.id!
            var t = TaskRecord(id: nil, clientId: clientId, name: "Design",
                               createdAt: Self.now, updatedAt: Self.now)
            try t.insert(db)
        }
        #expect(throws: DatabaseError.self) {
            try db.dbQueue.write { db in
                var t = TaskRecord(id: nil, clientId: clientId, name: "Design",
                                   createdAt: Self.now, updatedAt: Self.now)
                try t.insert(db)
            }
        }
    }

    @Test("entry referencing a task from a different client is rejected")
    func compositeFKEnforcesClientScopedTask() throws {
        let db = try Self.makeDB()
        try db.dbQueue.write { db in
            var acme = ClientRecord(id: nil, name: "Acme", createdAt: Self.now, updatedAt: Self.now)
            try acme.insert(db)
            var beta = ClientRecord(id: nil, name: "Beta", createdAt: Self.now, updatedAt: Self.now)
            try beta.insert(db)
            var acmeProject = ProjectRecord(id: nil, clientId: acme.id!, name: "Site",
                                            createdAt: Self.now, updatedAt: Self.now)
            try acmeProject.insert(db)
            var betaTask = TaskRecord(id: nil, clientId: beta.id!, name: "Design",
                                      createdAt: Self.now, updatedAt: Self.now)
            try betaTask.insert(db)

            // entry.client_id = acme but task belongs to beta — should fail
            let bad = EntryRecord(
                id: UUID().uuidString, date: "2026-05-06",
                clientId: acme.id!, projectId: acmeProject.id!, taskId: betaTask.id!,
                seconds: 0, notes: "", startedAt: nil, stoppedAt: Self.now,
                createdAt: Self.now, updatedAt: Self.now
            )
            #expect(throws: DatabaseError.self) {
                try bad.insert(db)
            }
        }
    }

    @Test("at most one running entry — partial unique index prevents a second")
    func onlyOneRunningEntry() throws {
        let db = try Self.makeDB()
        var clientId: Int64 = 0
        var projectId: Int64 = 0
        var taskId: Int64 = 0
        try db.dbQueue.write { db in
            var c = ClientRecord(id: nil, name: "Acme", createdAt: Self.now, updatedAt: Self.now)
            try c.insert(db)
            clientId = c.id!
            var p = ProjectRecord(id: nil, clientId: clientId, name: "Site",
                                  createdAt: Self.now, updatedAt: Self.now)
            try p.insert(db)
            projectId = p.id!
            var t = TaskRecord(id: nil, clientId: clientId, name: "Design",
                               createdAt: Self.now, updatedAt: Self.now)
            try t.insert(db)
            taskId = t.id!

            let running = EntryRecord(
                id: "first", date: "2026-05-06",
                clientId: clientId, projectId: projectId, taskId: taskId,
                seconds: 0, notes: "", startedAt: Self.now, stoppedAt: nil,
                createdAt: Self.now, updatedAt: Self.now
            )
            try running.insert(db)
        }

        #expect(throws: DatabaseError.self) {
            try db.dbQueue.write { db in
                let second = EntryRecord(
                    id: "second", date: "2026-05-06",
                    clientId: clientId, projectId: projectId, taskId: taskId,
                    seconds: 0, notes: "", startedAt: Self.now, stoppedAt: nil,
                    createdAt: Self.now, updatedAt: Self.now
                )
                try second.insert(db)
            }
        }
    }

    @Test("deleting a client with entries is restricted")
    func clientDeleteRestrictedByEntries() throws {
        let db = try Self.makeDB()
        try db.dbQueue.write { db in
            var c = ClientRecord(id: nil, name: "Acme", createdAt: Self.now, updatedAt: Self.now)
            try c.insert(db)
            var p = ProjectRecord(id: nil, clientId: c.id!, name: "Site",
                                  createdAt: Self.now, updatedAt: Self.now)
            try p.insert(db)
            var t = TaskRecord(id: nil, clientId: c.id!, name: "Design",
                               createdAt: Self.now, updatedAt: Self.now)
            try t.insert(db)
            let e = EntryRecord(
                id: "x", date: "2026-05-06",
                clientId: c.id!, projectId: p.id!, taskId: t.id!,
                seconds: 60, notes: "", startedAt: nil, stoppedAt: Self.now,
                createdAt: Self.now, updatedAt: Self.now
            )
            try e.insert(db)
        }

        #expect(throws: DatabaseError.self) {
            try db.dbQueue.write { db in
                _ = try ClientRecord.deleteAll(db)
            }
        }
    }

    @Test("deleting a client with no projects cascades to its tasks")
    func clientDeleteCascadesToTasks() throws {
        let db = try Self.makeDB()
        try db.dbQueue.write { db in
            var c = ClientRecord(id: nil, name: "Acme", createdAt: Self.now, updatedAt: Self.now)
            try c.insert(db)
            var t = TaskRecord(id: nil, clientId: c.id!, name: "Design",
                               createdAt: Self.now, updatedAt: Self.now)
            try t.insert(db)
            _ = try ClientRecord.deleteAll(db)
        }
        try db.dbQueue.read { db in
            let tasks = try TaskRecord.fetchCount(db)
            #expect(tasks == 0)
        }
    }

    @Test("deleting a project cascades its favorites")
    func projectDeleteCascadesFavorites() throws {
        let db = try Self.makeDB()
        try db.dbQueue.write { db in
            var c = ClientRecord(id: nil, name: "Acme", createdAt: Self.now, updatedAt: Self.now)
            try c.insert(db)
            var p = ProjectRecord(id: nil, clientId: c.id!, name: "Site",
                                  createdAt: Self.now, updatedAt: Self.now)
            try p.insert(db)
            var t = TaskRecord(id: nil, clientId: c.id!, name: "Design",
                               createdAt: Self.now, updatedAt: Self.now)
            try t.insert(db)
            var f = FavoriteRecord(id: nil, clientId: c.id!, projectId: p.id!, taskId: t.id!,
                                   createdAt: Self.now, updatedAt: Self.now)
            try f.insert(db)
            _ = try ProjectRecord.deleteAll(db)
        }
        try db.dbQueue.read { db in
            let favs = try FavoriteRecord.fetchCount(db)
            let tasks = try TaskRecord.fetchCount(db)
            #expect(favs == 0)
            #expect(tasks == 1, "task should NOT be cascade-deleted by project deletion")
        }
    }

    @Test("deleting a project with entries is restricted")
    func projectDeleteRestrictedByEntries() throws {
        let db = try Self.makeDB()
        try db.dbQueue.write { db in
            var c = ClientRecord(id: nil, name: "Acme", createdAt: Self.now, updatedAt: Self.now)
            try c.insert(db)
            var p = ProjectRecord(id: nil, clientId: c.id!, name: "Site",
                                  createdAt: Self.now, updatedAt: Self.now)
            try p.insert(db)
            var t = TaskRecord(id: nil, clientId: c.id!, name: "Design",
                               createdAt: Self.now, updatedAt: Self.now)
            try t.insert(db)
            let e = EntryRecord(
                id: "x", date: "2026-05-06",
                clientId: c.id!, projectId: p.id!, taskId: t.id!,
                seconds: 1, notes: "", startedAt: nil, stoppedAt: Self.now,
                createdAt: Self.now, updatedAt: Self.now
            )
            try e.insert(db)
        }
        #expect(throws: DatabaseError.self) {
            try db.dbQueue.write { db in
                _ = try ProjectRecord.deleteAll(db)
            }
        }
    }
}
