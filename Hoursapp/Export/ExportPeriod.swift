import Foundation

enum ExportPeriod: Equatable, Hashable {
    case month(year: Int, month: Int)
    case allMonths

    var displayName: String {
        switch self {
        case .month(let y, let m):
            return Self.monthLabel(year: y, month: m)
        case .allMonths:
            return "All months"
        }
    }

    var defaultFilename: String {
        switch self {
        case .month(let y, let m):
            return String(format: "hoursapp-%04d-%02d.xlsx", y, m)
        case .allMonths:
            return "hoursapp-all-\(DateFormat.day(from: .now)).xlsx"
        }
    }

    /// Builds the option list to show in the export dialog: every month with at
    /// least one stopped entry, most recent first, plus "All months" at the end.
    /// Falls back to the current month if no entries exist yet.
    static func availableOptions(for entries: [Entry], today: Date = .now) -> [ExportPeriod] {
        let comps = Calendar.iso8601Local.dateComponents([.year, .month], from: today)
        let currentMonth = ExportPeriod.month(year: comps.year ?? 1970, month: comps.month ?? 1)

        var months = Set<MonthKey>()
        for entry in entries where entry.stoppedAt != nil {
            if let key = MonthKey(dayString: entry.date) {
                months.insert(key)
            }
        }

        let monthOptions = months
            .sorted(by: { ($0.year, $0.month) > ($1.year, $1.month) })
            .map { ExportPeriod.month(year: $0.year, month: $0.month) }

        var options = monthOptions
        if !options.contains(currentMonth) {
            options.insert(currentMonth, at: 0)
        }
        options.append(.allMonths)
        return options
    }

    /// Filters entries down to the period's range, excluding running entries.
    static func filter(entries: [Entry], by period: ExportPeriod) -> [Entry] {
        let stopped = entries.filter { $0.stoppedAt != nil }
        switch period {
        case .allMonths:
            return stopped
        case .month(let year, let month):
            let prefix = String(format: "%04d-%02d", year, month)
            return stopped.filter { $0.date.hasPrefix(prefix) }
        }
    }

    static func monthLabel(year: Int, month: Int) -> String {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = 1
        let date = Calendar.iso8601Local.date(from: c) ?? Date(timeIntervalSince1970: 0)
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }
}

private struct MonthKey: Hashable {
    let year: Int
    let month: Int

    init?(dayString: String) {
        // dayString is "yyyy-MM-dd"
        let parts = dayString.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        self.year = y
        self.month = m
    }
}

extension Calendar {
    static let iso8601Local: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .current
        return c
    }()
}
