import AppKit

@MainActor
final class SleepWatcher {
    static let shared = SleepWatcher()

    private var observers: [NSObjectProtocol] = []
    private var pausedFavorite: Favorite?

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
        guard UserDefaults.standard.bool(forKey: PrefKey.pauseOnSleep) else { return }
        guard let running = Storage.shared.runningEntry() else { return }
        pausedFavorite = Favorite(client: running.client, project: running.project, task: running.task)
        Storage.shared.stopTimer()
    }

    private func handleWake() {
        guard let fav = pausedFavorite else { return }
        pausedFavorite = nil
        guard UserDefaults.standard.bool(forKey: PrefKey.pauseOnSleep) else { return }
        let today = DateFormat.day(from: .now)
        Storage.shared.startTimer(client: fav.client, project: fav.project, task: fav.task, on: today)
    }
}
