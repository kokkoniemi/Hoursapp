import Foundation

enum IdleDecision: Equatable {
    case skip
    case prompt(idleSeconds: Int)
}

enum IdleEngine {
    static func decide(
        now: Date,
        enabled: Bool,
        rawIdle: TimeInterval,
        runningElapsed: Int?,
        thresholdMinutes: Int,
        lastPromptDismissedAt: Date?
    ) -> IdleDecision {
        guard enabled else { return .skip }
        guard let runningElapsed else { return .skip }
        if let last = lastPromptDismissedAt, now.timeIntervalSince(last) < 60 {
            return .skip
        }
        let idle = min(rawIdle, TimeInterval(runningElapsed))
        let threshold = TimeInterval(max(thresholdMinutes, 1) * 60)
        guard idle >= threshold else { return .skip }
        return .prompt(idleSeconds: max(0, Int(idle)))
    }
}

enum SleepDecision: Equatable {
    case skip
    case prompt(sleptSeconds: Int)
}

/// Decides whether to surface a "Mac was asleep for X" prompt on wake. The
/// timer keeps running through sleep (parallel to how it keeps running
/// through idle), so on wake we ask the user whether to keep, subtract, or
/// stop. Reuses the idle threshold so the user only has one knob to tune.
enum SleepEngine {
    static func decide(
        enabled: Bool,
        sleptSeconds: TimeInterval,
        runningElapsedAtWake: Int?,
        thresholdMinutes: Int
    ) -> SleepDecision {
        guard enabled else { return .skip }
        guard let runningElapsed = runningElapsedAtWake else { return .skip }
        // Clamp slept-time to the running entry's elapsed: subtracting more
        // than the entry has on it would push started_at into the future.
        let slept = min(sleptSeconds, TimeInterval(runningElapsed))
        let threshold = TimeInterval(max(thresholdMinutes, 1) * 60)
        guard slept >= threshold else { return .skip }
        return .prompt(sleptSeconds: max(0, Int(slept)))
    }
}

enum LongRunDecision: Equatable {
    case skip
    case prompt(elapsedSeconds: Int)
}

enum LongRunEngine {
    static func decide(
        enabled: Bool,
        runningEntryId: String?,
        elapsedSeconds: Int,
        thresholdHours: Int,
        warnedEntryId: String?
    ) -> LongRunDecision {
        guard enabled else { return .skip }
        guard let runningEntryId else { return .skip }
        if warnedEntryId == runningEntryId { return .skip }
        let threshold = max(thresholdHours, 1) * 3600
        guard elapsedSeconds >= threshold else { return .skip }
        return .prompt(elapsedSeconds: elapsedSeconds)
    }
}
