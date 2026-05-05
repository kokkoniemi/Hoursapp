import Foundation

struct ClientProject: Hashable, Sendable {
    var client: String
    var project: String
}

struct TaskType: Hashable, Sendable {
    var name: String
}

struct Favorite: Hashable, Sendable {
    var client: String
    var project: String
    var task: String
}

struct Entry: Identifiable, Hashable, Sendable {
    var id: String
    var date: String
    var client: String
    var project: String
    var task: String
    var seconds: Int
    var notes: String
    var startedAt: String?
    var stoppedAt: String?

    var isRunning: Bool { stoppedAt == nil }
}

enum DateFormat {
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let timestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func day(from date: Date) -> String { dayFormatter.string(from: date) }
    static func timestamp(from date: Date) -> String { timestampFormatter.string(from: date) }
}
