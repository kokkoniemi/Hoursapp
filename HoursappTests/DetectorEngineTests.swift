import Testing
import Foundation
@testable import Hoursapp

@Suite("IdleEngine")
struct IdleEngineTests {
    private static let now = Date(timeIntervalSince1970: 1_730_000_000)

    @Test("disabled feature always skips")
    func disabled() {
        let d = IdleEngine.decide(
            now: Self.now, enabled: false,
            rawIdle: 9999, runningElapsed: 9999,
            thresholdMinutes: 1, lastPromptDismissedAt: nil
        )
        #expect(d == .skip)
    }

    @Test("no running timer skips")
    func noRunning() {
        let d = IdleEngine.decide(
            now: Self.now, enabled: true,
            rawIdle: 9999, runningElapsed: nil,
            thresholdMinutes: 1, lastPromptDismissedAt: nil
        )
        #expect(d == .skip)
    }

    @Test("below threshold skips")
    func belowThreshold() {
        let d = IdleEngine.decide(
            now: Self.now, enabled: true,
            rawIdle: 10 * 60 - 1, runningElapsed: 99_999,
            thresholdMinutes: 10, lastPromptDismissedAt: nil
        )
        #expect(d == .skip)
    }

    @Test("at threshold prompts with idle seconds")
    func atThreshold() {
        let d = IdleEngine.decide(
            now: Self.now, enabled: true,
            rawIdle: 10 * 60, runningElapsed: 99_999,
            thresholdMinutes: 10, lastPromptDismissedAt: nil
        )
        #expect(d == .prompt(idleSeconds: 600))
    }

    @Test("idle clamped to running elapsed")
    func clampToElapsed() {
        let d = IdleEngine.decide(
            now: Self.now, enabled: true,
            rawIdle: 99_999, runningElapsed: 605,
            thresholdMinutes: 10, lastPromptDismissedAt: nil
        )
        #expect(d == .prompt(idleSeconds: 605))
    }

    @Test("clamping below threshold cancels the prompt")
    func clampBelowThreshold() {
        // System reports 30 min idle but timer has only run for 5 min.
        let d = IdleEngine.decide(
            now: Self.now, enabled: true,
            rawIdle: 1800, runningElapsed: 300,
            thresholdMinutes: 10, lastPromptDismissedAt: nil
        )
        #expect(d == .skip)
    }

    @Test("recent prompt within 60s suppresses")
    func recentSuppresses() {
        let lastDismissed = Self.now.addingTimeInterval(-30)
        let d = IdleEngine.decide(
            now: Self.now, enabled: true,
            rawIdle: 9999, runningElapsed: 9999,
            thresholdMinutes: 1, lastPromptDismissedAt: lastDismissed
        )
        #expect(d == .skip)
    }

    @Test("60s after dismissal we prompt again")
    func cooldownPasses() {
        let lastDismissed = Self.now.addingTimeInterval(-60)
        let d = IdleEngine.decide(
            now: Self.now, enabled: true,
            rawIdle: 600, runningElapsed: 9999,
            thresholdMinutes: 10, lastPromptDismissedAt: lastDismissed
        )
        #expect(d == .prompt(idleSeconds: 600))
    }

    @Test("non-positive thresholdMinutes clamps to 1 minute")
    func thresholdMinAtLeastOne() {
        let d = IdleEngine.decide(
            now: Self.now, enabled: true,
            rawIdle: 60, runningElapsed: 9999,
            thresholdMinutes: 0, lastPromptDismissedAt: nil
        )
        #expect(d == .prompt(idleSeconds: 60))
    }
}

@Suite("SleepEngine")
struct SleepEngineTests {
    @Test("disabled feature always skips")
    func disabled() {
        let d = SleepEngine.decide(
            enabled: false,
            sleptSeconds: 9999, runningElapsedAtWake: 99_999,
            thresholdMinutes: 1
        )
        #expect(d == .skip)
    }

    @Test("no running timer skips")
    func noRunning() {
        let d = SleepEngine.decide(
            enabled: true,
            sleptSeconds: 9999, runningElapsedAtWake: nil,
            thresholdMinutes: 1
        )
        #expect(d == .skip)
    }

    @Test("below threshold skips")
    func belowThreshold() {
        let d = SleepEngine.decide(
            enabled: true,
            sleptSeconds: 10 * 60 - 1, runningElapsedAtWake: 99_999,
            thresholdMinutes: 10
        )
        #expect(d == .skip)
    }

    @Test("at threshold prompts with slept seconds")
    func atThreshold() {
        let d = SleepEngine.decide(
            enabled: true,
            sleptSeconds: 10 * 60, runningElapsedAtWake: 99_999,
            thresholdMinutes: 10
        )
        #expect(d == .prompt(sleptSeconds: 600))
    }

    @Test("slept clamped to running elapsed")
    func clampToElapsed() {
        // Mac slept 2h but the timer was only started 8m ago — we can't
        // subtract more than the entry has on it.
        let d = SleepEngine.decide(
            enabled: true,
            sleptSeconds: 7200, runningElapsedAtWake: 480,
            thresholdMinutes: 5
        )
        #expect(d == .prompt(sleptSeconds: 480))
    }

    @Test("clamping below threshold cancels the prompt")
    func clampBelowThreshold() {
        let d = SleepEngine.decide(
            enabled: true,
            sleptSeconds: 7200, runningElapsedAtWake: 60,
            thresholdMinutes: 10
        )
        #expect(d == .skip)
    }

    @Test("non-positive thresholdMinutes clamps to 1 minute")
    func thresholdMinAtLeastOne() {
        let d = SleepEngine.decide(
            enabled: true,
            sleptSeconds: 60, runningElapsedAtWake: 9999,
            thresholdMinutes: 0
        )
        #expect(d == .prompt(sleptSeconds: 60))
    }
}

@Suite("SleepWatcher.durationText")
struct SleepWatcherDurationTests {
    @Test("under a minute rounds up to 1 minute")
    func subMinute() {
        #expect(SleepWatcher.durationText(30) == "1 minute")
    }

    @Test("pluralizes minutes")
    func minutes() {
        #expect(SleepWatcher.durationText(120) == "2 minutes")
    }

    @Test("singular hour, no minute remainder")
    func singularHour() {
        #expect(SleepWatcher.durationText(3600) == "1 hour")
    }

    @Test("hours and minutes")
    func hoursAndMinutes() {
        #expect(SleepWatcher.durationText(8 * 3600 + 5 * 60) == "8 hours 5 minutes")
    }

    @Test("plural hours, singular minute")
    func mixedPluralization() {
        #expect(SleepWatcher.durationText(2 * 3600 + 60) == "2 hours 1 minute")
    }
}

@Suite("LongRunEngine")
struct LongRunEngineTests {
    @Test("disabled feature always skips")
    func disabled() {
        let d = LongRunEngine.decide(
            enabled: false, runningEntryId: "x",
            elapsedSeconds: 100_000, thresholdHours: 1, warnedEntryId: nil
        )
        #expect(d == .skip)
    }

    @Test("no running timer skips")
    func noRunning() {
        let d = LongRunEngine.decide(
            enabled: true, runningEntryId: nil,
            elapsedSeconds: 100_000, thresholdHours: 1, warnedEntryId: nil
        )
        #expect(d == .skip)
    }

    @Test("already warned for this entry skips")
    func alreadyWarned() {
        let d = LongRunEngine.decide(
            enabled: true, runningEntryId: "abc",
            elapsedSeconds: 9 * 3600, thresholdHours: 8, warnedEntryId: "abc"
        )
        #expect(d == .skip)
    }

    @Test("warning for a different entry does not suppress")
    func warnedDifferentEntry() {
        let d = LongRunEngine.decide(
            enabled: true, runningEntryId: "new",
            elapsedSeconds: 9 * 3600, thresholdHours: 8, warnedEntryId: "old"
        )
        #expect(d == .prompt(elapsedSeconds: 9 * 3600))
    }

    @Test("below threshold skips")
    func belowThreshold() {
        let d = LongRunEngine.decide(
            enabled: true, runningEntryId: "x",
            elapsedSeconds: 8 * 3600 - 1, thresholdHours: 8, warnedEntryId: nil
        )
        #expect(d == .skip)
    }

    @Test("at threshold prompts")
    func atThreshold() {
        let d = LongRunEngine.decide(
            enabled: true, runningEntryId: "x",
            elapsedSeconds: 8 * 3600, thresholdHours: 8, warnedEntryId: nil
        )
        #expect(d == .prompt(elapsedSeconds: 8 * 3600))
    }

    @Test("non-positive thresholdHours clamps to 1 hour")
    func thresholdMinAtLeastOne() {
        let d = LongRunEngine.decide(
            enabled: true, runningEntryId: "x",
            elapsedSeconds: 3600, thresholdHours: 0, warnedEntryId: nil
        )
        #expect(d == .prompt(elapsedSeconds: 3600))
    }
}
