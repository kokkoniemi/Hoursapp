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
