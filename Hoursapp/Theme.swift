import SwiftUI

enum TimeFormat {
    static func hoursMinutes(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        return "\(h):" + String(format: "%02d", m)
    }
}
