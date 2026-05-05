import Foundation

enum PrefKey {
    static let launchAtLogin = "launchAtLogin"
    static let idleDetectionEnabled = "idleDetectionEnabled"
    static let idleThresholdMinutes = "idleThresholdMinutes"
}

enum AppPreferences {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PrefKey.launchAtLogin: false,
            PrefKey.idleDetectionEnabled: true,
            PrefKey.idleThresholdMinutes: 45
        ])
    }
}
