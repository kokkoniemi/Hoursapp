import Foundation
import ZIPFoundation

/// Minimal, in-memory OOXML (.xlsx) writer.
///
/// Supports inline-string / number / formula / date cells, a composable style
/// system (font / fill / border / alignment / number-format), per-column
/// widths, frozen panes, and autofilter ranges. Files open cleanly in Excel,
/// Numbers, and LibreOffice; formulas are recalculated on open.
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
        // Collect every style used across sheets so we can write one styles.xml
        // and reference it from each sheet's cells.
        let registry = XlsxStyleRegistry()
        for sheet in sheets { sheet.populate(registry: registry) }

        var files: [(String, Data)] = []
        files.append(("[Content_Types].xml", contentTypesXML().utf8Data))
        files.append(("_rels/.rels", rootRelsXML().utf8Data))
        files.append(("xl/workbook.xml", workbookXML().utf8Data))
        files.append(("xl/_rels/workbook.xml.rels", workbookRelsXML().utf8Data))
        files.append(("xl/styles.xml", registry.serialize().utf8Data))
        for sheet in sheets {
            files.append(("xl/worksheets/sheet\(sheet.sheetId).xml",
                          sheet.serialize(registry: registry).utf8Data))
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

    enum XlsxError: Error {
        case archiveCreate
    }
}

// MARK: - Style model

struct XlsxStyle: Hashable {
    var bold: Bool = false
    /// ARGB hex like "FFFFFFFF" — nil means default (black).
    var fontColor: String? = nil
    /// ARGB hex; nil means no fill.
    var fillColor: String? = nil
    var hAlign: XlsxHAlign? = nil
    var vAlign: XlsxVAlign? = nil
    var wrapText: Bool = false
    var border: XlsxBorder = .init()
    var numberFormat: XlsxNumberFormat? = nil

    static let `default`     = XlsxStyle()
    static let bold          = XlsxStyle(bold: true)
    static let decimal2      = XlsxStyle(numberFormat: .decimal2)
    static let boldDecimal2  = XlsxStyle(bold: true, numberFormat: .decimal2)
}

enum XlsxHAlign: String, Hashable { case left, center, right }
enum XlsxVAlign: String, Hashable { case top, center, bottom }

struct XlsxBorder: Hashable {
    var top: XlsxBorderEdge? = nil
    var bottom: XlsxBorderEdge? = nil
    var left: XlsxBorderEdge? = nil
    var right: XlsxBorderEdge? = nil

    var isEmpty: Bool { top == nil && bottom == nil && left == nil && right == nil }
}

enum XlsxBorderEdge: String, Hashable {
    case thin, medium, thick
}

enum XlsxNumberFormat: Hashable {
    case decimal2
    case integer
    case percent
    case date
    case hoursMinutes
    case custom(String)

    var code: String {
        switch self {
        case .decimal2:      return "0.00"
        case .integer:       return "0"
        case .percent:       return "0%"
        case .date:          return "yyyy-mm-dd"
        case .hoursMinutes:  return "[h]:mm"
        case .custom(let s): return s
        }
    }
}

// MARK: - Style registry

/// Interns the unique fonts / fills / borders / number-formats / cellXfs used
/// across the workbook and emits a single `styles.xml`.
final class XlsxStyleRegistry {
    fileprivate struct Font: Hashable { var bold = false; var color: String? = nil; var size = 11; var name = "Calibri" }
    fileprivate enum Fill: Hashable {
        case none
        case gray125
        case solid(color: String)
    }
    fileprivate struct CellXf: Hashable {
        var numFmtId: Int
        var fontId: Int
        var fillId: Int
        var borderId: Int
        var alignment: Alignment?
    }
    fileprivate struct Alignment: Hashable {
        var horizontal: XlsxHAlign?
        var vertical: XlsxVAlign?
        var wrapText: Bool
    }

    // Excel reserves fill index 0 = none, 1 = gray125 — they must appear even
    // when unused, otherwise some tools choke.
    private var fonts: [Font] = [Font()]
    private var fills: [Fill] = [.none, .gray125]
    private var borders: [XlsxBorder] = [XlsxBorder()]
    private var customNumFmts: [String] = []   // codes; numFmtId = 164 + index
    private var cellXfs: [CellXf] = [CellXf(numFmtId: 0, fontId: 0, fillId: 0, borderId: 0, alignment: nil)]

    /// Returns the cellXf index to use for a cell with this style.
    func intern(_ style: XlsxStyle) -> Int {
        let fontId = internFont(bold: style.bold, color: style.fontColor)
        let fillId = internFill(color: style.fillColor)
        let borderId = internBorder(style.border)
        let numFmtId = internNumFmt(style.numberFormat)
        let alignment = makeAlignment(style)
        let xf = CellXf(
            numFmtId: numFmtId, fontId: fontId, fillId: fillId,
            borderId: borderId, alignment: alignment
        )
        if let idx = cellXfs.firstIndex(of: xf) { return idx }
        cellXfs.append(xf)
        return cellXfs.count - 1
    }

    private func internFont(bold: Bool, color: String?) -> Int {
        let f = Font(bold: bold, color: color)
        if let idx = fonts.firstIndex(of: f) { return idx }
        fonts.append(f)
        return fonts.count - 1
    }

    private func internFill(color: String?) -> Int {
        guard let color else { return 0 }
        let fill = Fill.solid(color: color)
        if let idx = fills.firstIndex(of: fill) { return idx }
        fills.append(fill)
        return fills.count - 1
    }

    private func internBorder(_ b: XlsxBorder) -> Int {
        if b.isEmpty { return 0 }
        if let idx = borders.firstIndex(of: b) { return idx }
        borders.append(b)
        return borders.count - 1
    }

    private func internNumFmt(_ fmt: XlsxNumberFormat?) -> Int {
        guard let fmt else { return 0 }
        let code = fmt.code
        if let idx = customNumFmts.firstIndex(of: code) { return 164 + idx }
        customNumFmts.append(code)
        return 164 + customNumFmts.count - 1
    }

    private func makeAlignment(_ s: XlsxStyle) -> Alignment? {
        guard s.hAlign != nil || s.vAlign != nil || s.wrapText else { return nil }
        return Alignment(horizontal: s.hAlign, vertical: s.vAlign, wrapText: s.wrapText)
    }

    func serialize() -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        xml += "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"

        if !customNumFmts.isEmpty {
            xml += "<numFmts count=\"\(customNumFmts.count)\">"
            for (i, code) in customNumFmts.enumerated() {
                xml += "<numFmt numFmtId=\"\(164 + i)\" formatCode=\"\(XML.escapeAttribute(code))\"/>"
            }
            xml += "</numFmts>"
        }

        xml += "<fonts count=\"\(fonts.count)\">"
        for f in fonts {
            xml += "<font>"
            if f.bold { xml += "<b/>" }
            xml += "<sz val=\"\(f.size)\"/>"
            if let color = f.color {
                xml += "<color rgb=\"\(color)\"/>"
            }
            xml += "<name val=\"\(f.name)\"/>"
            xml += "</font>"
        }
        xml += "</fonts>"

        xml += "<fills count=\"\(fills.count)\">"
        for fill in fills {
            switch fill {
            case .none:
                xml += "<fill><patternFill patternType=\"none\"/></fill>"
            case .gray125:
                xml += "<fill><patternFill patternType=\"gray125\"/></fill>"
            case .solid(let color):
                xml += "<fill><patternFill patternType=\"solid\"><fgColor rgb=\"\(color)\"/><bgColor indexed=\"64\"/></patternFill></fill>"
            }
        }
        xml += "</fills>"

        xml += "<borders count=\"\(borders.count)\">"
        for b in borders {
            xml += "<border>"
            xml += borderEdgeXML(name: "left", edge: b.left)
            xml += borderEdgeXML(name: "right", edge: b.right)
            xml += borderEdgeXML(name: "top", edge: b.top)
            xml += borderEdgeXML(name: "bottom", edge: b.bottom)
            xml += "<diagonal/>"
            xml += "</border>"
        }
        xml += "</borders>"

        xml += "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"

        xml += "<cellXfs count=\"\(cellXfs.count)\">"
        for xf in cellXfs {
            var attrs = "numFmtId=\"\(xf.numFmtId)\" fontId=\"\(xf.fontId)\" fillId=\"\(xf.fillId)\" borderId=\"\(xf.borderId)\" xfId=\"0\""
            if xf.fontId != 0 { attrs += " applyFont=\"1\"" }
            if xf.fillId != 0 { attrs += " applyFill=\"1\"" }
            if xf.borderId != 0 { attrs += " applyBorder=\"1\"" }
            if xf.numFmtId != 0 { attrs += " applyNumberFormat=\"1\"" }
            if xf.alignment != nil { attrs += " applyAlignment=\"1\"" }
            if let a = xf.alignment {
                xml += "<xf \(attrs)>"
                var inner = ""
                if let h = a.horizontal { inner += " horizontal=\"\(h.rawValue)\"" }
                if let v = a.vertical   { inner += " vertical=\"\(v.rawValue)\"" }
                if a.wrapText           { inner += " wrapText=\"1\"" }
                xml += "<alignment\(inner)/></xf>"
            } else {
                xml += "<xf \(attrs)/>"
            }
        }
        xml += "</cellXfs>"

        xml += "</styleSheet>"
        return xml
    }

    private func borderEdgeXML(name: String, edge: XlsxBorderEdge?) -> String {
        guard let edge else { return "<\(name)/>" }
        return "<\(name) style=\"\(edge.rawValue)\"><color rgb=\"FF808080\"/></\(name)>"
    }
}

// MARK: - Sheet

/// One row, one column → one cell.
struct XlsxCell {
    enum Value {
        case empty
        case text(String)
        case number(Double)
        case formula(String)
        case date(Date)
    }
    var value: Value
    var style: XlsxStyle
}

final class XlsxSheet {
    let name: String
    let sheetId: Int
    private var rows: [Int: [Int: XlsxCell]] = [:]
    private var columnWidths: [Int: Double] = [:]

    /// If > 0, this many top rows stay pinned when scrolling.
    var frozenRows: Int = 0
    /// If > 0, this many leftmost columns stay pinned when scrolling.
    var frozenCols: Int = 0
    /// Range to enable autofilter on, e.g. "A1:G100".
    var autoFilterRange: String? = nil
    /// When false, the spreadsheet reader hides its background gridlines so
    /// the deliberate banding/borders inside the data carry all the structure.
    var showGridLines: Bool = true

    /// Conditional-formatting rules (data bars, color scales). Emitted in
    /// insertion order; each gets a unique priority so Excel evaluates them
    /// deterministically.
    var conditionalFormats: [XlsxConditionalFormat] = []

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

    func setDate(row: Int, col: Int, _ date: Date, style: XlsxStyle = XlsxStyle(numberFormat: .date)) {
        write(row: row, col: col, cell: XlsxCell(value: .date(date), style: style))
    }

    func setColumnWidth(col: Int, width: Double) {
        columnWidths[col] = width
    }

    private func write(row: Int, col: Int, cell: XlsxCell) {
        precondition(row >= 1 && col >= 1, "row/col are 1-based")
        rows[row, default: [:]][col] = cell
    }

    /// Walk every cell so the registry sees its style.
    func populate(registry: XlsxStyleRegistry) {
        for (_, row) in rows {
            for (_, cell) in row {
                _ = registry.intern(cell.style)
            }
        }
    }

    func serialize(registry: XlsxStyleRegistry) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        """

        // sheetViews: freeze panes and gridline visibility live here.
        let needsSheetView = frozenRows > 0 || frozenCols > 0 || !showGridLines
        if needsSheetView {
            let gridlinesAttr = showGridLines ? "" : " showGridLines=\"0\""
            xml += "<sheetViews><sheetView workbookViewId=\"0\"\(gridlinesAttr)>"
            if frozenRows > 0 || frozenCols > 0 {
                let xSplit = frozenCols
                let ySplit = frozenRows
                let topLeft = XlsxRef.cellRef(row: ySplit + 1, col: xSplit + 1)
                let activePane: String
                if xSplit > 0 && ySplit > 0 { activePane = "bottomRight" }
                else if xSplit > 0          { activePane = "topRight" }
                else                        { activePane = "bottomLeft" }
                xml += "<pane xSplit=\"\(xSplit)\" ySplit=\"\(ySplit)\" topLeftCell=\"\(topLeft)\" activePane=\"\(activePane)\" state=\"frozen\"/>"
            }
            xml += "</sheetView></sheetViews>"
        }

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
                xml += serialize(cell: cell, row: rowIndex, col: colIndex, registry: registry)
            }
            xml += "</row>"
        }
        xml += "</sheetData>"

        if let range = autoFilterRange {
            xml += "<autoFilter ref=\"\(range)\"/>"
        }

        for (priority, cf) in conditionalFormats.enumerated() {
            xml += cf.serialize(priority: priority + 1)
        }

        xml += "</worksheet>"
        return xml
    }

    private func serialize(cell: XlsxCell, row: Int, col: Int, registry: XlsxStyleRegistry) -> String {
        let ref = XlsxRef.cellRef(row: row, col: col)
        let styleId = registry.intern(cell.style)
        let styleAttr = styleId == 0 ? "" : " s=\"\(styleId)\""
        switch cell.value {
        case .empty:
            return ""
        case .text(let s):
            return "<c r=\"\(ref)\" t=\"inlineStr\"\(styleAttr)><is><t xml:space=\"preserve\">\(XML.escapeText(s))</t></is></c>"
        case .number(let d):
            return "<c r=\"\(ref)\"\(styleAttr)><v>\(XlsxNumber.format(d))</v></c>"
        case .formula(let f):
            return "<c r=\"\(ref)\"\(styleAttr)><f>\(XML.escapeText(f))</f></c>"
        case .date(let d):
            return "<c r=\"\(ref)\"\(styleAttr)><v>\(XlsxNumber.format(d.excelSerial))</v></c>"
        }
    }
}

// MARK: - Conditional formatting

enum XlsxConditionalFormat {
    /// Fills each cell with a horizontal bar proportional to its value within
    /// the range's min/max. Great for "instant relative-effort" reads.
    case dataBar(range: String, color: String)

    /// 3-stop color scale: paints each cell from `low` (range min) through
    /// `mid` (at `midPercentile`) up to `high` (range max). Ideal for the
    /// calendar heatmap.
    case colorScale3(range: String, low: String, mid: String, high: String, midPercentile: Int = 50)

    func serialize(priority: Int) -> String {
        switch self {
        case .dataBar(let range, let color):
            return """
            <conditionalFormatting sqref="\(range)"><cfRule type="dataBar" priority="\(priority)"><dataBar><cfvo type="min"/><cfvo type="max"/><color rgb="\(color)"/></dataBar></cfRule></conditionalFormatting>
            """
        case .colorScale3(let range, let low, let mid, let high, let midPct):
            return """
            <conditionalFormatting sqref="\(range)"><cfRule type="colorScale" priority="\(priority)"><colorScale><cfvo type="min"/><cfvo type="percentile" val="\(midPct)"/><cfvo type="max"/><color rgb="\(low)"/><color rgb="\(mid)"/><color rgb="\(high)"/></colorScale></cfRule></conditionalFormatting>
            """
        }
    }
}

// MARK: - Date helpers

extension Date {
    /// Excel uses 1899-12-30 as day 0 (this absorbs the 1900 leap-year quirk
    /// inherited from Lotus 1-2-3, so dates from 1900-03-01 onward line up).
    var excelSerial: Double {
        let cal = Calendar.gregorianUTC
        let epoch = cal.date(from: DateComponents(year: 1899, month: 12, day: 30))!
        let days = cal.dateComponents([.day], from: epoch, to: self).day ?? 0
        return Double(days)
    }
}

private extension Calendar {
    static let gregorianUTC: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
}

// MARK: - Utility types

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
