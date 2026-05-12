import Foundation
import Observation

struct WeekDay: Identifiable, Hashable {
    let date: Date
    let dayKey: String
    let label: String
    let baseSeconds: Int
    let runningStartedAt: Date?
    let isSelected: Bool
    let isToday: Bool

    var id: String { dayKey }
    var hasRunningEntry: Bool { runningStartedAt != nil }

    func displayedSeconds(at now: Date) -> Int {
        guard let started = runningStartedAt else { return baseSeconds }
        return baseSeconds + max(0, Int(now.timeIntervalSince(started)))
    }
}

struct EntryGroup: Identifiable, Hashable {
    let client: String
    let project: String
    let task: String
    let baseSeconds: Int
    let runningStartedAt: Date?

    var id: String { "\(client)|\(project)|\(task)" }
    var hasRunningEntry: Bool { runningStartedAt != nil }

    func displayedSeconds(at now: Date) -> Int {
        guard let started = runningStartedAt else { return baseSeconds }
        return baseSeconds + max(0, Int(now.timeIntervalSince(started)))
    }
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

    var dayKey: String { DateFormat.day(from: selectedDate) }

    var isToday: Bool { calendar.isDateInToday(selectedDate) }

    func entries(for group: EntryGroup) -> [Entry] {
        let key = dayKey
        return storage.entries.filter {
            $0.date == key &&
            $0.client == group.client &&
            $0.project == group.project &&
            $0.task == group.task
        }
    }

    var weekDays: [WeekDay] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else { return [] }
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            let key = DateFormat.day(from: date)
            let dayEntries = storage.entries.filter { $0.date == key }
            let base = dayEntries.reduce(0) { $0 + $1.seconds }
            let runningStart = dayEntries.first(where: \.isRunning)
                .flatMap { $0.startedAt }
                .flatMap { DateFormat.timestampFormatter.date(from: $0) }
            return WeekDay(
                date: date,
                dayKey: key,
                label: Self.narrowWeekdayFormatter.string(from: date),
                baseSeconds: base,
                runningStartedAt: runningStart,
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
            let runningStart = items.first(where: \.isRunning)
                .flatMap { $0.startedAt }
                .flatMap { DateFormat.timestampFormatter.date(from: $0) }
            return EntryGroup(
                client: key.client,
                project: key.project,
                task: key.task,
                baseSeconds: items.reduce(0) { $0 + $1.seconds },
                runningStartedAt: runningStart
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

    var daysWithEntries: Set<String> {
        var keys: Set<String> = []
        for entry in storage.entries where entry.seconds > 0 || entry.isRunning {
            keys.insert(entry.date)
        }
        return keys
    }

    var monthCalendar: Calendar { calendar }

    private struct GroupKey: Hashable {
        let client: String
        let project: String
        let task: String
    }
}
