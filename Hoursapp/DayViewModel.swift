import Foundation
import Observation

struct WeekDay: Identifiable, Hashable {
    let date: Date
    let dayKey: String
    let label: String
    let totalSeconds: Int
    let isSelected: Bool
    let isToday: Bool

    var id: String { dayKey }
}

struct EntryGroup: Identifiable, Hashable {
    let client: String
    let project: String
    let task: String
    let totalSeconds: Int
    let hasRunningEntry: Bool

    var id: String { "\(client)|\(project)|\(task)" }
}

@MainActor
@Observable
final class DayViewModel {
    var selectedDate: Date
    let storage: Storage

    private let calendar: Calendar
    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMM"
        return f
    }()
    private static let narrowWeekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f
    }()

    init(storage: Storage, today: Date = .now) {
        self.storage = storage
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .current
        self.calendar = c
        self.selectedDate = c.startOfDay(for: today)
    }

    var dayTitle: String { Self.titleFormatter.string(from: selectedDate) }

    var weekDays: [WeekDay] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else { return [] }
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            let key = DateFormat.day(from: date)
            let total = storage.entries.filter { $0.date == key }.reduce(0) { $0 + $1.seconds }
            return WeekDay(
                date: date,
                dayKey: key,
                label: Self.narrowWeekdayFormatter.string(from: date),
                totalSeconds: total,
                isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                isToday: calendar.isDateInToday(date)
            )
        }
    }

    var groupedEntries: [EntryGroup] {
        let key = DateFormat.day(from: selectedDate)
        let dayEntries = storage.entries.filter { $0.date == key }
        let buckets = Dictionary(grouping: dayEntries) { GroupKey(client: $0.client, project: $0.project, task: $0.task) }
        return buckets.map { key, items in
            EntryGroup(
                client: key.client,
                project: key.project,
                task: key.task,
                totalSeconds: items.reduce(0) { $0 + $1.seconds },
                hasRunningEntry: items.contains(where: \.isRunning)
            )
        }.sorted { lhs, rhs in
            if lhs.client != rhs.client { return lhs.client < rhs.client }
            if lhs.project != rhs.project { return lhs.project < rhs.project }
            return lhs.task < rhs.task
        }
    }

    func select(date: Date) {
        selectedDate = calendar.startOfDay(for: date)
    }

    func goToPreviousWeek() {
        if let d = calendar.date(byAdding: .day, value: -7, to: selectedDate) {
            selectedDate = d
        }
    }

    func goToNextWeek() {
        if let d = calendar.date(byAdding: .day, value: 7, to: selectedDate) {
            selectedDate = d
        }
    }

    func goToToday() { selectedDate = calendar.startOfDay(for: .now) }

    private struct GroupKey: Hashable {
        let client: String
        let project: String
        let task: String
    }
}
