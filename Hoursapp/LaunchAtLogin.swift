import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Hoursapp: launch-at-login change failed: \(error)")
        }
    }

    static func syncDefaultsWithSystem() {
        UserDefaults.standard.set(isEnabled, forKey: PrefKey.launchAtLogin)
    }
}
