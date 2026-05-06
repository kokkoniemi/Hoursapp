import Testing
import Foundation
@testable import Hoursapp

@MainActor
@Suite("DayViewModel")
struct DayViewModelTests {
    private static var isoCalendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .current
        return c
    }

    @Test("init normalizes selectedDate to start of day")
    func initStartOfDay() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        let cal = Self.isoCalendar
        let middleOfDay = cal.date(bySettingHour: 14, minute: 30, second: 0, of: .now)!
        let vm = DayViewModel(storage: storage, today: middleOfDay)

        let comps = cal.dateComponents([.hour, .minute, .second], from: vm.selectedDate)
        #expect(comps.hour == 0 && comps.minute == 0 && comps.second == 0)
    }

    @Test("dayKey reflects selectedDate in current TZ")
    func dayKey() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        let now = Date.now
        let vm = DayViewModel(storage: storage, today: now)
        #expect(vm.dayKey == DateFormat.day(from: now))
    }

    @Test("weekDays returns 7 days with exactly one isSelected")
    func weekDaysShape() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        let vm = DayViewModel(storage: storage, today: .now)
        let days = vm.weekDays
        #expect(days.count == 7)
        #expect(days.filter(\.isSelected).count == 1)
        #expect(days.filter(\.isToday).count == 1)
    }

    @Test("weekDays sums baseSeconds per day")
    func weekDaysSums() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        let vm = DayViewModel(storage: storage, today: .now)
        let key = vm.dayKey
        storage.upsertEntry(TestSupport.entry(id: "a", date: key, seconds: 600,
                                              stoppedAt: Date.now.addingTimeInterval(-1)))
        storage.upsertEntry(TestSupport.entry(id: "b", date: key, task: "Other", seconds: 400,
                                              stoppedAt: Date.now.addingTimeInterval(-1)))

        let today = try #require(vm.weekDays.first(where: { $0.isSelected }))
        #expect(today.baseSeconds == 1000)
        #expect(today.runningStartedAt == nil)
        #expect(today.displayedSeconds(at: .now) == 1000)
    }

    @Test("weekDays surfaces a running entry's start")
    func weekDaysRunning() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        let vm = DayViewModel(storage: storage, today: .now)
        let key = vm.dayKey
        let runningStart = Date.now.addingTimeInterval(-180)
        storage.upsertEntry(TestSupport.entry(
            id: "r", date: key, seconds: 0, startedAt: runningStart
        ))

        let today = try #require(vm.weekDays.first(where: { $0.isSelected }))
        let started = try #require(today.runningStartedAt)
        #expect(abs(started.timeIntervalSince(runningStart)) < 1)
        #expect(today.hasRunningEntry)
        let displayed = today.displayedSeconds(at: .now)
        #expect(displayed >= 179 && displayed <= 200)
    }

    @Test("groupedEntries groups by client/project/task and sorts")
    func grouping() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        let vm = DayViewModel(storage: storage, today: .now)
        let key = vm.dayKey

        storage.upsertEntry(TestSupport.entry(id: "1", date: key,
            client: "Beta", project: "P", task: "T", seconds: 100,
            stoppedAt: Date.now.addingTimeInterval(-1)))
        storage.upsertEntry(TestSupport.entry(id: "2", date: key,
            client: "Beta", project: "P", task: "T", seconds: 50,
            stoppedAt: Date.now.addingTimeInterval(-1)))
        storage.upsertEntry(TestSupport.entry(id: "3", date: key,
            client: "Alpha", project: "Q", task: "U", seconds: 30,
            stoppedAt: Date.now.addingTimeInterval(-1)))

        let groups = vm.groupedEntries
        #expect(groups.count == 2)
        #expect(groups[0].client == "Alpha")
        #expect(groups[1].client == "Beta")
        #expect(groups[1].baseSeconds == 150)
        #expect(groups[1].runningStartedAt == nil)
    }

    @Test("groupedEntries propagates running start to its bucket")
    func groupingRunning() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        let vm = DayViewModel(storage: storage, today: .now)
        let key = vm.dayKey
        let runningStart = Date.now.addingTimeInterval(-60)

        storage.upsertEntry(TestSupport.entry(id: "stopped", date: key, seconds: 200,
                                              stoppedAt: Date.now.addingTimeInterval(-1)))
        storage.upsertEntry(TestSupport.entry(id: "running", date: key, seconds: 0,
                                              startedAt: runningStart))

        let group = try #require(vm.groupedEntries.first)
        #expect(group.hasRunningEntry)
        let live = group.displayedSeconds(at: .now)
        #expect(live >= 259 && live <= 280)
    }

    @Test("daysWithEntries excludes empty stopped entries")
    func daysWithEntries() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        let vm = DayViewModel(storage: storage, today: .now)
        storage.upsertEntry(TestSupport.entry(id: "empty", date: "2026-01-01", seconds: 0,
                                              stoppedAt: Date.now.addingTimeInterval(-1)))
        storage.upsertEntry(TestSupport.entry(id: "real", date: "2026-01-02", seconds: 30,
                                              stoppedAt: Date.now.addingTimeInterval(-1)))
        storage.upsertEntry(TestSupport.entry(id: "running", date: "2026-01-03", seconds: 0,
                                              startedAt: Date.now.addingTimeInterval(-10)))

        let days = vm.daysWithEntries
        #expect(!days.contains("2026-01-01"))
        #expect(days.contains("2026-01-02"))
        #expect(days.contains("2026-01-03"))
    }

    @Test("entries(for:) filters to selected day's matching combo")
    func entriesForGroup() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        let vm = DayViewModel(storage: storage, today: .now)
        let key = vm.dayKey

        storage.upsertEntry(TestSupport.entry(id: "today1", date: key,
            client: "Acme", project: "Site", task: "Design", seconds: 60,
            stoppedAt: Date.now.addingTimeInterval(-1)))
        storage.upsertEntry(TestSupport.entry(id: "today-other", date: key,
            client: "Acme", project: "Site", task: "QA", seconds: 60,
            stoppedAt: Date.now.addingTimeInterval(-1)))
        storage.upsertEntry(TestSupport.entry(id: "yesterday", date: "2020-01-01",
            client: "Acme", project: "Site", task: "Design", seconds: 60,
            stoppedAt: Date.now.addingTimeInterval(-1)))

        let group = EntryGroup(client: "Acme", project: "Site", task: "Design",
                               baseSeconds: 0, runningStartedAt: nil)
        #expect(vm.entries(for: group).map(\.id) == ["today1"])
    }

    @Test("week navigation moves selectedDate by 7 days")
    func navigation() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        let cal = Self.isoCalendar
        let anchor = cal.startOfDay(for: .now)
        let vm = DayViewModel(storage: storage, today: anchor)

        vm.goToPreviousWeek()
        #expect(cal.dateComponents([.day], from: vm.selectedDate, to: anchor).day == 7)

        vm.goToNextWeek()
        vm.goToNextWeek()
        #expect(cal.dateComponents([.day], from: anchor, to: vm.selectedDate).day == 7)

        vm.goToToday()
        #expect(cal.isDate(vm.selectedDate, inSameDayAs: anchor))
    }

    @Test("select(date:) snaps to start of day")
    func selectDate() throws {
        let (storage, dir) = try TestSupport.makeStorage()
        defer { TestSupport.cleanup(dir) }

        let vm = DayViewModel(storage: storage, today: .now)
        let cal = Self.isoCalendar
        let messy = cal.date(bySettingHour: 23, minute: 59, second: 59, of: .now)!
        vm.select(date: messy)
        let comps = cal.dateComponents([.hour, .minute, .second], from: vm.selectedDate)
        #expect(comps.hour == 0 && comps.minute == 0 && comps.second == 0)
        #expect(cal.isDate(vm.selectedDate, inSameDayAs: messy))
    }
}
