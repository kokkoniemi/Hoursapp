import Foundation

enum ExcelExporter {
    /// One narrow column on the left and one short row on top of every sheet.
    /// Column width unit ≈ characters; 1.43 lands at ~10 px in Calibri 11.
    /// Row height unit is points; 7.5 pt ≈ 10 px at 96 DPI.
    private static let paddingRows: Int = 1
    private static let paddingCols: Int = 1
    private static let paddingRowHeight: Double = 7.5
    private static let paddingColumnWidth: Double = 1.43

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

    /// Inserts a narrow padding column on the left and a short padding row on
    /// top. All call sites keep using logical (1-based) coordinates — the
    /// sheet shifts everything at serialize time.
    private static func applyPadding(_ sheet: XlsxSheet) {
        sheet.topPadding = paddingRows
        sheet.leftPadding = paddingCols
        sheet.paddingRowHeight = paddingRowHeight
        sheet.paddingColumnWidth = paddingColumnWidth
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
        applyPadding(sheet)
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

    /// Borders for one calendar cell. Each day is two stacked cells (date
    /// row + hours row); within a day we leave no border so the pair reads as
    /// one unit, while vertical lines separate days-of-week and bottom lines
    /// separate weeks. The top border on the first week and the right border
    /// on Sundays close the outer frame.
    private static func calendarBorders(weekIdx: Int, dayIdx: Int, isHoursRow: Bool) -> XlsxBorder {
        var b = XlsxBorder()
        b.left = .thin
        if dayIdx == 6 { b.right = .thin }
        if !isHoursRow && weekIdx == 0 { b.top = .thin }
        if isHoursRow { b.bottom = .thin }
        return b
    }

    private static func applyBorders(_ base: XlsxStyle, _ border: XlsxBorder) -> XlsxStyle {
        var s = base
        s.border = border
        return s
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
        // Bake the heatmap colors per-day rather than relying on a
        // <conditionalFormatting> color-scale. CF only paints the cell whose
        // value it scales, so a single rule can't paint both the day-number
        // row and the hours row in matching tones. Computing the gradient
        // ourselves lets every cell of a given day share one fill.
        let maxSeconds = grid.flatMap { $0 }.map(\.seconds).max() ?? 0

        for (weekIdx, week) in grid.enumerated() {
            // Day-number row.
            for (dayIdx, cell) in week.enumerated() {
                let topBorder = calendarBorders(weekIdx: weekIdx, dayIdx: dayIdx, isHoursRow: false)
                let style = calendarDayStyle(
                    cell: cell, maxSeconds: maxSeconds, border: topBorder, isHoursRow: false
                )
                if cell.isInMonth, let day = cell.day {
                    sheet.setNumber(row: row, col: dayIdx + 1, Double(day), style: style)
                } else {
                    sheet.setText(row: row, col: dayIdx + 1, "", style: style)
                }
            }
            row += 1

            // Hours row — shares the fill computed for its day so the two
            // cells read as one painted block.
            for (dayIdx, cell) in week.enumerated() {
                let bottomBorder = calendarBorders(weekIdx: weekIdx, dayIdx: dayIdx, isHoursRow: true)
                let style = calendarDayStyle(
                    cell: cell, maxSeconds: maxSeconds, border: bottomBorder, isHoursRow: true
                )
                if cell.isInMonth, cell.seconds > 0 {
                    sheet.setNumber(row: row, col: dayIdx + 1,
                                    secondsAsDays(cell.seconds), style: style)
                } else {
                    sheet.setText(row: row, col: dayIdx + 1, "", style: style)
                }
            }
            row += 1
        }

        return row
    }

    /// Computes the visual style for a single calendar cell, baking in the
    /// gradient fill and a text color that flips to white once the cell
    /// background is dark enough for black text to fail WCAG contrast.
    private static func calendarDayStyle(
        cell: ExportAnalytics.CalendarCell,
        maxSeconds: Int,
        border: XlsxBorder,
        isHoursRow: Bool
    ) -> XlsxStyle {
        // Out-of-month: faint gray block, never painted by the heatmap.
        guard cell.isInMonth else {
            var s = isHoursRow
                ? XlsxStyle(fillColor: ReportPalette.outOfMonth)
                : XlsxStyle(fillColor: ReportPalette.outOfMonth, numberFormat: .integer)
            s.border = border
            return s
        }

        // In-month but zero activity: no fill, normal text colors.
        guard cell.seconds > 0, maxSeconds > 0 else {
            var s = isHoursRow
                ? XlsxStyle()
                : XlsxStyle(fontColor: ReportPalette.muted, hAlign: .left,
                            vAlign: .top, numberFormat: .integer)
            if isHoursRow {
                s = XlsxStyle()  // truly empty
            }
            s.border = border
            return s
        }

        let t = Double(cell.seconds) / Double(maxSeconds)
        let fill = Color.gradient(t: t,
                                  low: ReportPalette.heatLow,
                                  mid: ReportPalette.heatMid,
                                  high: ReportPalette.heatHigh)
        let textWhite = Color.luminance(fill) < 0.18
        let lightTextColor = "FFFFFFFF"
        let dayLabelColor = textWhite ? lightTextColor : ReportPalette.muted
        let hoursColor    = textWhite ? lightTextColor : "FF000000"

        var s: XlsxStyle
        if isHoursRow {
            s = XlsxStyle(
                bold: true,
                fontColor: hoursColor,
                fillColor: fill,
                hAlign: .right,
                vAlign: .top,
                numberFormat: .hoursMinutes
            )
        } else {
            s = XlsxStyle(
                fontColor: dayLabelColor,
                fillColor: fill,
                hAlign: .left,
                vAlign: .top,
                numberFormat: .integer
            )
        }
        s.border = border
        return s
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

    /// ARGB color math for the calendar heatmap. Kept private to the exporter
    /// because the colors here are display values baked into specific cells —
    /// not a general-purpose color type.
    enum Color {
        /// Three-stop gradient: `t` 0 → low, 0.5 → mid, 1 → high.
        static func gradient(t: Double, low: String, mid: String, high: String) -> String {
            let clamped = min(1, max(0, t))
            if clamped < 0.5 {
                return interpolate(from: low, to: mid, t: clamped * 2)
            } else {
                return interpolate(from: mid, to: high, t: (clamped - 0.5) * 2)
            }
        }

        /// Linear interpolation in sRGB space. Good enough for a heatmap where
        /// we just need a perceptually monotonic ramp.
        static func interpolate(from: String, to: String, t: Double) -> String {
            let (rA, gA, bA) = rgb(from)
            let (rB, gB, bB) = rgb(to)
            let r = Int((Double(rA) + (Double(rB) - Double(rA)) * t).rounded())
            let g = Int((Double(gA) + (Double(gB) - Double(gA)) * t).rounded())
            let b = Int((Double(bA) + (Double(bB) - Double(bA)) * t).rounded())
            return String(format: "FF%02X%02X%02X", r, g, b)
        }

        /// WCAG relative luminance, returned in [0, 1]. Below ~0.18 dark text
        /// fails AA against the color; we flip to white at that threshold.
        static func luminance(_ argb: String) -> Double {
            let (r, g, b) = rgb(argb)
            func channel(_ v: Int) -> Double {
                let c = Double(v) / 255.0
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
        }

        private static func rgb(_ argb: String) -> (Int, Int, Int) {
            // Accept "FFRRGGBB" or "RRGGBB"; ignore the alpha channel.
            let hex = argb.count == 8 ? String(argb.dropFirst(2)) : argb
            guard hex.count == 6 else { return (0, 0, 0) }
            let chars = Array(hex)
            let r = Int(String(chars[0..<2]), radix: 16) ?? 0
            let g = Int(String(chars[2..<4]), radix: 16) ?? 0
            let b = Int(String(chars[4..<6]), radix: 16) ?? 0
            return (r, g, b)
        }
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
        applyPadding(summary)
        summary.showGridLines = false

        let analytics = AllTimeAnalytics(entries: entries)
        let months = analytics.months

        configureAllMonthsColumns(sheet: summary, monthCount: months.count)

        var row = 1
        row = writeAllTimeHero(sheet: summary, startRow: row, analytics: analytics)
        row += 1

        guard !entries.isEmpty else {
            summary.setText(row: row, col: 1, "(no stopped entries)", style: .default)
            return
        }

        row = writeMonthlyTrend(sheet: summary, startRow: row, analytics: analytics)
        row += 1
        _ = writeClientMonthHeatmap(sheet: summary, startRow: row, analytics: analytics)

        // Per-month entries sheets get the polished body so the rest of the
        // workbook is consistent with the single-month export.
        for monthKey in months {
            let monthSheet = workbook.addSheet(name: monthKey)
            applyPadding(monthSheet)
            let monthEntries = entries.filter { $0.date.hasPrefix(monthKey) }
            addEntriesSheetBody(to: monthSheet, entries: monthEntries)
        }
    }

    private static func configureAllMonthsColumns(sheet: XlsxSheet, monthCount: Int) {
        // Client column wider, month columns compact so a long history still
        // fits horizontally with the sparkline at the end.
        sheet.setColumnWidth(col: 1, width: 22)
        let monthColWidth: Double = 9
        for i in 0..<monthCount {
            sheet.setColumnWidth(col: 2 + i, width: monthColWidth)
        }
        sheet.setColumnWidth(col: 2 + monthCount, width: 11)   // Total
        sheet.setColumnWidth(col: 3 + monthCount, width: 18)   // Trend sparkline
    }

    private static func writeAllTimeHero(
        sheet: XlsxSheet, startRow: Int, analytics: AllTimeAnalytics
    ) -> Int {
        sheet.setText(row: startRow, col: 1, "ALL-TIME SUMMARY", style: SummaryStyle.heroTitle)

        let statsRow = startRow + 2
        writeStat(sheet: sheet, row: statsRow, col: 1,
                  label: "Total",
                  valueDays: secondsAsDays(analytics.totalSeconds),
                  isTime: true)
        writeStat(sheet: sheet, row: statsRow, col: 3,
                  label: "Span",
                  text: analytics.spanLabel ?? "—")
        writeStat(sheet: sheet, row: statsRow, col: 5,
                  label: "Clients · Projects",
                  text: "\(analytics.distinctClients) · \(analytics.distinctProjects)")
        if let busiest = analytics.busiestMonth {
            let label = "\(monthLabelShort(busiest.month)) · \(TimeFormat.hoursMinutes(busiest.seconds))"
            writeStat(sheet: sheet, row: statsRow, col: 7, label: "Busiest month", text: label)
        }

        let secondRow = statsRow + 1
        writeStat(sheet: sheet, row: secondRow, col: 1,
                  label: "Longest streak",
                  number: Double(analytics.longestStreak))
        writeStat(sheet: sheet, row: secondRow, col: 3,
                  label: "Active days",
                  number: Double(analytics.activeDays))
        writeStat(sheet: sheet, row: secondRow, col: 5,
                  label: "Tasks",
                  number: Double(analytics.distinctTasks))

        return secondRow
    }

    private static func writeMonthlyTrend(
        sheet: XlsxSheet, startRow: Int, analytics: AllTimeAnalytics
    ) -> Int {
        var row = startRow
        sheet.setText(row: row, col: 1, "Monthly trend", style: SummaryStyle.sectionTitle)
        row += 1

        sheet.setText(row: row, col: 1, "Month", style: SummaryStyle.tableHeader)
        sheet.setText(row: row, col: 2, "Hours", style: SummaryStyle.tableHeaderRight)
        sheet.setText(row: row, col: 3, "Active days", style: SummaryStyle.tableHeaderRight)
        sheet.setText(row: row, col: 4, "Avg / day", style: SummaryStyle.tableHeaderRight)
        row += 1

        let firstDataRow = row
        for (idx, month) in analytics.byMonth.enumerated() {
            let banded = (idx % 2 == 1)
            let fill: String? = banded ? ReportPalette.band : nil
            sheet.setText(row: row, col: 1, month.month,
                          style: withFill(SummaryStyle.cellText, fill: fill))
            // Live cross-sheet sum so editing an entry on a month sheet
            // reflows the trend table automatically.
            sheet.setFormula(row: row, col: 2,
                             "SUM('\(month.month)'!F:F)",
                             style: withFill(SummaryStyle.cellHours, fill: fill))
            sheet.setNumber(row: row, col: 3, Double(month.activeDays),
                            style: withFill(SummaryStyle.cellNumber, fill: fill))
            let avgDays = month.activeDays > 0
                ? Double(month.seconds) / Double(month.activeDays) / 86_400.0
                : 0
            sheet.setNumber(row: row, col: 4, avgDays,
                            style: withFill(SummaryStyle.cellHours, fill: fill))
            row += 1
        }

        let lastDataRow = row - 1

        // Data bar on the Hours column so the trend reads at a glance.
        if lastDataRow >= firstDataRow {
            sheet.conditionalFormats.append(.dataBar(
                range: "B\(firstDataRow):B\(lastDataRow)",
                color: ReportPalette.dataBar
            ))
        }

        // Total row.
        for col in 1...4 {
            sheet.setText(row: row, col: col, "", style: SummaryStyle.totalFill)
        }
        sheet.setText(row: row, col: 1, "Total", style: SummaryStyle.totalLabel)
        sheet.setFormula(row: row, col: 2,
                         "SUM(B\(firstDataRow):B\(lastDataRow))",
                         style: SummaryStyle.totalValueHours)
        row += 1

        return row
    }

    private static func writeClientMonthHeatmap(
        sheet: XlsxSheet, startRow: Int, analytics: AllTimeAnalytics
    ) -> Int {
        var row = startRow
        sheet.setText(row: row, col: 1, "By client across time", style: SummaryStyle.sectionTitle)
        row += 1

        let months = analytics.months
        let totalCol = months.count + 2
        let trendCol = months.count + 3

        sheet.setText(row: row, col: 1, "Client", style: SummaryStyle.tableHeader)
        for (i, monthKey) in months.enumerated() {
            sheet.setText(row: row, col: 2 + i,
                          monthLabelCompact(monthKey),
                          style: SummaryStyle.tableHeaderCenter)
        }
        sheet.setText(row: row, col: totalCol, "Total", style: SummaryStyle.tableHeaderRight)
        sheet.setText(row: row, col: trendCol, "Trend", style: SummaryStyle.tableHeaderCenter)
        row += 1

        let matrix = analytics.clientMonthMatrix(months: months)
        let firstDataRow = row

        for (idx, entry) in matrix.enumerated() {
            let banded = (idx % 2 == 1)
            let fill: String? = banded ? ReportPalette.band : nil
            sheet.setText(row: row, col: 1, entry.client,
                          style: withFill(SummaryStyle.cellText, fill: fill))
            for (i, seconds) in entry.perMonth.enumerated() {
                if seconds > 0 {
                    sheet.setNumber(row: row, col: 2 + i,
                                    secondsAsDays(seconds),
                                    style: withFill(SummaryStyle.cellHours, fill: fill))
                } else {
                    // Empty cell still gets the fill so banding remains contiguous.
                    sheet.setText(row: row, col: 2 + i, "",
                                  style: withFill(XlsxStyle(), fill: fill))
                }
            }
            let totalSeconds = entry.perMonth.reduce(0, +)
            sheet.setNumber(row: row, col: totalCol, secondsAsDays(totalSeconds),
                            style: withFill(SummaryStyle.cellHours, fill: fill))
            sheet.setText(row: row, col: trendCol, Sparkline.render(entry.perMonth),
                          style: withFill(SummaryStyle.sparkline, fill: fill))
            row += 1
        }

        let lastDataRow = row - 1
        if lastDataRow >= firstDataRow, !months.isEmpty {
            // 3-color scale across the per-month matrix only — Total and Trend
            // columns stay neutral so the colors read as month-to-month variance,
            // not absolute size.
            let firstMonthCol = XlsxRef.columnLetter(2)
            let lastMonthCol = XlsxRef.columnLetter(1 + months.count)
            sheet.conditionalFormats.append(.colorScale3(
                range: "\(firstMonthCol)\(firstDataRow):\(lastMonthCol)\(lastDataRow)",
                low: ReportPalette.heatLow,
                mid: ReportPalette.heatMid,
                high: ReportPalette.heatHigh
            ))
        }

        return row
    }

    private static func monthLabelCompact(_ key: String) -> String {
        // "yyyy-MM" → "MMM yy" e.g. "2026-05" → "May 26".
        let parts = key.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              (1...12).contains(month) else { return key }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(months[month - 1]) \(String(format: "%02d", year % 100))"
    }

    private static func monthLabelShort(_ key: String) -> String {
        // "yyyy-MM" → "MMM yyyy" e.g. "May 2026". Used in the hero stats.
        let parts = key.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              (1...12).contains(month) else { return key }
        return ExportPeriod.monthLabel(year: year, month: month)
    }

    // MARK: - Per-entry sheets

    private static func addEntriesSheet(to workbook: XlsxWorkbook, name: String, entries: [Entry]) {
        let sheet = workbook.addSheet(name: name)
        applyPadding(sheet)
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

}

// MARK: - Report palette & styles

private enum ReportPalette {
    static let headerFill = "FF305496"   // Office-accent dark blue
    static let headerText = "FFFFFFFF"   // White
    static let band       = "FFF7F7F7"   // ~3% gray
    static let totalFill  = "FFE7EEF7"   // Very light blue tint
    static let heroText   = "FF305496"   // Dark accent for the title
    static let dataBar    = "FF638EC6"   // Lighter accent for data bars
    // Heatmap stops — text color is chosen per cell based on luminance, so
    // the saturated brand accent can be used at the high end without losing
    // contrast (we flip to white text on the dark cells).
    static let heatLow    = "FFFFFFFF"   // White → no activity
    static let heatMid    = "FFA8C5E8"   // Soft blue mid
    static let heatHigh   = "FF305496"   // Brand accent — used with white text
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
    static let cellNumber = XlsxStyle(hAlign: .right, vAlign: .center, numberFormat: .integer)

    /// Unicode block-character sparkline cell — centered, slightly muted, so
    /// the strip reads as a sketch rather than competing with the numeric
    /// columns next to it.
    static let sparkline = XlsxStyle(
        fontColor: ReportPalette.heatHigh,
        hAlign: .center,
        vAlign: .center
    )

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
    /// Day-of-month label. Stored as an integer with format `0` so Excel
    /// doesn't tag the cell with a "number stored as text" warning triangle.
    static let calendarDayLabel = XlsxStyle(
        fontColor: ReportPalette.muted, hAlign: .left, vAlign: .top,
        numberFormat: .integer
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

// MARK: - All-time analytics

/// Aggregations spanning every month in the dataset. Used by the All-months
/// summary; kept separate from `ExportAnalytics` because that one is
/// month-scoped.
struct AllTimeAnalytics {
    let entries: [Entry]

    var totalSeconds: Int { entries.reduce(0) { $0 + $1.seconds } }
    var activeDays: Int { Set(entries.map(\.date)).count }

    /// Every yyyy-MM key with at least one stopped entry, ascending.
    var months: [String] {
        var set = Set<String>()
        for e in entries where e.date.count >= 7 {
            set.insert(String(e.date.prefix(7)))
        }
        return set.sorted()
    }

    var distinctClients: Int { Set(entries.map(\.client)).count }
    var distinctProjects: Int {
        Set(entries.map { "\($0.client)\u{0}\($0.project)" }).count
    }
    var distinctTasks: Int {
        Set(entries.map { "\($0.client)\u{0}\($0.project)\u{0}\($0.task)" }).count
    }

    /// Longest run of consecutive calendar days with at least one entry.
    var longestStreak: Int {
        let dates = Set(entries.map(\.date)).sorted()
        guard !dates.isEmpty else { return 0 }
        let cal = Calendar.gregorianUTC
        var best = 1
        var current = 1
        for i in 1..<dates.count {
            guard let prev = DateKey.parse(dates[i - 1]),
                  let cur  = DateKey.parse(dates[i]) else { continue }
            let diff = cal.dateComponents([.day], from: prev, to: cur).day ?? 0
            if diff == 1 {
                current += 1
                best = max(best, current)
            } else {
                current = 1
            }
        }
        return best
    }

    var spanLabel: String? {
        let dates = entries.map(\.date)
        guard let first = dates.min(), let last = dates.max() else { return nil }
        if first == last { return first }
        return "\(first) → \(last)"
    }

    struct MonthSummary { let month: String; let seconds: Int; let activeDays: Int }

    var byMonth: [MonthSummary] {
        struct Acc { var seconds = 0; var days: Set<String> = [] }
        var bucket: [String: Acc] = [:]
        for e in entries where e.date.count >= 7 {
            let key = String(e.date.prefix(7))
            bucket[key, default: Acc()].seconds += e.seconds
            bucket[key, default: Acc()].days.insert(e.date)
        }
        return bucket
            .map { MonthSummary(month: $0.key, seconds: $0.value.seconds, activeDays: $0.value.days.count) }
            .sorted { $0.month < $1.month }
    }

    var busiestMonth: MonthSummary? {
        byMonth.max { $0.seconds < $1.seconds }
    }

    /// Per-client hours by month. The `perMonth` array is aligned to the
    /// passed-in `months` list so the heatmap row layout is predictable.
    /// Sorted by total descending so the heaviest clients sit at the top.
    func clientMonthMatrix(months: [String]) -> [(client: String, perMonth: [Int])] {
        var bucket: [String: [String: Int]] = [:]
        for e in entries where e.date.count >= 7 {
            let monthKey = String(e.date.prefix(7))
            bucket[e.client, default: [:]][monthKey, default: 0] += e.seconds
        }
        return bucket
            .map { client, perMonth -> (client: String, perMonth: [Int]) in
                let values = months.map { perMonth[$0] ?? 0 }
                return (client: client, perMonth: values)
            }
            .sorted { $0.perMonth.reduce(0, +) > $1.perMonth.reduce(0, +) }
    }
}

// MARK: - Sparkline

/// Renders a sequence of numeric values as a Unicode block-character strip.
/// Cheap, font-agnostic, and works in every spreadsheet reader — chosen in
/// preference to OOXML's native sparkline extension (which is well-supported
/// in Excel but inconsistent in Numbers and LibreOffice).
enum Sparkline {
    private static let blocks = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

    static func render(_ values: [Int]) -> String {
        guard let maxValue = values.max(), maxValue > 0 else {
            // No activity at all — emit a row of spaces so column width stays
            // predictable but the cell reads as visually empty.
            return String(repeating: " ", count: values.count)
        }
        return values.map { value -> String in
            guard value > 0 else { return " " }
            // Floor rather than round so the smallest non-zero value maps to
            // the shortest block (▁) and only the absolute max maps to █.
            let scaled = Double(value) / Double(maxValue) * Double(blocks.count - 1)
            let idx = min(blocks.count - 1, max(0, Int(scaled)))
            return blocks[idx]
        }.joined()
    }
}
