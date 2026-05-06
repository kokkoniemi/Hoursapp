import Foundation

enum ExcelExporter {
    static func export(entries: [Entry], period: ExportPeriod, to url: URL) throws {
        let workbook = buildWorkbook(entries: entries, period: period)
        try workbook.write(to: url)
    }

    static func buildWorkbook(entries: [Entry], period: ExportPeriod) -> XlsxWorkbook {
        let scoped = ExportPeriod.filter(entries: entries, by: period)
        let workbook = XlsxWorkbook()

        switch period {
        case .month(let year, let month):
            buildMonthlyWorkbook(workbook, year: year, month: month, entries: scoped)
        case .allMonths:
            buildAllMonthsWorkbook(workbook, entries: scoped)
        }

        return workbook
    }

    // MARK: - Single month

    private static func buildMonthlyWorkbook(
        _ workbook: XlsxWorkbook, year: Int, month: Int, entries: [Entry]
    ) {
        addSummarySheet(to: workbook, year: year, month: month, entries: entries)
        addEntriesSheet(to: workbook, name: "Entries", entries: entries)
    }

    private static func addSummarySheet(
        to workbook: XlsxWorkbook, year: Int, month: Int, entries: [Entry]
    ) {
        let sheet = workbook.addSheet(name: "Summary")
        sheet.setColumnWidth(col: 1, width: 22)
        sheet.setColumnWidth(col: 2, width: 22)
        sheet.setColumnWidth(col: 3, width: 22)
        sheet.setColumnWidth(col: 4, width: 10)
        sheet.setColumnWidth(col: 5, width: 8)

        let totalHours = Double(entries.reduce(0) { $0 + $1.seconds }) / 3600.0
        sheet.setText(row: 1, col: 1,
                      "\(ExportPeriod.monthLabel(year: year, month: month)) — \(formatHours(totalHours)) h",
                      style: .bold)

        let header = ["Client", "Project", "Task", "Hours", "Days"]
        for (i, h) in header.enumerated() {
            sheet.setText(row: 3, col: i + 1, h, style: .bold)
        }

        let groups = groupByCombo(entries)
        var row = 4
        for group in groups {
            sheet.setText(row: row, col: 1, group.client)
            sheet.setText(row: row, col: 2, group.project)
            sheet.setText(row: row, col: 3, group.task)
            sheet.setNumber(row: row, col: 4, Double(group.totalSeconds) / 3600.0, style: .decimal2)
            sheet.setNumber(row: row, col: 5, Double(group.distinctDays), style: .default)
            row += 1
        }

        // Total row
        if !groups.isEmpty {
            sheet.setText(row: row, col: 3, "Total", style: .bold)
            sheet.setFormula(row: row, col: 4, "SUM(D4:D\(row - 1))", style: .boldDecimal2)
        } else {
            sheet.setText(row: row, col: 1, "(no stopped entries in this month)", style: .default)
        }
    }

    // MARK: - All months

    private static func buildAllMonthsWorkbook(_ workbook: XlsxWorkbook, entries: [Entry]) {
        let summary = workbook.addSheet(name: "Summary")
        summary.setColumnWidth(col: 1, width: 14)
        summary.setColumnWidth(col: 2, width: 10)
        summary.setColumnWidth(col: 3, width: 10)
        summary.setColumnWidth(col: 4, width: 12)

        for (i, h) in ["Month", "Hours", "Entries", "Days worked"].enumerated() {
            summary.setText(row: 1, col: i + 1, h, style: .bold)
        }

        let buckets = bucketByMonth(entries).sorted { $0.key < $1.key }
        var row = 2
        for (key, monthEntries) in buckets {
            let sheetName = key
            let monthSheet = workbook.addSheet(name: sheetName)
            addEntriesSheetBody(to: monthSheet, entries: monthEntries)

            summary.setText(row: row, col: 1, sheetName)
            summary.setFormula(row: row, col: 2, "SUM('\(sheetName)'!E:E)", style: .decimal2)
            summary.setNumber(row: row, col: 3, Double(monthEntries.count), style: .default)
            summary.setNumber(row: row, col: 4,
                              Double(Set(monthEntries.map(\.date)).count), style: .default)
            row += 1
        }

        if buckets.isEmpty {
            summary.setText(row: 2, col: 1, "(no stopped entries)", style: .default)
        } else {
            summary.setText(row: row, col: 1, "Total", style: .bold)
            summary.setFormula(row: row, col: 2, "SUM(B2:B\(row - 1))", style: .boldDecimal2)
        }
    }

    // MARK: - Per-entry sheets

    private static func addEntriesSheet(to workbook: XlsxWorkbook, name: String, entries: [Entry]) {
        let sheet = workbook.addSheet(name: name)
        addEntriesSheetBody(to: sheet, entries: entries)
    }

    private static func addEntriesSheetBody(to sheet: XlsxSheet, entries: [Entry]) {
        sheet.setColumnWidth(col: 1, width: 12)
        sheet.setColumnWidth(col: 2, width: 22)
        sheet.setColumnWidth(col: 3, width: 22)
        sheet.setColumnWidth(col: 4, width: 22)
        sheet.setColumnWidth(col: 5, width: 8)
        sheet.setColumnWidth(col: 6, width: 60)

        for (i, h) in ["Date", "Client", "Project", "Task", "Hours", "Notes"].enumerated() {
            sheet.setText(row: 1, col: i + 1, h, style: .bold)
        }

        let sorted = entries.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            if lhs.client != rhs.client { return lhs.client < rhs.client }
            if lhs.project != rhs.project { return lhs.project < rhs.project }
            return lhs.task < rhs.task
        }

        var row = 2
        for entry in sorted {
            sheet.setText(row: row, col: 1, entry.date)
            sheet.setText(row: row, col: 2, entry.client)
            sheet.setText(row: row, col: 3, entry.project)
            sheet.setText(row: row, col: 4, entry.task)
            sheet.setNumber(row: row, col: 5, Double(entry.seconds) / 3600.0, style: .decimal2)
            sheet.setText(row: row, col: 6, entry.notes)
            row += 1
        }

        if !sorted.isEmpty {
            sheet.setText(row: row, col: 4, "Total", style: .bold)
            sheet.setFormula(row: row, col: 5, "SUM(E2:E\(row - 1))", style: .boldDecimal2)
        }
    }

    // MARK: - Aggregation helpers

    private struct ComboGroup {
        var client: String
        var project: String
        var task: String
        var totalSeconds: Int
        var distinctDays: Int
    }

    private static func groupByCombo(_ entries: [Entry]) -> [ComboGroup] {
        struct Key: Hashable { let client: String; let project: String; let task: String }
        var bucket: [Key: (seconds: Int, days: Set<String>)] = [:]
        for entry in entries {
            let key = Key(client: entry.client, project: entry.project, task: entry.task)
            var current = bucket[key] ?? (0, [])
            current.seconds += entry.seconds
            current.days.insert(entry.date)
            bucket[key] = current
        }
        return bucket
            .map { key, value in
                ComboGroup(
                    client: key.client, project: key.project, task: key.task,
                    totalSeconds: value.seconds, distinctDays: value.days.count
                )
            }
            .sorted { lhs, rhs in
                if lhs.client != rhs.client { return lhs.client < rhs.client }
                if lhs.project != rhs.project { return lhs.project < rhs.project }
                return lhs.task < rhs.task
            }
    }

    private static func bucketByMonth(_ entries: [Entry]) -> [String: [Entry]] {
        var buckets: [String: [Entry]] = [:]
        for entry in entries {
            // entry.date is yyyy-MM-dd; the month key is the first 7 chars.
            guard entry.date.count >= 7 else { continue }
            let key = String(entry.date.prefix(7))
            buckets[key, default: []].append(entry)
        }
        return buckets
    }

    private static func formatHours(_ hours: Double) -> String {
        String(format: "%.2f", hours)
    }
}
