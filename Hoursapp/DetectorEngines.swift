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
