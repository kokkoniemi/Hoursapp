import Testing
import Foundation
@testable import Hoursapp

@MainActor
@Suite("Storage")
struct StorageTests {
    private static func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "hoursapp-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("bootstrap creates the SQLite database with empty tables")
    func bootstrapCreatesDB() throws {
        let dir = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storage = Storage(directory: dir)
        try storage.bootstrap()

        let dbURL = dir.appending(path: "hoursapp.sqlite")
        #expect(FileManager.default.fileExists(atPath: dbURL.path))
        #expect(storage.clients.isEmpty)
        #expect(storage.tasks.isEmpty)
        #expect(storage.entries.isEmpty)
        #expect(storage.favorites.isEmpty)
    }

    @Test("upserted data round-trips through bootstrap")
    func roundTripThroughBootstrap() async throws {
        let dir = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        do {
            let storage = Storage(directory: dir)
            try storage.bootstrap()
            storage.addClient(ClientProject(client: "Acme", project: "Site"))
            storage.addTask(name: "Design", for: "Acme")
            storage.upsertEntry(Entry(
                id: "abc",
                date: "2026-05-05",
                client: "Acme",
                project: "Site",
                task: "Design",
                seconds: 1800,
                notes: "kickoff, with comma",
                startedAt: "2026-05-05T09:00:00Z",
                stoppedAt: "2026-05-05T09:30:00Z"
            ))
            await storage.flushPendingWrites()
        }

        let reopened = Storage(directory: dir)
        try reopened.bootstrap()
        #expect(reopened.clients == [ClientProject(client: "Acme", project: "Site")])
        #expect(reopened.tasks == [TaskType(client: "Acme", name: "Design")])
        #expect(reopened.entries.count == 1)
        let e = try #require(reopened.entries.first)
        #expect(e.id == "abc")
        #expect(e.notes == "kickoff, with comma")
        #expect(e.seconds == 1800)
        #expect(e.isRunning == false)
    }

    @Test("running entry has empty stopped_at and survives reload")
    func runningEntryPersists() async throws {
        let dir = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storage = Storage(directory: dir)
        try storage.bootstrap()
        storage.upsertEntry(Entry(
            id: "run1",
            date: "2026-05-05",
            client: "Acme",
            project: "Site",
            task: "Design",
            seconds: 0,
            notes: "",
            startedAt: "2026-05-05T09:00:00Z",
            stoppedAt: nil
        ))
        await storage.flushPendingWrites()

        let reopened = Storage(directory: dir)
        try reopened.bootstrap()
        let running = try #require(reopened.runningEntry())
        #expect(running.id == "run1")
        #expect(running.isRunning)
    }

    @Test("addClient and addTask are idempotent")
    func idempotent() {
        let dir = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storage = Storage(directory: dir)
        try? storage.bootstrap()
        storage.addClient(ClientProject(client: "Acme", project: "Site"))
        storage.addClient(ClientProject(client: "Acme", project: "Site"))
        storage.addTask(name: "Design", for: "Acme")
        storage.addTask(name: "Design", for: "Acme")
        #expect(storage.clients.count == 1)
        #expect(storage.tasks.count == 1)
    }

    @Test("favorites round-trip and idempotent add/remove")
    func favoritesRoundTrip() async throws {
        let dir = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        do {
            let storage = Storage(directory: dir)
            try storage.bootstrap()
            let f = Favorite(client: "Acme", project: "Site", task: "Design")
            storage.addFavorite(f)
            storage.addFavorite(f)
            #expect(storage.favorites == [f])
            #expect(storage.isFavorite(client: "Acme", project: "Site", task: "Design"))
            await storage.flushPendingWrites()
        }

        let reopened = Storage(directory: dir)
        try reopened.bootstrap()
        #expect(reopened.favorites == [Favorite(client: "Acme", project: "Site", task: "Design")])

        reopened.removeFavorite(Favorite(client: "Acme", project: "Site", task: "Design"))
        #expect(reopened.favorites.isEmpty)
        #expect(!reopened.isFavorite(client: "Acme", project: "Site", task: "Design"))
    }

    @Test("projects(for:) filters by client")
    func projectsForClient() {
        let dir = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storage = Storage(directory: dir)
        try? storage.bootstrap()
        storage.addClient(ClientProject(client: "Acme", project: "Site"))
        storage.addClient(ClientProject(client: "Acme", project: "App"))
        storage.addClient(ClientProject(client: "Other", project: "Misc"))
        #expect(storage.projects(for: "Acme") == ["App", "Site"])
        #expect(storage.projects(for: "Other") == ["Misc"])
        #expect(storage.projects(for: "Nope") == [])
    }
}
