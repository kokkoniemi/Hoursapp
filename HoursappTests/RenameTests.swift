import Testing
import Foundation
@testable import Hoursapp

@MainActor
@Suite("Storage rename")
struct StorageRenameTests {
    @Test("renaming a client updates every entry that referenced it")
    func renameClientUpdatesEntries() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        let day = "2026-05-06"
        storage.upsertEntry(TestSupport.entry(
            id: "a", date: day, client: "Acme", project: "Site", task: "Design",
            seconds: 60, stoppedAt: Date.now.addingTimeInterval(-1)
        ))

        let renamed = storage.renameClient(from: "Acme", to: "Spitalfields")
        #expect(renamed)
        #expect(storage.entries.first?.client == "Spitalfields")
        #expect(storage.uniqueClientNames() == ["Spitalfields"])
    }

    @Test("rename is rejected when the new name is already taken")
    func renameClientRejectsConflict() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        storage.addClient(ClientProject(client: "Acme", project: "Site"))
        storage.addClient(ClientProject(client: "Beta", project: "App"))

        let renamed = storage.renameClient(from: "Acme", to: "Beta")
        #expect(!renamed)
        #expect(Set(storage.uniqueClientNames()) == ["Acme", "Beta"])
    }

    @Test("renaming to empty / unchanged / unknown sources is a no-op")
    func renameClientNoOps() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        storage.addClient(ClientProject(client: "Acme", project: "Site"))

        #expect(!storage.renameClient(from: "Acme", to: ""))
        #expect(!storage.renameClient(from: "Acme", to: "   "))
        #expect(!storage.renameClient(from: "Acme", to: "Acme"))
        #expect(!storage.renameClient(from: "Ghost", to: "NewGhost"))
        #expect(storage.uniqueClientNames() == ["Acme"])
    }

    @Test("renaming a project only affects that client's projects")
    func renameProjectIsClientScoped() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        storage.addClient(ClientProject(client: "Acme", project: "Site"))
        storage.addClient(ClientProject(client: "Beta", project: "Site"))   // same name, different client

        let renamed = storage.renameProject(client: "Acme", from: "Site", to: "Web")
        #expect(renamed)
        #expect(storage.projects(for: "Acme") == ["Web"])
        #expect(storage.projects(for: "Beta") == ["Site"], "Beta's Site should be untouched")
    }

    @Test("project rename is rejected if the same client already has the target name")
    func renameProjectRejectsConflict() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        storage.addClient(ClientProject(client: "Acme", project: "Site"))
        storage.addClient(ClientProject(client: "Acme", project: "Web"))

        let renamed = storage.renameProject(client: "Acme", from: "Site", to: "Web")
        #expect(!renamed)
        #expect(Set(storage.projects(for: "Acme")) == ["Site", "Web"])
    }

    @Test("renaming a task only affects that client's tasks")
    func renameTaskIsClientScoped() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        storage.addClient(ClientProject(client: "Acme", project: "Site"))
        storage.addClient(ClientProject(client: "Beta", project: "App"))
        storage.addTask(name: "Design", for: "Acme")
        storage.addTask(name: "Design", for: "Beta")

        let renamed = storage.renameTask(client: "Acme", from: "Design", to: "UX")
        #expect(renamed)
        #expect(storage.taskNames(for: "Acme") == ["UX"])
        #expect(storage.taskNames(for: "Beta") == ["Design"])
    }

    @Test("any rename clears a pending undo slot")
    func renameClearsUndo() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        storage.addClient(ClientProject(client: "Acme", project: "Site"))
        storage.upsertEntry(TestSupport.entry(
            id: "x", date: "2026-05-06",
            stoppedAt: Date.now.addingTimeInterval(-1)
        ))
        storage.deleteEntry(id: "x")
        #expect(storage.lastUndoableAction != nil)

        _ = storage.renameClient(from: "Acme", to: "Beta")
        #expect(storage.lastUndoableAction == nil)
    }
}
