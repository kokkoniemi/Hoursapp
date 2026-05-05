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
        guard UserDefaults.standard.bool(forKey: PrefKey.idleDetectionEnabled) else { return }
        guard Storage.shared.runningEntry() != nil else { return }

        if let last = lastPromptDismissedAt, Date.now.timeIntervalSince(last) < 60 {
            return
        }

        let idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
        let thresholdMinutes = max(UserDefaults.standard.integer(forKey: PrefKey.idleThresholdMinutes), 1)
        let threshold = TimeInterval(thresholdMinutes * 60)

        if idleSeconds >= threshold {
            promptIdle(idleSeconds: Int(idleSeconds))
        }
    }

    private func promptIdle(idleSeconds: Int) {
        alertOpen = true
        defer {
            alertOpen = false
            lastPromptDismissedAt = .now
        }

        let minutes = idleSeconds / 60
        let alert = NSAlert()
        alert.messageText = "You've been idle for \(minutes) minutes"
        alert.informativeText = "A timer is still running. What would you like to do with this idle time?"
        alert.addButton(withTitle: "Keep")
        alert.addButton(withTitle: "Discard idle time")
        alert.addButton(withTitle: "Stop timer")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        switch response {
        case .alertSecondButtonReturn:
            Storage.shared.discardRunningIdle(seconds: idleSeconds)
        case .alertThirdButtonReturn:
            Storage.shared.stopTimerDiscardingIdle(seconds: idleSeconds)
        default:
            break
        }
    }
}
