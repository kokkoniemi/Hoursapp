import Testing
import Foundation
@testable import Hoursapp

@MainActor
@Suite("Storage undo")
struct StorageUndoTests {
    @Test("deleteEntry can be undone — entry is restored with same id")
    func undoDelete() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        storage.upsertEntry(TestSupport.entry(
            id: "x", date: "2026-05-06", seconds: 600,
            stoppedAt: Date.now.addingTimeInterval(-1)
        ))
        #expect(storage.entries.count == 1)

        storage.deleteEntry(id: "x")
        #expect(storage.entries.isEmpty)
        let action = try #require(storage.lastUndoableAction)
        if case .deletedEntry = action {} else { Issue.record("expected deletedEntry"); return }

        storage.undoLastAction()
        #expect(storage.entries.count == 1)
        #expect(storage.entries.first?.id == "x")
        #expect(storage.entries.first?.seconds == 600)
        #expect(storage.lastUndoableAction == nil)
    }

    @Test("discardRunningIdle can be undone — startedAt restored")
    func undoDiscardIdle() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        let originalStart = Date.now.addingTimeInterval(-600)
        storage.upsertEntry(TestSupport.entry(
            id: "r", date: "2026-05-06",
            startedAt: originalStart, stoppedAt: nil
        ))
        let originalStartText = storage.entries.first?.startedAt
        #expect(originalStartText != nil)

        storage.discardRunningIdle(seconds: 200)
        let bumpedStartText = storage.entries.first?.startedAt
        #expect(bumpedStartText != originalStartText)

        let action = try #require(storage.lastUndoableAction)
        if case .discardedIdle = action {} else { Issue.record("expected discardedIdle"); return }

        storage.undoLastAction()
        #expect(storage.entries.first?.startedAt == originalStartText)
        #expect(storage.lastUndoableAction == nil)
    }

    @Test("any non-undo mutation clears the undo state")
    func mutationClearsUndo() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        storage.upsertEntry(TestSupport.entry(
            id: "x", date: "2026-05-06",
            stoppedAt: Date.now.addingTimeInterval(-1)
        ))
        storage.deleteEntry(id: "x")
        #expect(storage.lastUndoableAction != nil)

        // An unrelated mutation should clear the slot.
        storage.addClient(ClientProject(client: "Beta", project: "App"))
        #expect(storage.lastUndoableAction == nil)

        // ⌘Z is now a no-op.
        storage.undoLastAction()
        #expect(storage.entries.isEmpty)
    }

    @Test("undo with no pending action is a no-op")
    func undoNoOp() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        storage.undoLastAction()
        #expect(storage.lastUndoableAction == nil)
        #expect(storage.entries.isEmpty)
    }

    @Test("only the most recent destructive action is undoable")
    func onlyMostRecent() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        storage.upsertEntry(TestSupport.entry(id: "a", date: "2026-05-06",
                                              stoppedAt: Date.now.addingTimeInterval(-1)))
        storage.upsertEntry(TestSupport.entry(id: "b", date: "2026-05-06",
                                              stoppedAt: Date.now.addingTimeInterval(-1)))
        storage.deleteEntry(id: "a")
        storage.deleteEntry(id: "b")

        // Only "b" should come back; "a" is gone for good.
        storage.undoLastAction()
        #expect(storage.entries.map(\.id) == ["b"])
    }

    @Test("stopTimerDiscardingIdle does not leak a half-undo for the discard portion")
    func stopDiscardingClearsUndo() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        storage.upsertEntry(TestSupport.entry(
            id: "r", date: "2026-05-06", seconds: 100,
            startedAt: Date.now.addingTimeInterval(-300), stoppedAt: nil
        ))
        storage.stopTimerDiscardingIdle(seconds: 200)

        // The timer is stopped — undo would re-open the running state, which
        // is confusing. Make sure we don't dangle a stale undo slot.
        #expect(storage.lastUndoableAction == nil)
    }
}
