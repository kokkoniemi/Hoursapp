import Testing
import Foundation
import ZIPFoundation
@testable import Hoursapp

@Suite("ExportPeriod")
struct ExportPeriodTests {
    private static func entry(date: String, seconds: Int = 60, running: Bool = false) -> Hoursapp.Entry {
        Hoursapp.Entry(
            id: UUID().uuidString,
            date: date,
            client: "Acme", project: "Site", task: "Design",
            seconds: seconds, notes: "",
            startedAt: nil,
            stoppedAt: running ? nil : "2026-05-06T10:00:00Z"
        )
    }

    @Test("availableOptions includes the current month even with no entries")
    func emptyEntriesIncludesCurrent() {
        let today = ISO8601DateFormatter().date(from: "2026-05-06T10:00:00Z")!
        let options = ExportPeriod.availableOptions(for: [], today: today)
        #expect(options.first == .month(year: 2026, month: 5))
        #expect(options.last == .allMonths)
    }

    @Test("availableOptions lists each month with stopped entries, most recent first")
    func sortsMonthsDescending() {
        let today = ISO8601DateFormatter().date(from: "2026-05-06T10:00:00Z")!
        let entries = [
            Self.entry(date: "2026-03-15"),
            Self.entry(date: "2026-04-02"),
            Self.entry(date: "2026-04-20"),
            Self.entry(date: "2026-01-10"),
        ]
        let options = ExportPeriod.availableOptions(for: entries, today: today)
        // Current month (May 2026) is prepended; months are descending; All last.
        #expect(options == [
            .month(year: 2026, month: 5),
            .month(year: 2026, month: 4),
            .month(year: 2026, month: 3),
            .month(year: 2026, month: 1),
            .allMonths,
        ])
    }

    @Test("running entries are excluded from period suggestions")
    func runningEntriesExcluded() {
        let today = ISO8601DateFormatter().date(from: "2026-05-06T10:00:00Z")!
        let entries = [
            Self.entry(date: "2025-12-01", running: true),  // running, ignored
        ]
        let options = ExportPeriod.availableOptions(for: entries, today: today)
        #expect(options == [.month(year: 2026, month: 5), .allMonths])
    }

    @Test("filter excludes other months and running entries")
    func filterByMonth() {
        let entries = [
            Self.entry(date: "2026-04-30"),   // April
            Self.entry(date: "2026-05-01"),   // May
            Self.entry(date: "2026-05-31"),   // May
            Self.entry(date: "2026-06-01"),   // June
            Self.entry(date: "2026-05-10", running: true),  // running, excluded
        ]
        let filtered = ExportPeriod.filter(entries: entries, by: .month(year: 2026, month: 5))
        #expect(filtered.count == 2)
        #expect(filtered.allSatisfy { $0.date.hasPrefix("2026-05") })
    }

    @Test("filter all-months keeps every stopped entry")
    func filterAll() {
        let entries = [
            Self.entry(date: "2026-04-30"),
            Self.entry(date: "2026-05-01"),
            Self.entry(date: "2026-05-10", running: true),
        ]
        let filtered = ExportPeriod.filter(entries: entries, by: .allMonths)
        #expect(filtered.count == 2)
    }
}

@Suite("ExcelExporter")
struct ExcelExporterTests {
    private static func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "hoursapp-export-\(UUID().uuidString).xlsx")
    }

    private static func makeEntries() -> [Hoursapp.Entry] {
        [
            entry(id: "a", date: "2026-05-01", client: "Acme", project: "Site", task: "Design", seconds: 3600),
            entry(id: "b", date: "2026-05-01", client: "Acme", project: "Site", task: "QA", seconds: 1800),
            entry(id: "c", date: "2026-05-02", client: "Acme", project: "Site", task: "Design", seconds: 5400),
            entry(id: "d", date: "2026-04-15", client: "Beta", project: "App", task: "Meetings", seconds: 1800),
        ]
    }

    private static func entry(
        id: String, date: String, client: String, project: String, task: String, seconds: Int
    ) -> Hoursapp.Entry {
        Hoursapp.Entry(
            id: id, date: date,
            client: client, project: project, task: task,
            seconds: seconds, notes: "",
            startedAt: nil, stoppedAt: "2026-05-06T10:00:00Z"
        )
    }

    @Test("monthly export has Summary + Entries sheets and a SUM total")
    func monthlyExport() throws {
        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try ExcelExporter.export(
            entries: Self.makeEntries(),
            period: .month(year: 2026, month: 5),
            to: url
        )

        let archive = try #require(Archive(url: url, accessMode: .read))
        let workbookXML = try Self.read(archive, "xl/workbook.xml")
        #expect(workbookXML.contains("name=\"Summary\""))
        #expect(workbookXML.contains("name=\"Entries\""))

        let summaryXML = try Self.read(archive, "xl/worksheets/sheet1.xml")
        // Hero title uppercases the month label for visual weight.
        #expect(summaryXML.contains("MAY 2026"))
        // The rebuilt summary includes the three breakdown sections and the
        // calendar heatmap. We assert their section titles rather than fragile
        // cell positions, which keeps the test stable as the layout evolves.
        #expect(summaryXML.contains("By client"))
        #expect(summaryXML.contains("By project"))
        #expect(summaryXML.contains("By task"))
        #expect(summaryXML.contains("Calendar"))
        #expect(summaryXML.contains("Day of week"))
        // Conditional formatting is emitted for the breakdown data bars.
        #expect(summaryXML.contains("type=\"dataBar\""))
        // And a 3-color scale on the calendar heatmap.
        #expect(summaryXML.contains("type=\"colorScale\""))

        let entriesXML = try Self.read(archive, "xl/worksheets/sheet2.xml")
        #expect(entriesXML.contains("Acme"))
        #expect(!entriesXML.contains("Beta"))    // Beta is in April, excluded
        // Hours column moved to F after the Weekday column was inserted.
        #expect(entriesXML.contains("<f>SUM(F2:F4)</f>"))
    }

    @Test("monthly export with no entries only writes the title and a placeholder")
    func emptyMonth() throws {
        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try ExcelExporter.export(
            entries: [],
            period: .month(year: 2026, month: 5),
            to: url
        )

        let archive = try #require(Archive(url: url, accessMode: .read))
        let summaryXML = try Self.read(archive, "xl/worksheets/sheet1.xml")
        #expect(summaryXML.contains("MAY 2026"))
        #expect(summaryXML.contains("(no stopped entries in this month)"))
    }

    @Test("all-months export adds one sheet per month plus Summary")
    func allMonthsExport() throws {
        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try ExcelExporter.export(
            entries: Self.makeEntries(),
            period: .allMonths,
            to: url
        )

        let archive = try #require(Archive(url: url, accessMode: .read))
        let names = Set(archive.map(\.path))
        // 1 summary + 2 month sheets = 3 sheet xml files
        #expect(names.contains("xl/worksheets/sheet1.xml"))
        #expect(names.contains("xl/worksheets/sheet2.xml"))
        #expect(names.contains("xl/worksheets/sheet3.xml"))

        let workbookXML = try Self.read(archive, "xl/workbook.xml")
        #expect(workbookXML.contains("name=\"Summary\""))
        #expect(workbookXML.contains("name=\"2026-04\""))
        #expect(workbookXML.contains("name=\"2026-05\""))

        let summaryXML = try Self.read(archive, "xl/worksheets/sheet1.xml")
        // Per-month entries sheets now have hours in column F (Date | Weekday |
        // Client | Project | Task | Hours | Notes).
        #expect(summaryXML.contains("<f>SUM('2026-04'!F:F)</f>"))
        #expect(summaryXML.contains("<f>SUM('2026-05'!F:F)</f>"))
        #expect(summaryXML.contains("<f>SUM(B2:B3)</f>"))
    }

    @Test("notes with quotes/commas/newlines round-trip safely")
    func tricksyNotes() throws {
        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let weird = Hoursapp.Entry(
            id: "x", date: "2026-05-15",
            client: "Acme", project: "Site", task: "Design",
            seconds: 60,
            notes: "she said \"hi\", & <html>\nnew line",
            startedAt: nil, stoppedAt: "2026-05-15T10:00:00Z"
        )
        try ExcelExporter.export(entries: [weird], period: .month(year: 2026, month: 5), to: url)

        let archive = try #require(Archive(url: url, accessMode: .read))
        let entriesXML = try Self.read(archive, "xl/worksheets/sheet2.xml")
        // Element-character escaping: & < > are escaped; quotes/apostrophes are not.
        #expect(entriesXML.contains("\"hi\""))
        #expect(entriesXML.contains("&amp;"))
        #expect(entriesXML.contains("&lt;html&gt;"))
        // The literal newline survives inside the XML — preserved by xml:space="preserve".
        #expect(entriesXML.contains("\nnew line"))
    }

    private static func read(_ archive: Archive, _ name: String) throws -> String {
        guard let entry = archive[name] else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing \(name)"])
        }
        var data = Data()
        _ = try archive.extract(entry) { chunk in data.append(chunk) }
        return String(decoding: data, as: UTF8.self)
    }
}
