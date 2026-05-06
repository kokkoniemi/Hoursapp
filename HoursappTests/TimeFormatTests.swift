import Testing
@testable import Hoursapp

@Suite("TimeFormat")
struct TimeFormatTests {
    @Test("zero seconds renders as 0:00")
    func zero() {
        #expect(TimeFormat.hoursMinutes(0) == "0:00")
    }

    @Test("seconds under a minute round down to 0:00")
    func subMinute() {
        #expect(TimeFormat.hoursMinutes(59) == "0:00")
    }

    @Test("minute boundary")
    func minuteBoundary() {
        #expect(TimeFormat.hoursMinutes(60) == "0:01")
        #expect(TimeFormat.hoursMinutes(119) == "0:01")
        #expect(TimeFormat.hoursMinutes(120) == "0:02")
    }

    @Test("pads single-digit minutes")
    func padding() {
        #expect(TimeFormat.hoursMinutes(3 * 3600 + 5 * 60) == "3:05")
    }

    @Test("hours over ten without truncation")
    func bigHours() {
        #expect(TimeFormat.hoursMinutes(25 * 3600 + 30 * 60) == "25:30")
    }

    @Test("negative seconds clamp to zero")
    func negative() {
        #expect(TimeFormat.hoursMinutes(-500) == "0:00")
    }

    @Test("exactly an hour")
    func wholeHour() {
        #expect(TimeFormat.hoursMinutes(3600) == "1:00")
    }
}
