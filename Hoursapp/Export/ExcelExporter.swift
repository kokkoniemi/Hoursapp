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
        sheet.showGridLines = false
        configureSummaryColumns(sheet: sheet)

        let monthLabel = ExportPeriod.monthLabel(year: year, month: month)
        let analytics = ExportAnalytics(entries: entries, year: year, month: month)

        var row = 1
        row = writeHero(sheet: sheet, startRow: row, monthLabel: monthLabel, analytics: analytics)
        row += 1

        guard !entries.isEmpty else {
            sheet.setText(row: row, col: 1, "(no stopped entries in this month)", style: .default)
            return
        }

        row = writeBreakdown(
            sheet: sheet, startRow: row,
            title: "By client",
            nameHeaders: ["Client"],
            rows: analytics.byClient.map { ([$0.client], $0.seconds) },
            totalSeconds: analytics.totalSeconds
        )
        row += 1

        row = writeBreakdown(
            sheet: sheet, startRow: row,
            title: "By project",
            nameHeaders: ["Client", "Project"],
            rows: analytics.byProject.map { ([$0.client, $0.project], $0.seconds) },
            totalSeconds: analytics.totalSeconds
        )
        row += 1

        row = writeBreakdown(
            sheet: sheet, startRow: row,
            title: "By task",
            nameHeaders: ["Client", "Project", "Task"],
            rows: analytics.byTask.map { ([$0.client, $0.project, $0.task], $0.seconds) },
            totalSeconds: analytics.totalSeconds
        )
        row += 1

        row = writeCalendar(sheet: sheet, startRow: row, year: year, month: month, analytics: analytics)
        row += 1

        _ = writeDayOfWeek(sheet: sheet, startRow: row, analytics: analytics)
    }

    private static func configureSummaryColumns(sheet: XlsxSheet) {
        // 7 cols used for the calendar (A..G); the breakdown tables fit within
        // the same width by repurposing the same columns.
        sheet.setColumnWidth(col: 1, width: 18)
        sheet.setColumnWidth(col: 2, width: 18)
        sheet.setColumnWidth(col: 3, width: 18)
        sheet.setColumnWidth(col: 4, width: 12)
        sheet.setColumnWidth(col: 5, width: 10)
        sheet.setColumnWidth(col: 6, width: 12)
        sheet.setColumnWidth(col: 7, width: 12)
    }

    // MARK: - Summary blocks

    private static func writeHero(
        sheet: XlsxSheet, startRow: Int, monthLabel: String, analytics: ExportAnalytics
    ) -> Int {
        sheet.setText(row: startRow, col: 1, monthLabel.uppercased(), style: SummaryStyle.heroTitle)

        let totalSeconds = analytics.totalSeconds
        let activeDays = analytics.activeDays
        let avgSeconds = activeDays > 0 ? totalSeconds / activeDays : 0
        let busiest = analytics.busiestDay

        let statsRow = startRow + 2
        writeStat(sheet: sheet, row: statsRow, col: 1,
                  label: "Total",
                  valueDays: secondsAsDays(totalSeconds),
                  isTime: true)
        writeStat(sheet: sheet, row: statsRow, col: 3,
                  label: "Active days",
                  number: Double(activeDays))
        writeStat(sheet: sheet, row: statsRow, col: 5,
                  label: "Avg / day",
                  valueDays: secondsAsDays(avgSeconds),
                  isTime: true)
        if let busiest {
            writeStat(sheet: sheet, row: statsRow, col: 7,
                      label: "Busiest",
                      text: busiestDayLabel(busiest))
        }

        return statsRow
    }

    private static func writeStat(
        sheet: XlsxSheet, row: Int, col: Int,
        label: String,
        valueDays: Double? = nil,
        number: Double? = nil,
        text: String? = nil,
        isTime: Bool = false
    ) {
        sheet.setText(row: row, col: col, label, style: SummaryStyle.statLabel)
        if let valueDays {
            sheet.setNumber(row: row, col: col + 1, valueDays,
                            style: isTime ? SummaryStyle.statValueHours : SummaryStyle.statValueNumber)
        } else if let number {
            sheet.setNumber(row: row, col: col + 1, number, style: SummaryStyle.statValueNumber)
        } else if let text {
            sheet.setText(row: row, col: col + 1, text, style: SummaryStyle.statValueText)
        }
    }

    private static func busiestDayLabel(_ day: ExportAnalytics.DayTotal) -> String {
        let label = DateKey.weekdayLabel(day.date)
        let dayNumber = day.date.split(separator: "-").last ?? ""
        let hms = TimeFormat.hoursMinutes(day.seconds)
        return "\(label) \(dayNumber) · \(hms)"
    }

    private static func writeBreakdown(
        sheet: XlsxSheet, startRow: Int,
        title: String,
        nameHeaders: [String],
        rows: [(names: [String], seconds: Int)],
        totalSeconds: Int
    ) -> Int {
        var row = startRow
        sheet.setText(row: row, col: 1, title, style: SummaryStyle.sectionTitle)
        row += 1

        let nameColCount = nameHeaders.count
        let hoursCol = nameColCount + 1
        let percentCol = nameColCount + 2

        for (i, header) in nameHeaders.enumerated() {
            sheet.setText(row: row, col: i + 1, header, style: SummaryStyle.tableHeader)
        }
        sheet.setText(row: row, col: hoursCol, "Hours", style: SummaryStyle.tableHeaderRight)
        sheet.setText(row: row, col: percentCol, "%", style: SummaryStyle.tableHeaderRight)
        let headerRow = row
        row += 1

        let firstDataRow = row
        guard !rows.isEmpty else { return row }

        for (idx, entry) in rows.enumerated() {
            let banded = (idx % 2 == 1)
            let fill: String? = banded ? ReportPalette.band : nil
            let textStyle = withFill(SummaryStyle.cellText, fill: fill)
            let hoursStyle = withFill(SummaryStyle.cellHours, fill: fill)
            let percentStyle = withFill(SummaryStyle.cellPercent, fill: fill)

            for (i, name) in entry.names.enumerated() {
                sheet.setText(row: row, col: i + 1, name, style: textStyle)
            }
            sheet.setNumber(row: row, col: hoursCol,
                            secondsAsDays(entry.seconds), style: hoursStyle)
            let pct = totalSeconds > 0 ? Double(entry.seconds) / Double(totalSeconds) : 0
            sheet.setNumber(row: row, col: percentCol, pct, style: percentStyle)
            row += 1
        }

        // Data bar on hours column across data rows.
        let hoursColLetter = XlsxRef.columnLetter(hoursCol)
        sheet.conditionalFormats.append(
            .dataBar(range: "\(hoursColLetter)\(firstDataRow):\(hoursColLetter)\(row - 1)",
                     color: ReportPalette.dataBar)
        )

        // Total row.
        for col in 1...percentCol {
            sheet.setText(row: row, col: col, "", style: SummaryStyle.totalFill)
        }
        sheet.setText(row: row, col: nameColCount, "Total", style: SummaryStyle.totalLabel)
        let lastDataRow = row - 1
        sheet.setFormula(row: row, col: hoursCol,
                         "SUM(\(hoursColLetter)\(firstDataRow):\(hoursColLetter)\(lastDataRow))",
                         style: SummaryStyle.totalValueHours)
        row += 1

        _ = headerRow  // intentional: kept for readability above
        return row
    }

    private static func writeCalendar(
        sheet: XlsxSheet, startRow: Int, year: Int, month: Int, analytics: ExportAnalytics
    ) -> Int {
        var row = startRow
        sheet.setText(row: row, col: 1, "Calendar", style: SummaryStyle.sectionTitle)
        row += 1

        let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        for (i, w) in weekdays.enumerated() {
            sheet.setText(row: row, col: i + 1, w, style: SummaryStyle.tableHeaderCenter)
        }
        row += 1

        let grid = analytics.calendarGrid(year: year, month: month)
        let dataStart = row
        for week in grid {
            // Day number row — small grey label.
            for (i, cell) in week.enumerated() {
                if cell.isInMonth, let day = cell.day {
                    sheet.setText(row: row, col: i + 1, String(day), style: SummaryStyle.calendarDayLabel)
                } else {
                    sheet.setText(row: row, col: i + 1, "", style: SummaryStyle.calendarOutOfMonth)
                }
            }
            row += 1

            // Hours row.
            for (i, cell) in week.enumerated() {
                if cell.isInMonth {
                    if cell.seconds > 0 {
                        sheet.setNumber(row: row, col: i + 1,
                                        secondsAsDays(cell.seconds),
                                        style: SummaryStyle.calendarHours)
                    } else {
                        sheet.setText(row: row, col: i + 1, "", style: SummaryStyle.calendarEmpty)
                    }
                } else {
                    sheet.setText(row: row, col: i + 1, "", style: SummaryStyle.calendarOutOfMonth)
                }
            }
            row += 1
        }

        // 3-color scale across every hours row (non-contiguous range built by
        // listing each hours-row's span, separated by spaces in the sqref).
        let hoursRows: [Int] = stride(from: dataStart + 1, to: row, by: 2).map { $0 }
        if !hoursRows.isEmpty {
            let ranges = hoursRows.map { r in
                "\(XlsxRef.columnLetter(1))\(r):\(XlsxRef.columnLetter(7))\(r)"
            }.joined(separator: " ")
            sheet.conditionalFormats.append(.colorScale3(
                range: ranges,
                low: ReportPalette.heatLow,
                mid: ReportPalette.heatMid,
                high: ReportPalette.heatHigh
            ))
        }

        return row
    }

    private static func writeDayOfWeek(
        sheet: XlsxSheet, startRow: Int, analytics: ExportAnalytics
    ) -> Int {
        var row = startRow
        sheet.setText(row: row, col: 1, "Day of week", style: SummaryStyle.sectionTitle)
        row += 1

        sheet.setText(row: row, col: 1, "Weekday", style: SummaryStyle.tableHeader)
        sheet.setText(row: row, col: 2, "Hours", style: SummaryStyle.tableHeaderRight)
        row += 1

        let firstDataRow = row
        for (idx, bucket) in analytics.byWeekday.enumerated() {
            let banded = (idx % 2 == 1)
            let fill: String? = banded ? ReportPalette.band : nil
            sheet.setText(row: row, col: 1, bucket.label,
                          style: withFill(SummaryStyle.cellText, fill: fill))
            sheet.setNumber(row: row, col: 2, secondsAsDays(bucket.seconds),
                            style: withFill(SummaryStyle.cellHours, fill: fill))
            row += 1
        }

        let lastDataRow = row - 1
        if lastDataRow >= firstDataRow {
            sheet.conditionalFormats.append(.dataBar(
                range: "B\(firstDataRow):B\(lastDataRow)",
                color: ReportPalette.dataBar
            ))
        }
        return row
    }

    // MARK: - Helpers

    private static func secondsAsDays(_ seconds: Int) -> Double {
        Double(seconds) / 86_400.0
    }

    private static func withFill(_ base: XlsxStyle, fill: String?) -> XlsxStyle {
        guard let fill else { return base }
        var s = base
        s.fillColor = fill
        return s
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
            // Hours live in column F of each per-month entries sheet (Date | Weekday |
            // Client | Project | Task | Hours | Notes).
            summary.setFormula(row: row, col: 2, "SUM('\(sheetName)'!F:F)", style: .decimal2)
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

    /// Column layout (1-based):
    ///   1 Date · 2 Weekday · 3 Client · 4 Project · 5 Task · 6 Hours · 7 Notes
    private static func addEntriesSheetBody(to sheet: XlsxSheet, entries: [Entry]) {
        sheet.setColumnWidth(col: 1, width: 12)   // Date
        sheet.setColumnWidth(col: 2, width: 8)    // Weekday
        sheet.setColumnWidth(col: 3, width: 22)   // Client
        sheet.setColumnWidth(col: 4, width: 22)   // Project
        sheet.setColumnWidth(col: 5, width: 22)   // Task
        sheet.setColumnWidth(col: 6, width: 10)   // Hours
        sheet.setColumnWidth(col: 7, width: 80)   // Notes

        sheet.frozenRows = 1
        sheet.showGridLines = false

        let headers = ["Date", "Weekday", "Client", "Project", "Task", "Hours", "Notes"]
        for (i, h) in headers.enumerated() {
            sheet.setText(row: 1, col: i + 1, h, style: ReportStyle.header)
        }

        let sorted = entries.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            if lhs.client != rhs.client { return lhs.client < rhs.client }
            if lhs.project != rhs.project { return lhs.project < rhs.project }
            return lhs.task < rhs.task
        }

        var prevDate: String? = nil
        var row = 2
        for entry in sorted {
            // Banded rows: every other data row gets a faint fill. Banding
            // starts on the second data row so the row directly under the
            // header stays clean.
            let banded = ((row - 2) % 2 == 1)
            let bandFill: String? = banded ? ReportPalette.band : nil
            // Day separator: thin top border whenever the date rolls over.
            let needsDayLine = (prevDate != nil && prevDate != entry.date)

            let textStyle = rowStyle(base: ReportStyle.text, fill: bandFill, topBorder: needsDayLine)
            let dateStyle = rowStyle(base: ReportStyle.date, fill: bandFill, topBorder: needsDayLine)
            let weekdayStyle = rowStyle(base: ReportStyle.weekday, fill: bandFill, topBorder: needsDayLine)
            let hoursStyle = rowStyle(base: ReportStyle.hoursMinutes, fill: bandFill, topBorder: needsDayLine)
            let notesStyle = rowStyle(base: ReportStyle.notes, fill: bandFill, topBorder: needsDayLine)

            if let dateValue = DateKey.parse(entry.date) {
                sheet.setDate(row: row, col: 1, dateValue, style: dateStyle)
            } else {
                sheet.setText(row: row, col: 1, entry.date, style: textStyle)
            }
            sheet.setText(row: row, col: 2, DateKey.weekdayLabel(entry.date), style: weekdayStyle)
            sheet.setText(row: row, col: 3, entry.client, style: textStyle)
            sheet.setText(row: row, col: 4, entry.project, style: textStyle)
            sheet.setText(row: row, col: 5, entry.task,    style: textStyle)
            // Hours stored as a fraction of a day so the `[h]:mm` time format
            // renders them correctly; SUM still works because the underlying
            // values are plain numbers.
            sheet.setNumber(row: row, col: 6, Double(entry.seconds) / 86_400.0, style: hoursStyle)
            sheet.setText(row: row, col: 7, entry.notes, style: notesStyle)

            prevDate = entry.date
            row += 1
        }

        if !sorted.isEmpty {
            let lastDataRow = row - 1
            // Paint the whole total row with the same fill so it reads as a
            // contiguous band even where there's no text.
            for col in 1...7 {
                sheet.setText(row: row, col: col, "", style: ReportStyle.totalFill)
            }
            sheet.setText(row: row, col: 5, "Total", style: ReportStyle.totalLabel)
            sheet.setFormula(row: row, col: 6, "SUM(F2:F\(lastDataRow))", style: ReportStyle.totalValue)
            // Filter spans only the data range — leaving the total row out so
            // filtering doesn't hide the bottom total.
            sheet.autoFilterRange = "A1:G\(lastDataRow)"
        } else {
            sheet.autoFilterRange = "A1:G1"
        }
    }

    /// Composes a per-row style on top of a base, layering in the band fill
    /// and (optionally) the day-separator top border.
    private static func rowStyle(base: XlsxStyle, fill: String?, topBorder: Bool) -> XlsxStyle {
        var s = base
        if let fill { s.fillColor = fill }
        if topBorder { s.border.top = .thin }
        return s
    }

    // MARK: - Aggregation helpers

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

}

// MARK: - Report palette & styles

private enum ReportPalette {
    static let headerFill = "FF305496"   // Office-accent dark blue
    static let headerText = "FFFFFFFF"   // White
    static let band       = "FFF7F7F7"   // ~3% gray
    static let totalFill  = "FFE7EEF7"   // Very light blue tint
    static let heroText   = "FF305496"   // Dark accent for the title
    static let dataBar    = "FF638EC6"   // Lighter accent for data bars
    static let heatLow    = "FFFFFFFF"   // White → no activity
    static let heatMid    = "FFB6CDE8"   // Soft blue mid
    static let heatHigh   = "FF305496"   // Saturated accent for heavy days
    static let muted      = "FF8C8C8C"   // Calendar day number, "out of month" tint
    static let outOfMonth = "FFF0F0F0"   // Faint fill for grid cells outside the month
}

private enum ReportStyle {
    static let header = XlsxStyle(
        bold: true,
        fontColor: ReportPalette.headerText,
        fillColor: ReportPalette.headerFill,
        hAlign: .left,
        vAlign: .center
    )

    /// Plain text cell. Used as the base for client/project/task and the
    /// `entry.date` fallback when a date string fails to parse.
    /// All row cells share the same top-vertical alignment so a wrapped note
    /// doesn't shove its neighbors to the bottom of the expanded row.
    static let text = XlsxStyle(vAlign: .top)

    /// Real Excel date cell — `yyyy-mm-dd`, left-aligned to line up with the
    /// other text columns. Date format reads better than the integer serial
    /// when Excel renders it.
    static let date = XlsxStyle(hAlign: .left, vAlign: .top, numberFormat: .date)

    /// Centered three-letter weekday. Easy to scan vertically.
    static let weekday = XlsxStyle(hAlign: .center, vAlign: .top)

    /// Time-of-duration format — numeric value is in days (1.0 = 24h), and
    /// `[h]:mm` displays it as hours and minutes. SUM still totals correctly.
    static let hoursMinutes = XlsxStyle(hAlign: .right, vAlign: .top, numberFormat: .hoursMinutes)

    /// Notes wrap inside the cell so long notes don't blow the column width.
    static let notes = XlsxStyle(vAlign: .top, wrapText: true)

    // Total row — composed in three pieces so we can fill the spacer cells
    // with the same band without bolding empty cells.
    static let totalFill: XlsxStyle = {
        var s = XlsxStyle(fillColor: ReportPalette.totalFill)
        s.border.top = .medium
        return s
    }()

    static let totalLabel: XlsxStyle = {
        var s = XlsxStyle(bold: true, fillColor: ReportPalette.totalFill, hAlign: .right)
        s.border.top = .medium
        return s
    }()

    static let totalValue: XlsxStyle = {
        var s = XlsxStyle(bold: true, fillColor: ReportPalette.totalFill,
                          hAlign: .right, numberFormat: .hoursMinutes)
        s.border.top = .medium
        return s
    }()
}

// MARK: - Date key helpers

private enum DateKey {
    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "EEE"
        return f
    }()

    static func parse(_ key: String) -> Date? { parser.date(from: key) }

    static func weekdayLabel(_ key: String) -> String {
        guard let date = parse(key) else { return "" }
        return weekdayFormatter.string(from: date)
    }
}

// MARK: - Summary styles

private enum SummaryStyle {
    static let heroTitle = XlsxStyle(
        bold: true,
        fontColor: ReportPalette.heroText,
        hAlign: .left, vAlign: .center
    )

    static let sectionTitle = XlsxStyle(bold: true, hAlign: .left)

    static let statLabel = XlsxStyle(
        fontColor: ReportPalette.muted,
        hAlign: .right
    )
    static let statValueHours = XlsxStyle(
        bold: true, hAlign: .left, numberFormat: .hoursMinutes
    )
    static let statValueNumber = XlsxStyle(
        bold: true, hAlign: .left, numberFormat: .integer
    )
    static let statValueText = XlsxStyle(bold: true, hAlign: .left)

    static let tableHeader = XlsxStyle(
        bold: true,
        fontColor: ReportPalette.headerText,
        fillColor: ReportPalette.headerFill,
        hAlign: .left, vAlign: .center
    )
    static let tableHeaderRight: XlsxStyle = {
        var s = tableHeader
        s.hAlign = .right
        return s
    }()
    static let tableHeaderCenter: XlsxStyle = {
        var s = tableHeader
        s.hAlign = .center
        return s
    }()

    static let cellText = XlsxStyle(vAlign: .center)
    static let cellHours = XlsxStyle(hAlign: .right, vAlign: .center, numberFormat: .hoursMinutes)
    static let cellPercent = XlsxStyle(hAlign: .right, vAlign: .center, numberFormat: .percent)

    static let totalFill: XlsxStyle = {
        var s = XlsxStyle(fillColor: ReportPalette.totalFill)
        s.border.top = .medium
        return s
    }()
    static let totalLabel: XlsxStyle = {
        var s = XlsxStyle(bold: true, fillColor: ReportPalette.totalFill, hAlign: .right)
        s.border.top = .medium
        return s
    }()
    static let totalValueHours: XlsxStyle = {
        var s = XlsxStyle(bold: true, fillColor: ReportPalette.totalFill,
                          hAlign: .right, numberFormat: .hoursMinutes)
        s.border.top = .medium
        return s
    }()

    // Calendar cells.
    static let calendarDayLabel = XlsxStyle(
        fontColor: ReportPalette.muted, hAlign: .left, vAlign: .top
    )
    static let calendarHours = XlsxStyle(
        bold: true, hAlign: .right, vAlign: .top, numberFormat: .hoursMinutes
    )
    static let calendarEmpty = XlsxStyle()
    static let calendarOutOfMonth = XlsxStyle(fillColor: ReportPalette.outOfMonth)
}

// MARK: - Analytics

/// Aggregations computed over a slice of entries. Kept as a struct so it's
/// trivially testable in isolation from the workbook writer.
struct ExportAnalytics {
    let entries: [Entry]
    let year: Int
    let month: Int

    var totalSeconds: Int {
        entries.reduce(0) { $0 + $1.seconds }
    }

    var activeDays: Int {
        Set(entries.map(\.date)).count
    }

    struct DayTotal { let date: String; let seconds: Int }

    private var dayTotals: [DayTotal] {
        var bucket: [String: Int] = [:]
        for e in entries { bucket[e.date, default: 0] += e.seconds }
        return bucket.map { DayTotal(date: $0.key, seconds: $0.value) }
    }

    var busiestDay: DayTotal? {
        dayTotals.max { $0.seconds < $1.seconds }
    }

    struct ClientBucket: Equatable { let client: String; let seconds: Int }
    struct ProjectBucket: Equatable { let client: String; let project: String; let seconds: Int }
    struct TaskBucket: Equatable { let client: String; let project: String; let task: String; let seconds: Int }

    var byClient: [ClientBucket] {
        var bucket: [String: Int] = [:]
        for e in entries { bucket[e.client, default: 0] += e.seconds }
        return bucket
            .map { ClientBucket(client: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    var byProject: [ProjectBucket] {
        struct Key: Hashable { let client: String; let project: String }
        var bucket: [Key: Int] = [:]
        for e in entries { bucket[Key(client: e.client, project: e.project), default: 0] += e.seconds }
        return bucket
            .map { ProjectBucket(client: $0.key.client, project: $0.key.project, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    var byTask: [TaskBucket] {
        struct Key: Hashable { let client: String; let project: String; let task: String }
        var bucket: [Key: Int] = [:]
        for e in entries {
            bucket[Key(client: e.client, project: e.project, task: e.task), default: 0] += e.seconds
        }
        return bucket
            .map { TaskBucket(client: $0.key.client, project: $0.key.project, task: $0.key.task, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    struct WeekdayBucket { let label: String; let seconds: Int }

    /// Mon..Sun bucketing — independent of locale weekday-start so the
    /// dashboard always reads in the same order.
    var byWeekday: [WeekdayBucket] {
        var totals = Array(repeating: 0, count: 7)  // 0=Mon..6=Sun
        for entry in entries {
            guard let date = DateKey.parse(entry.date) else { continue }
            let weekday = Calendar.gregorianUTC.component(.weekday, from: date)  // 1=Sun..7=Sat
            let idx = (weekday + 5) % 7  // shift so Mon=0
            totals[idx] += entry.seconds
        }
        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return zip(labels, totals).map { WeekdayBucket(label: $0, seconds: $1) }
    }

    struct CalendarCell { let day: Int?; let seconds: Int; let isInMonth: Bool }

    /// 6-row × 7-col grid of the month for the heatmap. Each row starts on a
    /// Monday and contains both leading/trailing out-of-month cells where
    /// applicable.
    func calendarGrid(year: Int, month: Int) -> [[CalendarCell]] {
        let cal = Calendar.gregorianUTC
        guard let firstOfMonth = cal.date(from: DateComponents(year: year, month: month, day: 1)),
              let monthRange = cal.range(of: .day, in: .month, for: firstOfMonth)
        else { return [] }

        let dayCount = monthRange.count
        // Excel-style ISO week: how many days *before* the 1st belong to that week (0 if 1st is Mon).
        let firstWeekday = cal.component(.weekday, from: firstOfMonth)  // 1=Sun..7=Sat
        let leadingBlanks = (firstWeekday + 5) % 7

        var byDay = Array(repeating: 0, count: dayCount + 1)  // 1-indexed
        for entry in entries {
            guard entry.date.hasPrefix(String(format: "%04d-%02d", year, month)),
                  let date = DateKey.parse(entry.date)
            else { continue }
            let d = cal.component(.day, from: date)
            if d >= 1 && d <= dayCount { byDay[d] += entry.seconds }
        }

        var grid: [[CalendarCell]] = []
        var cursor = 1 - leadingBlanks
        while cursor <= dayCount {
            var week: [CalendarCell] = []
            for _ in 0..<7 {
                if cursor < 1 || cursor > dayCount {
                    week.append(CalendarCell(day: nil, seconds: 0, isInMonth: false))
                } else {
                    week.append(CalendarCell(day: cursor, seconds: byDay[cursor], isInMonth: true))
                }
                cursor += 1
            }
            grid.append(week)
        }
        return grid
    }
}

private extension Calendar {
    static let gregorianUTC: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
}
