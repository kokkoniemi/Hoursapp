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
        #expect(HoursInput.parse("1h -5m") == nil)
    }

    @Test("trims surrounding spaces and tabs")
    func whitespace() {
        #expect(HoursInput.parse("  1:30  ") == 5400)
        #expect(HoursInput.parse("\t2.0\t") == 7200)
    }

    @Test("hour-suffixed values")
    func hourSuffix() {
        #expect(HoursInput.parse("1h") == 3600)
        #expect(HoursInput.parse("2hr") == 7200)
        #expect(HoursInput.parse("3hrs") == 10800)
        #expect(HoursInput.parse("1hour") == 3600)
        #expect(HoursInput.parse("1.5h") == 5400)
    }

    @Test("minute-suffixed values")
    func minuteSuffix() {
        #expect(HoursInput.parse("5m") == 300)
        #expect(HoursInput.parse("90min") == 5400)
        #expect(HoursInput.parse("90mins") == 5400)
        #expect(HoursInput.parse("90minutes") == 5400)
        #expect(HoursInput.parse("300min") == 18000)
    }

    @Test("compound h+m forms")
    func compound() {
        #expect(HoursInput.parse("1h 5m") == 3900)
        #expect(HoursInput.parse("1h5m") == 3900)
        #expect(HoursInput.parse("1.5h 30m") == 7200)
        #expect(HoursInput.parse("2hr 15min") == 8100)
        // Order independence — minutes-then-hours is fine too.
        #expect(HoursInput.parse("30m 1h") == 5400)
    }

    @Test("unit parsing is case-insensitive")
    func caseInsensitive() {
        #expect(HoursInput.parse("1H 5M") == 3900)
        #expect(HoursInput.parse("2HR") == 7200)
    }

    @Test("rejects unknown units and bare numbers in compound form")
    func rejectsBadUnits() {
        #expect(HoursInput.parse("1h 5") == nil)
        #expect(HoursInput.parse("1day") == nil)
        #expect(HoursInput.parse("1s") == nil)   // seconds intentionally not supported
        #expect(HoursInput.parse("h") == nil)
        #expect(HoursInput.parse("1h foo") == nil)
    }
}
