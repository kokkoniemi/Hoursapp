import AppKit
import CoreGraphics

@MainActor
final class IdleDetector {
    static let shared = IdleDetector()

    private var ticker: Timer?
    private var alertOpen = false
    private var lastPromptDismissedAt: Date?

    func start() {
        stop()
        ticker = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard !alertOpen else { return }

        let runningElapsed = Storage.shared.runningEntry().map { Storage.shared.displayedSeconds(for: $0) }
        let rawIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: Self.anyInputEventType)

        let decision = IdleEngine.decide(
            now: .now,
            enabled: UserDefaults.standard.bool(forKey: PrefKey.idleDetectionEnabled),
            rawIdle: rawIdle,
            runningElapsed: runningElapsed,
            thresholdMinutes: UserDefaults.standard.integer(forKey: PrefKey.idleThresholdMinutes),
            lastPromptDismissedAt: lastPromptDismissedAt
        )

        if case .prompt(let idleSeconds) = decision {
            promptIdle(idleSeconds: idleSeconds)
        }
    }

    private static let anyInputEventType = CGEventType(rawValue: ~0)!

    private func promptIdle(idleSeconds: Int) {
        alertOpen = true
        defer {
            alertOpen = false
            lastPromptDismissedAt = .now
        }

        let minutes = idleSeconds / 60
        let minutesText = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        let alert = NSAlert()
        alert.messageText = "Welcome back — were you away for \(minutesText)?"
        alert.informativeText = "Your timer kept running. Keep that time on the entry, take it off, or stop the timer."
        alert.addButton(withTitle: "Keep")
        alert.addButton(withTitle: "Subtract idle time")
        alert.addButton(withTitle: "Stop now")

        let promptShownAt = Date.now
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        let modalDuration = max(0, Int(Date.now.timeIntervalSince(promptShownAt)))
        let totalIdle = idleSeconds + modalDuration

        switch response {
        case .alertSecondButtonReturn:
            Storage.shared.discardRunningIdle(seconds: totalIdle)
        case .alertThirdButtonReturn:
            Storage.shared.stopTimerDiscardingIdle(seconds: totalIdle)
        default:
            break
        }
    }
}
