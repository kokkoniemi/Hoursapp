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
        let running = Storage.shared.runningEntry()
        if running == nil { warnedEntryId = nil }

        let decision = LongRunEngine.decide(
            enabled: UserDefaults.standard.bool(forKey: PrefKey.longRunWarningEnabled),
            runningEntryId: running?.id,
            elapsedSeconds: running.map { Storage.shared.displayedSeconds(for: $0) } ?? 0,
            thresholdHours: UserDefaults.standard.integer(forKey: PrefKey.longRunWarningHours),
            warnedEntryId: warnedEntryId
        )

        if case .prompt(let elapsed) = decision, let running {
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
