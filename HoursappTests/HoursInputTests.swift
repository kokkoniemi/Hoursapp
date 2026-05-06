import Testing
@testable import Hoursapp

@Suite("HoursInput parsing")
struct HoursInputTests {
    @Test("empty string parses as zero")
    func empty() {
        #expect(HoursInput.parse("") == 0)
        #expect(HoursInput.parse("   ") == 0)
    }

    @Test("h:mm format")
    func hoursColonMinutes() {
        #expect(HoursInput.parse("0:00") == 0)
        #expect(HoursInput.parse("1:30") == 5400)
        #expect(HoursInput.parse("12:05") == 12 * 3600 + 5 * 60)
    }

    @Test("rejects invalid h:mm")
    func badColon() {
        #expect(HoursInput.parse("1:60") == nil)
        #expect(HoursInput.parse("1:-5") == nil)
        #expect(HoursInput.parse(":30") == nil)
        #expect(HoursInput.parse("1:30:00") == nil)
        #expect(HoursInput.parse("a:b") == nil)
    }

    @Test("decimal hours round to nearest second")
    func decimal() {
        #expect(HoursInput.parse("1") == 3600)
        #expect(HoursInput.parse("1.5") == 5400)
        #expect(HoursInput.parse("0.25") == 900)
    }

    @Test("rejects negative or non-numeric values")
    func invalid() {
        #expect(HoursInput.parse("-1") == nil)
        #expect(HoursInput.parse("foo") == nil)
        #expect(HoursInput.parse("1h") == nil)
    }

    @Test("trims surrounding spaces and tabs")
    func whitespace() {
        #expect(HoursInput.parse("  1:30  ") == 5400)
        #expect(HoursInput.parse("\t2.0\t") == 7200)
    }
}
