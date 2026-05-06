import Testing
import Foundation
@testable import Hoursapp

@MainActor
@Suite("Storage timers")
struct StorageTimerTests {
    @Test("startTimer creates a fresh entry when none matches")
    func startCreatesEntry() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        let day = TestSupport.day(.now)
        storage.startTimer(client: "Acme", project: "Site", task: "Design", on: day)

        let running = try #require(storage.runningEntry())
        #expect(running.client == "Acme")
        #expect(running.project == "Site")
        #expect(running.task == "Design")
        #expect(running.date == day)
        #expect(running.seconds == 0)
        #expect(running.isRunning)
        #expect(storage.clients.contains(ClientProject(client: "Acme", project: "Site")))
        #expect(storage.tasks.contains(TaskType(client: "Acme", name: "Design")))
    }

    @Test("startTimer reuses an existing same-day combo entry")
    func startReusesEntry() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        let day = TestSupport.day(.now)
        let existingId = "existing-id"
        storage.upsertEntry(TestSupport.entry(
            id: existingId, date: day, seconds: 600,
            stoppedAt: Date.now.addingTimeInterval(-100)
        ))

        storage.startTimer(client: "Acme", project: "Site", task: "Design", on: day)

        #expect(storage.entries.count == 1)
        let running = try #require(storage.runningEntry())
        #expect(running.id == existingId)
        #expect(running.seconds == 600) // accumulated time preserved
        #expect(running.stoppedAt == nil)
        #expect(running.startedAt != nil)
    }

    @Test("startTimer stops any other running timer first")
    func startStopsOther() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        let day = TestSupport.day(.now)
        storage.upsertEntry(TestSupport.entry(
            id: "first", date: day, client: "A", project: "P", task: "T",
            startedAt: Date.now.addingTimeInterval(-30),
            stoppedAt: nil
        ))

        storage.startTimer(client: "B", project: "Q", task: "U", on: day)

        let runningEntries = storage.entries.filter(\.isRunning)
        #expect(runningEntries.count == 1)
        let stillRunning = try #require(runningEntries.first)
        #expect(stillRunning.client == "B")

        let firstReloaded = try #require(storage.entries.first(where: { $0.id == "first" }))
        #expect(!firstReloaded.isRunning)
        #expect(firstReloaded.seconds >= 30)
    }

    @Test("stopTimer accumulates elapsed seconds and clears the running flag")
    func stopAccumulates() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        let day = TestSupport.day(.now)
        storage.upsertEntry(TestSupport.entry(
            id: "r", date: day, seconds: 100,
            startedAt: Date.now.addingTimeInterval(-90),
            stoppedAt: nil
        ))

        storage.stopTimer()

        let stopped = try #require(storage.entries.first(where: { $0.id == "r" }))
        #expect(!stopped.isRunning)
        #expect(stopped.stoppedAt != nil)
        #expect(stopped.seconds >= 190 && stopped.seconds <= 200,
                "expected base 100 + ~90s elapsed, got \(stopped.seconds)")
    }

    @Test("stopTimer is a no-op when nothing is running")
    func stopNoOp() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        storage.upsertEntry(TestSupport.entry(
            id: "done", date: TestSupport.day(.now), seconds: 100,
            stoppedAt: Date.now.addingTimeInterval(-10)
        ))
        storage.stopTimer()
        let entry = try #require(storage.entries.first)
        #expect(entry.seconds == 100)
    }

    @Test("displayedSeconds returns base for non-running, base+elapsed for running")
    func displayedSeconds() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        let now = Date.now
        let runningStart = now.addingTimeInterval(-120)
        let stopped = TestSupport.entry(
            id: "s", date: TestSupport.day(now), seconds: 500,
            stoppedAt: now.addingTimeInterval(-1)
        )
        let running = TestSupport.entry(
            id: "r", date: TestSupport.day(now), seconds: 50,
            startedAt: runningStart, stoppedAt: nil
        )

        #expect(storage.displayedSeconds(for: stopped, at: now) == 500)
        #expect(storage.displayedSeconds(for: running, at: now) == 50 + 120)
    }

    @Test("todayTotalSeconds sums today's entries (live for running)")
    func todayTotal() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        let now = Date.now
        let today = TestSupport.day(now)
        let yesterday = TestSupport.day(now.addingTimeInterval(-86_400))

        storage.upsertEntry(TestSupport.entry(
            id: "y", date: yesterday, seconds: 9999,
            stoppedAt: now.addingTimeInterval(-3600)
        ))
        storage.upsertEntry(TestSupport.entry(
            id: "t1", date: today, seconds: 1200,
            stoppedAt: now.addingTimeInterval(-10)
        ))
        storage.upsertEntry(TestSupport.entry(
            id: "t2", date: today, seconds: 0,
            startedAt: now.addingTimeInterval(-300),
            stoppedAt: nil
        ))

        let total = storage.todayTotalSeconds(at: now)
        #expect(total == 1200 + 300)
    }

    @Test("discardRunningIdle bumps startedAt forward without exceeding now")
    func discardIdle() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        let day = TestSupport.day(.now)
        let originalStart = Date.now.addingTimeInterval(-600)
        storage.upsertEntry(TestSupport.entry(
            id: "r", date: day, seconds: 0, startedAt: originalStart, stoppedAt: nil
        ))

        storage.discardRunningIdle(seconds: 200)
        let bumped = try #require(storage.runningStartedAtDate())
        #expect(bumped.timeIntervalSince(originalStart) >= 199)
        #expect(bumped <= Date.now.addingTimeInterval(1))

        // Asking to discard more than elapsed clamps to now.
        storage.discardRunningIdle(seconds: 999_999)
        let clamped = try #require(storage.runningStartedAtDate())
        #expect(clamped.timeIntervalSince(.now) < 2)
    }

    @Test("stopTimerDiscardingIdle drops idle then stops")
    func stopDiscarding() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        let day = TestSupport.day(.now)
        storage.upsertEntry(TestSupport.entry(
            id: "r", date: day, seconds: 100,
            startedAt: Date.now.addingTimeInterval(-300),
            stoppedAt: nil
        ))

        storage.stopTimerDiscardingIdle(seconds: 200)
        let entry = try #require(storage.entries.first)
        #expect(!entry.isRunning)
        // 300s elapsed - 200s idle = ~100s kept, plus 100 base.
        #expect(entry.seconds >= 195 && entry.seconds <= 210,
                "expected ~200s, got \(entry.seconds)")
    }

    @Test("deleteEntry removes by id")
    func deleteEntry() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        storage.upsertEntry(TestSupport.entry(id: "a", date: "2026-01-01"))
        storage.upsertEntry(TestSupport.entry(id: "b", date: "2026-01-01"))
        storage.deleteEntry(id: "a")
        #expect(storage.entries.map(\.id) == ["b"])
    }

    @Test("upsertEntry replaces by id")
    func upsertReplaces() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        storage.upsertEntry(TestSupport.entry(id: "a", date: "2026-01-01", seconds: 10))
        storage.upsertEntry(TestSupport.entry(id: "a", date: "2026-01-01", seconds: 20))
        #expect(storage.entries.count == 1)
        #expect(storage.entries[0].seconds == 20)
    }

    @Test("mostRecentEntry variants prefer the last appended match")
    func mostRecent() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        storage.upsertEntry(TestSupport.entry(id: "1", date: "2026-01-01", client: "A", project: "P1", task: "T"))
        storage.upsertEntry(TestSupport.entry(id: "2", date: "2026-01-02", client: "A", project: "P2", task: "T"))
        storage.upsertEntry(TestSupport.entry(id: "3", date: "2026-01-03", client: "B", project: "PB", task: "T"))

        #expect(storage.mostRecentEntry()?.id == "3")
        #expect(storage.mostRecentEntry(client: "A")?.id == "2")
        #expect(storage.mostRecentEntry(client: "A", project: "P1")?.id == "1")
        #expect(storage.mostRecentEntry(client: "Nope") == nil)
    }

    @Test("uniqueClientNames dedupes and sorts")
    func uniqueClients() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        storage.addClient(ClientProject(client: "Beta", project: "X"))
        storage.addClient(ClientProject(client: "Alpha", project: "Y"))
        storage.addClient(ClientProject(client: "Alpha", project: "Z"))
        #expect(storage.uniqueClientNames() == ["Alpha", "Beta"])
    }

    @Test("taskNames sorted")
    func taskNamesSorted() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        storage.addClient(ClientProject(client: "Acme", project: "Site"))
        storage.addTask(name: "Zeta", for: "Acme")
        storage.addTask(name: "Alpha", for: "Acme")
        #expect(storage.taskNames(for: "Acme") == ["Alpha", "Zeta"])
    }

    @Test("entries(on:) filters by date string")
    func entriesOnDay() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        storage.upsertEntry(TestSupport.entry(id: "a", date: "2026-01-01"))
        storage.upsertEntry(TestSupport.entry(id: "b", date: "2026-01-02"))
        #expect(storage.entries(on: "2026-01-01").map(\.id) == ["a"])
        #expect(storage.entries(on: "2026-01-09") == [])
    }

    @Test("debounced writes survive flush and reload")
    func debouncedRoundTrip() async throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        storage.addClient(ClientProject(client: "Acme", project: "Site"))
        for i in 0..<5 {
            storage.addTask(name: "T\(i)", for: "Acme")
        }
        await storage.flushPendingWrites()

        let reopened = Storage(directory: dir)
        try reopened.bootstrap()
        #expect(reopened.tasks.count == 5)
    }
}
