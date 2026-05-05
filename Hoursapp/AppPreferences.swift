import Foundation

enum PrefKey {
    static let launchAtLogin = "launchAtLogin"
    static let idleDetectionEnabled = "idleDetectionEnabled"
    static let idleThresholdMinutes = "idleThresholdMinutes"
    static let pauseOnSleep = "pauseOnSleep"
    static let longRunWarningEnabled = "longRunWarningEnabled"
    static let longRunWarningHours = "longRunWarningHours"
}

enum AppPreferences {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PrefKey.launchAtLogin: false,
            PrefKey.idleDetectionEnabled: true,
            PrefKey.idleThresholdMinutes: 45,
            PrefKey.pauseOnSleep: true,
            PrefKey.longRunWarningEnabled: true,
            PrefKey.longRunWarningHours: 8
        ])
    }
}
