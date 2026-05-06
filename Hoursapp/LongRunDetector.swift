import AppKit

@MainActor
final class LongRunDetector {
    static let shared = LongRunDetector()

    private var ticker: Timer?
    private var alertOpen = false
    private var warnedEntryId: String?

    func start() {
        stop()
        ticker = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
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
        guard UserDefaults.standard.bool(forKey: PrefKey.longRunWarningEnabled) else { return }
        guard let running = Storage.shared.runningEntry() else {
            warnedEntryId = nil
            return
        }
        if warnedEntryId == running.id { return }

        let elapsed = Storage.shared.displayedSeconds(for: running)
        let thresholdHours = max(UserDefaults.standard.integer(forKey: PrefKey.longRunWarningHours), 1)
        let thresholdSeconds = thresholdHours * 3600

        if elapsed >= thresholdSeconds {
            warnedEntryId = running.id
            promptLongRun(entry: running, elapsedSeconds: elapsed)
        }
    }

    private func promptLongRun(entry: Entry, elapsedSeconds: Int) {
        alertOpen = true
        defer { alertOpen = false }

        let hours = elapsedSeconds / 3600
        let alert = NSAlert()
        alert.messageText = "Timer running for \(hours) hours"
        alert.informativeText = "\(entry.project) — \(entry.task) has been tracking for \(hours) hours. Did you forget to stop?"
        alert.addButton(withTitle: "Keep going")
        alert.addButton(withTitle: "Stop timer")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            Storage.shared.stopTimer()
        }
    }
}
