import Testing
@testable import Hoursapp

@Suite("CSV parsing")
struct CSVParseTests {
    @Test("parses simple two-row file")
    func simple() {
        let rows = CSV.parse("a,b,c\n1,2,3\n")
        #expect(rows == [["a","b","c"], ["1","2","3"]])
    }

    @Test("handles missing trailing newline")
    func noTrailingNewline() {
        let rows = CSV.parse("a,b\nc,d")
        #expect(rows == [["a","b"], ["c","d"]])
    }

    @Test("preserves trailing empty field")
    func trailingEmptyField() {
        let rows = CSV.parse("a,b,\n")
        #expect(rows == [["a","b",""]])
    }

    @Test("unquotes doubled quotes inside quoted field")
    func doubledQuotes() {
        let rows = CSV.parse("\"he said \"\"hi\"\"\",x\n")
        #expect(rows == [["he said \"hi\"", "x"]])
    }

    @Test("preserves commas inside quoted fields")
    func commaInQuotes() {
        let rows = CSV.parse("\"a,b\",c\n")
        #expect(rows == [["a,b", "c"]])
    }

    @Test("preserves newlines inside quoted fields")
    func newlineInQuotes() {
        let rows = CSV.parse("\"line1\nline2\",x\n")
        #expect(rows == [["line1\nline2", "x"]])
    }

    @Test("handles CRLF line endings")
    func crlf() {
        let rows = CSV.parse("a,b\r\nc,d\r\n")
        #expect(rows == [["a","b"], ["c","d"]])
    }

    @Test("empty input yields no rows")
    func empty() {
        #expect(CSV.parse("") == [])
    }
}

@Suite("CSV encoding")
struct CSVEncodeTests {
    @Test("encodes plain rows")
    func plain() {
        let text = CSV.encode([["a","b"], ["c","d"]])
        #expect(text == "a,b\nc,d\n")
    }

    @Test("quotes fields with commas")
    func commaQuoted() {
        let text = CSV.encode([["a,b","c"]])
        #expect(text == "\"a,b\",c\n")
    }

    @Test("doubles quotes inside quoted field")
    func quotesEscaped() {
        let text = CSV.encode([["he said \"hi\""]])
        #expect(text == "\"he said \"\"hi\"\"\"\n")
    }

    @Test("quotes fields with newlines")
    func newlineQuoted() {
        let text = CSV.encode([["line1\nline2"]])
        #expect(text == "\"line1\nline2\"\n")
    }

    @Test("round-trips edge cases")
    func roundTrip() {
        let original: [[String]] = [
            ["id","notes"],
            ["1","plain"],
            ["2","has,comma"],
            ["3","has\"quote"],
            ["4","has\nnewline"],
            ["5",""],
        ]
        let encoded = CSV.encode(original)
        let decoded = CSV.parse(encoded)
        #expect(decoded == original)
    }
}
