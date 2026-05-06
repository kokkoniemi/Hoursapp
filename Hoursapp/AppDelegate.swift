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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await Storage.shared.flushPendingWrites()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
