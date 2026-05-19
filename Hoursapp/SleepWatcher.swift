import AppKit

/// Surfaces a Keep / Subtract / Stop prompt on wake when the Mac slept long
/// enough to plausibly mean the user was away. Mirrors the IdleDetector flow:
/// the timer keeps ticking through sleep, and the user gets to decide on
/// wake whether that time counts. Reuses the idle threshold so the two
/// detectors share one knob.
@MainActor
final class SleepWatcher {
    static let shared = SleepWatcher()

    private var observers: [NSObjectProtocol] = []
    private var sleepStartedAt: Date?
    private var alertOpen = false

    func start() {
        stop()
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleSleep() }
        })
        observers.append(nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        })
    }

    func stop() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.forEach { nc.removeObserver($0) }
        observers.removeAll()
    }

    private func handleSleep() {
        // Record the instant willSleep fires; on wake we'll diff against now.
        // Tracked unconditionally — the enabled check happens at prompt time so
        // toggling the preference mid-sleep still respects the latest value.
        sleepStartedAt = .now
    }

    private func handleWake() {
        guard let startedSleeping = sleepStartedAt else { return }
        sleepStartedAt = nil

        let sleptSeconds = Date.now.timeIntervalSince(startedSleeping)
        let runningElapsed = Storage.shared.runningEntry().map { Storage.shared.displayedSeconds(for: $0) }

        let decision = SleepEngine.decide(
            enabled: UserDefaults.standard.bool(forKey: PrefKey.pauseOnSleep),
            sleptSeconds: sleptSeconds,
            runningElapsedAtWake: runningElapsed,
            thresholdMinutes: UserDefaults.standard.integer(forKey: PrefKey.idleThresholdMinutes)
        )

        if case .prompt(let seconds) = decision {
            promptSlept(seconds: seconds)
        }
    }

    private func promptSlept(seconds: Int) {
        guard !alertOpen else { return }
        alertOpen = true
        defer { alertOpen = false }

        let alert = NSAlert()
        alert.messageText = "Welcome back — your Mac was asleep for \(Self.durationText(seconds))."
        alert.informativeText = "Your timer kept running. Keep that time on the entry, take it off, or stop the timer."
        alert.addButton(withTitle: "Keep")
        alert.addButton(withTitle: "Subtract sleep time")
        alert.addButton(withTitle: "Stop now")

        let promptShownAt = Date.now
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        let modalDuration = max(0, Int(Date.now.timeIntervalSince(promptShownAt)))
        // Include the time the dialog itself was on screen so the subtract
        // matches the user's mental model ("I was away that whole time").
        let totalSlept = seconds + modalDuration

        switch response {
        case .alertSecondButtonReturn:
            Storage.shared.discardRunningIdle(seconds: totalSlept)
        case .alertThirdButtonReturn:
            Storage.shared.stopTimerDiscardingIdle(seconds: totalSlept)
        default:
            break
        }
    }

    /// Human-friendly "X hour(s) Y minute(s)" / "Y minute(s)". Sleep stretches
    /// often run into hours, so a bare minute count reads worse than the idle
    /// prompt's single-unit phrasing.
    nonisolated static func durationText(_ seconds: Int) -> String {
        let totalMinutes = max(1, seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let minuteWord = minutes == 1 ? "minute" : "minutes"
        let hourWord = hours == 1 ? "hour" : "hours"
        if hours == 0 {
            return "\(totalMinutes) \(minuteWord)"
        }
        if minutes == 0 {
            return "\(hours) \(hourWord)"
        }
        return "\(hours) \(hourWord) \(minutes) \(minuteWord)"
    }
}
