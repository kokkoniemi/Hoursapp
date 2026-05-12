import Testing
import Foundation
import ZIPFoundation
@testable import Hoursapp

@Suite("Xlsx column letters & cell references")
struct XlsxRefTests {
    @Test("column letters")
    func columnLetters() {
        #expect(XlsxRef.columnLetter(1) == "A")
        #expect(XlsxRef.columnLetter(26) == "Z")
        #expect(XlsxRef.columnLetter(27) == "AA")
        #expect(XlsxRef.columnLetter(52) == "AZ")
        #expect(XlsxRef.columnLetter(53) == "BA")
        #expect(XlsxRef.columnLetter(702) == "ZZ")
        #expect(XlsxRef.columnLetter(703) == "AAA")
    }

    @Test("cell refs")
    func cellRefs() {
        #expect(XlsxRef.cellRef(row: 1, col: 1) == "A1")
        #expect(XlsxRef.cellRef(row: 99, col: 5) == "E99")
    }
}

@Suite("Xlsx number formatting")
struct XlsxNumberTests {
    @Test("integers render without decimals")
    func integers() {
        #expect(XlsxNumber.format(0) == "0")
        #expect(XlsxNumber.format(42) == "42")
        #expect(XlsxNumber.format(-3) == "-3")
    }

    @Test("decimals strip trailing zeros")
    func decimals() {
        #expect(XlsxNumber.format(1.5) == "1.5")
        #expect(XlsxNumber.format(1.25) == "1.25")
        #expect(XlsxNumber.format(0.1) == "0.1")
    }
}

@Suite("XML escaping")
struct XMLEscapeTests {
    @Test("element-text escape preserves quotes and apostrophes")
    func textEscape() {
        #expect(XML.escapeText("a & b") == "a &amp; b")
        #expect(XML.escapeText("<x>") == "&lt;x&gt;")
        #expect(XML.escapeText("he said \"hi\"") == "he said \"hi\"")
        #expect(XML.escapeText("it's") == "it's")
    }

    @Test("attribute escape covers double quotes")
    func attributeEscape() {
        #expect(XML.escapeAttribute("a & b") == "a &amp; b")
        #expect(XML.escapeAttribute("name=\"x\"") == "name=&quot;x&quot;")
        // Apostrophes are safe inside double-quoted attributes; they pass through.
        #expect(XML.escapeAttribute("it's") == "it's")
    }
}

@Suite("XlsxWorkbook end-to-end")
struct XlsxWorkbookTests {
    private static func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "hoursapp-xlsx-\(UUID().uuidString).xlsx")
    }

    @Test("a written workbook is a valid .xlsx zip with the expected entries")
    func writeRoundTrip() throws {
        let workbook = XlsxWorkbook()
        let sheet = workbook.addSheet(name: "Hello")
        sheet.setText(row: 1, col: 1, "Greeting", style: .bold)
        sheet.setNumber(row: 2, col: 1, 3.5)
        sheet.setFormula(row: 3, col: 1, "SUM(A2:A2)", style: .boldDecimal2)

        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try workbook.write(to: url)

        let archive = try #require(Archive(url: url, accessMode: .read))
        let names = Set(archive.map(\.path))
        #expect(names.contains("[Content_Types].xml"))
        #expect(names.contains("_rels/.rels"))
        #expect(names.contains("xl/workbook.xml"))
        #expect(names.contains("xl/_rels/workbook.xml.rels"))
        #expect(names.contains("xl/styles.xml"))
        #expect(names.contains("xl/worksheets/sheet1.xml"))

        let sheetXML = try Self.readEntry(in: archive, named: "xl/worksheets/sheet1.xml")
        #expect(sheetXML.contains("Greeting"))
        #expect(sheetXML.contains("<v>3.5</v>"))
        #expect(sheetXML.contains("<f>SUM(A2:A2)</f>"))

        let workbookXML = try Self.readEntry(in: archive, named: "xl/workbook.xml")
        #expect(workbookXML.contains("name=\"Hello\""))
    }

    @Test("text cells are XML-escaped")
    func escapesText() throws {
        let workbook = XlsxWorkbook()
        let sheet = workbook.addSheet(name: "Esc")
        sheet.setText(row: 1, col: 1, "a & <b> 'c' \"d\"")

        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try workbook.write(to: url)

        let archive = try #require(Archive(url: url, accessMode: .read))
        let xml = try Self.readEntry(in: archive, named: "xl/worksheets/sheet1.xml")
        // Element character data: only & < > are escaped.
        #expect(xml.contains("a &amp; &lt;b&gt; 'c' \"d\""))
    }

    @Test("date cells emit Excel serial values")
    func dateCells() throws {
        let workbook = XlsxWorkbook()
        let sheet = workbook.addSheet(name: "Dates")
        // Excel epoch is 1899-12-30; 2020-01-01 (UTC) is serial 43831.
        var components = DateComponents()
        components.year = 2020; components.month = 1; components.day = 1
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: components)!
        sheet.setDate(row: 1, col: 1, date)

        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try workbook.write(to: url)

        let archive = try #require(Archive(url: url, accessMode: .read))
        let xml = try Self.readEntry(in: archive, named: "xl/worksheets/sheet1.xml")
        #expect(xml.contains("<v>43831</v>"))
    }

    @Test("frozen rows emit a frozen pane and autofilter sets a ref")
    func freezeAndFilter() throws {
        let workbook = XlsxWorkbook()
        let sheet = workbook.addSheet(name: "Frozen")
        sheet.setText(row: 1, col: 1, "Header")
        sheet.frozenRows = 1
        sheet.autoFilterRange = "A1:C10"

        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try workbook.write(to: url)

        let archive = try #require(Archive(url: url, accessMode: .read))
        let xml = try Self.readEntry(in: archive, named: "xl/worksheets/sheet1.xml")
        #expect(xml.contains("ySplit=\"1\""))
        #expect(xml.contains("state=\"frozen\""))
        #expect(xml.contains("<autoFilter ref=\"A1:C10\"/>"))
    }

    @Test("custom styles register fonts, fills and borders")
    func customStyles() throws {
        let workbook = XlsxWorkbook()
        let sheet = workbook.addSheet(name: "Style")
        let headerStyle = XlsxStyle(
            bold: true,
            fontColor: "FFFFFFFF",
            fillColor: "FF305496",
            hAlign: .center,
            wrapText: true
        )
        sheet.setText(row: 1, col: 1, "Hi", style: headerStyle)

        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try workbook.write(to: url)

        let archive = try #require(Archive(url: url, accessMode: .read))
        let styles = try Self.readEntry(in: archive, named: "xl/styles.xml")
        #expect(styles.contains("<color rgb=\"FFFFFFFF\"/>"))
        #expect(styles.contains("<fgColor rgb=\"FF305496\"/>"))
        #expect(styles.contains("horizontal=\"center\""))
        #expect(styles.contains("wrapText=\"1\""))
        #expect(styles.contains("<b/>"))
    }

    @Test("sheet padding shifts cells, formulas, autofilter, freeze, and CF")
    func sheetPadding() throws {
        let workbook = XlsxWorkbook()
        let sheet = workbook.addSheet(name: "Pad")
        sheet.topPadding = 1
        sheet.leftPadding = 1
        sheet.paddingRowHeight = 8
        sheet.paddingColumnWidth = 1.5
        sheet.frozenRows = 1
        sheet.autoFilterRange = "A1:B3"
        sheet.conditionalFormats.append(.dataBar(range: "B2:B3", color: "FF638EC6"))
        sheet.setText(row: 1, col: 1, "Header")
        sheet.setNumber(row: 2, col: 2, 1)
        sheet.setNumber(row: 3, col: 2, 2)
        sheet.setFormula(row: 4, col: 2, "SUM(B2:B3)")

        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try workbook.write(to: url)

        let archive = try #require(Archive(url: url, accessMode: .read))
        let xml = try Self.readEntry(in: archive, named: "xl/worksheets/sheet1.xml")

        // Cells shifted by one row + one col: A1 → B2, B4 → C5.
        #expect(xml.contains("r=\"B2\""))
        #expect(xml.contains("r=\"C5\""))
        // Formula references shifted too.
        #expect(xml.contains("<f>SUM(C3:C4)</f>"))
        // Autofilter and CF ranges shifted.
        #expect(xml.contains("<autoFilter ref=\"B2:C4\"/>"))
        #expect(xml.contains("sqref=\"C3:C4\""))
        // Freeze pane includes the padding row, so ySplit is 2 (1 padding + 1 header).
        #expect(xml.contains("ySplit=\"2\""))
        // Padding column width and row height present.
        #expect(xml.contains("<col min=\"1\" max=\"1\" width=\"1.5\""))
        #expect(xml.contains("<row r=\"1\" ht=\"8.0\" customHeight=\"1\"/>"))
    }

    @Test("multiple sheets get distinct sheetN.xml entries")
    func multipleSheets() throws {
        let workbook = XlsxWorkbook()
        _ = workbook.addSheet(name: "First")
        _ = workbook.addSheet(name: "Second")
        _ = workbook.addSheet(name: "Third")

        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try workbook.write(to: url)

        let archive = try #require(Archive(url: url, accessMode: .read))
        let names = Set(archive.map(\.path))
        #expect(names.contains("xl/worksheets/sheet1.xml"))
        #expect(names.contains("xl/worksheets/sheet2.xml"))
        #expect(names.contains("xl/worksheets/sheet3.xml"))

        let workbookXML = try Self.readEntry(in: archive, named: "xl/workbook.xml")
        #expect(workbookXML.contains("name=\"First\""))
        #expect(workbookXML.contains("name=\"Second\""))
        #expect(workbookXML.contains("name=\"Third\""))
    }

    private static func readEntry(in archive: Archive, named name: String) throws -> String {
        guard let entry = archive[name] else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing \(name)"])
        }
        var data = Data()
        _ = try archive.extract(entry) { chunk in data.append(chunk) }
        return String(decoding: data, as: UTF8.self)
    }
}
