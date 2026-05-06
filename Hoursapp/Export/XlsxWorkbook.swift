import Foundation
import ZIPFoundation

/// Minimal, in-memory OOXML (.xlsx) writer.
///
/// Only supports what Hoursapp needs: inline-string text cells, numeric cells,
/// formula cells, four preset styles (default / bold / decimal2 / bold+decimal2),
/// and per-column widths. The output opens cleanly in Excel, Numbers, and
/// LibreOffice; formulas are recalculated on open.
final class XlsxWorkbook {
    private(set) var sheets: [XlsxSheet] = []

    func addSheet(name: String) -> XlsxSheet {
        let sheet = XlsxSheet(name: name, sheetId: sheets.count + 1)
        sheets.append(sheet)
        return sheet
    }

    func write(to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        guard let archive = Archive(url: url, accessMode: .create) else {
            throw XlsxError.archiveCreate
        }
        for (path, data) in build() {
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(data.count),
                compressionMethod: .deflate,
                provider: { position, size in
                    data.subdata(in: Int(position)..<Int(position) + size)
                }
            )
        }
    }

    /// Returns the in-memory file map that gets zipped into the .xlsx.
    /// Exposed for tests.
    func build() -> [(String, Data)] {
        var files: [(String, Data)] = []
        files.append(("[Content_Types].xml", contentTypesXML().utf8Data))
        files.append(("_rels/.rels", rootRelsXML().utf8Data))
        files.append(("xl/workbook.xml", workbookXML().utf8Data))
        files.append(("xl/_rels/workbook.xml.rels", workbookRelsXML().utf8Data))
        files.append(("xl/styles.xml", stylesXML().utf8Data))
        for sheet in sheets {
            files.append(("xl/worksheets/sheet\(sheet.sheetId).xml", sheet.serialize().utf8Data))
        }
        return files
    }

    // MARK: - Part builders

    private func contentTypesXML() -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        """
        for sheet in sheets {
            xml += "<Override PartName=\"/xl/worksheets/sheet\(sheet.sheetId).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        xml += "</Types>"
        return xml
    }

    private func rootRelsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
    }

    private func workbookXML() -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets>
        """
        for sheet in sheets {
            xml += "<sheet name=\"\(XML.escapeAttribute(sheet.name))\" sheetId=\"\(sheet.sheetId)\" r:id=\"rId\(sheet.sheetId)\"/>"
        }
        xml += "</sheets></workbook>"
        return xml
    }

    private func workbookRelsXML() -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        """
        for sheet in sheets {
            xml += "<Relationship Id=\"rId\(sheet.sheetId)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(sheet.sheetId).xml\"/>"
        }
        xml += "<Relationship Id=\"rIdStyles\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        xml += "</Relationships>"
        return xml
    }

    private func stylesXML() -> String {
        // Style indexes (cellXfs):
        //   0: default
        //   1: bold (header)
        //   2: number 0.00
        //   3: bold + number 0.00
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <numFmts count="1"><numFmt numFmtId="164" formatCode="0.00"/></numFmts>
        <fonts count="2">
        <font><sz val="11"/><name val="Calibri"/></font>
        <font><b/><sz val="11"/><name val="Calibri"/></font>
        </fonts>
        <fills count="1"><fill><patternFill patternType="none"/></fill></fills>
        <borders count="1"><border/></borders>
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
        <cellXfs count="4">
        <xf numFmtId="0"   fontId="0" fillId="0" borderId="0" xfId="0"/>
        <xf numFmtId="0"   fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
        <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
        <xf numFmtId="164" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1" applyNumberFormat="1"/>
        </cellXfs>
        </styleSheet>
        """
    }

    enum XlsxError: Error {
        case archiveCreate
    }
}

/// One row, one column → one cell.
struct XlsxCell {
    enum Value {
        case empty
        case text(String)
        case number(Double)
        case formula(String)
    }
    var value: Value
    var style: XlsxStyle
}

enum XlsxStyle: Int {
    case `default` = 0
    case bold = 1
    case decimal2 = 2
    case boldDecimal2 = 3
}

final class XlsxSheet {
    let name: String
    let sheetId: Int
    private var rows: [Int: [Int: XlsxCell]] = [:]   // rowIndex (1-based) → colIndex → cell
    private var columnWidths: [Int: Double] = [:]    // colIndex (1-based) → width

    init(name: String, sheetId: Int) {
        self.name = name
        self.sheetId = sheetId
    }

    func setText(row: Int, col: Int, _ value: String, style: XlsxStyle = .default) {
        write(row: row, col: col, cell: XlsxCell(value: .text(value), style: style))
    }

    func setNumber(row: Int, col: Int, _ value: Double, style: XlsxStyle = .decimal2) {
        write(row: row, col: col, cell: XlsxCell(value: .number(value), style: style))
    }

    func setFormula(row: Int, col: Int, _ formula: String, style: XlsxStyle = .decimal2) {
        write(row: row, col: col, cell: XlsxCell(value: .formula(formula), style: style))
    }

    func setColumnWidth(col: Int, width: Double) {
        columnWidths[col] = width
    }

    private func write(row: Int, col: Int, cell: XlsxCell) {
        precondition(row >= 1 && col >= 1, "row/col are 1-based")
        rows[row, default: [:]][col] = cell
    }

    func serialize() -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        """
        if !columnWidths.isEmpty {
            xml += "<cols>"
            for (col, width) in columnWidths.sorted(by: { $0.key < $1.key }) {
                xml += "<col min=\"\(col)\" max=\"\(col)\" width=\"\(width)\" customWidth=\"1\"/>"
            }
            xml += "</cols>"
        }
        xml += "<sheetData>"
        for rowIndex in rows.keys.sorted() {
            guard let row = rows[rowIndex] else { continue }
            xml += "<row r=\"\(rowIndex)\">"
            for colIndex in row.keys.sorted() {
                guard let cell = row[colIndex] else { continue }
                xml += serialize(cell: cell, row: rowIndex, col: colIndex)
            }
            xml += "</row>"
        }
        xml += "</sheetData></worksheet>"
        return xml
    }

    private func serialize(cell: XlsxCell, row: Int, col: Int) -> String {
        let ref = XlsxRef.cellRef(row: row, col: col)
        let styleAttr = cell.style.rawValue == 0 ? "" : " s=\"\(cell.style.rawValue)\""
        switch cell.value {
        case .empty:
            return ""
        case .text(let s):
            return "<c r=\"\(ref)\" t=\"inlineStr\"\(styleAttr)><is><t xml:space=\"preserve\">\(XML.escapeText(s))</t></is></c>"
        case .number(let d):
            return "<c r=\"\(ref)\"\(styleAttr)><v>\(XlsxNumber.format(d))</v></c>"
        case .formula(let f):
            return "<c r=\"\(ref)\"\(styleAttr)><f>\(XML.escapeText(f))</f></c>"
        }
    }
}

enum XlsxRef {
    static func cellRef(row: Int, col: Int) -> String {
        columnLetter(col) + String(row)
    }

    static func columnLetter(_ col: Int) -> String {
        precondition(col >= 1)
        var n = col
        var letters = ""
        while n > 0 {
            let rem = (n - 1) % 26
            letters = String(UnicodeScalar(65 + rem)!) + letters
            n = (n - 1) / 26
        }
        return letters
    }
}

enum XlsxNumber {
    static func format(_ d: Double) -> String {
        // Avoid scientific notation; up to 6 decimals, trimming trailing zeros.
        if d == d.rounded() {
            return String(Int64(d))
        }
        var s = String(format: "%.6f", d)
        while s.last == "0" { s.removeLast() }
        if s.last == "." { s.removeLast() }
        return s
    }
}

enum XML {
    /// Escapes element character data (between tags). XML 1.0 only requires
    /// `&` and `<` to be escaped; `>` is escaped defensively to avoid `]]>`
    /// sequences. `'` and `"` are intentionally left alone so that formulas
    /// like `SUM('2026-04'!E:E)` stay readable.
    static func escapeText(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default:  out.append(c)
            }
        }
        return out
    }

    /// Escapes characters for use inside double-quoted attribute values.
    static func escapeAttribute(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "&":  out += "&amp;"
            case "<":  out += "&lt;"
            case ">":  out += "&gt;"
            case "\"": out += "&quot;"
            default:   out.append(c)
            }
        }
        return out
    }
}

private extension String {
    var utf8Data: Data { Data(utf8) }
}
