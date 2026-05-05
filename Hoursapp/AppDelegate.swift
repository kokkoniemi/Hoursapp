import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppPreferences.registerDefaults()
        LaunchAtLogin.syncDefaultsWithSystem()
        do {
            try Storage.shared.bootstrap()
        } catch {
            NSLog("Hoursapp storage bootstrap failed: \(error)")
        }
        menuBarController = MenuBarController()
        IdleDetector.shared.start()
        SleepWatcher.shared.start()
        LongRunDetector.shared.start()
    }
}
