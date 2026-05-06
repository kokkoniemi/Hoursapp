import SwiftUI

struct ContentView: View {
    @State private var model = DayViewModel(storage: .shared)
    @State private var sheet: EditSheet?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 0) {
                HeaderView(model: model)
                Divider()
                WeekStripView(model: model, now: context.date)
                Divider()
                EntriesListView(model: model, sheet: $sheet, now: context.date)
                Divider()
                FooterView(sheet: $sheet, dayKey: model.dayKey)
            }
            .frame(width: 480, height: 640)
        }
        .sheet(item: $sheet) { item in
            EntrySheet(sheet: item) { sheet = nil }
        }
    }
}

private struct HeaderView: View {
    let model: DayViewModel
    @State private var showingCalendar = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: model.goToPreviousWeek) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help("Previous week")

            Spacer()

            Text(model.dayTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button {
                showingCalendar.toggle()
            } label: {
                Image(systemName: "calendar")
            }
            .buttonStyle(.borderless)
            .help("Pick a date")
            .popover(isPresented: $showingCalendar, arrowEdge: .top) {
                MonthCalendarView(model: model) {
                    showingCalendar = false
                }
            }

            Button(action: model.goToNextWeek) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .help("Next week")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct MonthCalendarView: View {
    let model: DayViewModel
    let onPick: () -> Void

    @State private var visibleMonth: Date = .now

    private static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f
    }()

    private var calendar: Calendar { model.monthCalendar }

    private var weekdayLabels: [String] {
        let symbols = (0..<7).compactMap { offset -> String? in
            let firstWeekday = calendar.firstWeekday
            let weekdayIndex = ((firstWeekday - 1 + offset) % 7)
            var components = DateComponents()
            components.weekday = weekdayIndex + 1
            guard let date = calendar.nextDate(after: .distantPast, matching: components, matchingPolicy: .nextTime) else {
                return nil
            }
            return Self.weekdayFormatter.string(from: date).uppercased()
        }
        return symbols
    }

    private var daysInGrid: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth) else { return [] }
        let firstOfMonth = monthInterval.start
        let firstWeekday = calendar.firstWeekday
        let monthStartWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leading = (monthStartWeekday - firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 0
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayCount {
            if let date = calendar.date(byAdding: .day, value: offset, to: firstOfMonth) {
                cells.append(date)
            }
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private var markers: Set<String> { model.daysWithEntries }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    if let d = calendar.date(byAdding: .month, value: -1, to: visibleMonth) {
                        visibleMonth = d
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)

                Spacer()

                Text(Self.monthTitleFormatter.string(from: visibleMonth))
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Button {
                    if let d = calendar.date(byAdding: .month, value: 1, to: visibleMonth) {
                        visibleMonth = d
                    }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 0) {
                ForEach(weekdayLabels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(daysInGrid.enumerated()), id: \.offset) { _, date in
                    if let date {
                        DayCell(
                            date: date,
                            isSelected: calendar.isDate(date, inSameDayAs: model.selectedDate),
                            isToday: calendar.isDateInToday(date),
                            hasMarker: markers.contains(DateFormat.day(from: date))
                        ) {
                            model.select(date: date)
                            onPick()
                        }
                    } else {
                        Color.clear.frame(height: 30)
                    }
                }
            }

            HStack {
                Button("Today") {
                    model.goToToday()
                    visibleMonth = .now
                    onPick()
                }
                .buttonStyle(.borderless)
                Spacer()
            }
        }
        .padding(12)
        .frame(width: 260)
        .onAppear { visibleMonth = model.selectedDate }
    }

    private struct DayCell: View {
        let date: Date
        let isSelected: Bool
        let isToday: Bool
        let hasMarker: Bool
        let onTap: () -> Void

        var body: some View {
            Button(action: onTap) {
                VStack(spacing: 2) {
                    ZStack {
                        if isSelected {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 24, height: 24)
                        } else if isToday {
                            Circle()
                                .stroke(Color.accentColor, lineWidth: 1)
                                .frame(width: 24, height: 24)
                        }
                        Text("\(Calendar.current.component(.day, from: date))")
                            .font(.system(size: 12, weight: isSelected || isToday ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .white : (isToday ? Color.accentColor : .primary))
                    }
                    .frame(height: 24)

                    Circle()
                        .fill(hasMarker ? (isSelected ? Color.white : Color.accentColor) : Color.clear)
                        .frame(width: 4, height: 4)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct WeekStripView: View {
    let model: DayViewModel
    let now: Date

    var body: some View {
        HStack(spacing: 0) {
            ForEach(model.weekDays) { day in
                Button {
                    model.select(date: day.date)
                } label: {
                    DayPill(day: day, now: now)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct DayPill: View {
    let day: WeekDay
    let now: Date

    private var labelColor: Color {
        if day.isSelected { return .white }
        return day.isToday ? .accentColor : .primary
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if day.isSelected {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 26, height: 26)
                }
                Text(day.label)
                    .font(.system(size: 12, weight: day.isSelected || day.isToday ? .semibold : .regular))
                    .foregroundStyle(labelColor)
            }
            .frame(height: 26)

            Text(TimeFormat.hoursMinutes(day.displayedSeconds(at: now)))
                .font(.system(size: 11))
                .foregroundStyle(day.isSelected ? .primary : .secondary)
                .monospacedDigit()
        }
    }
}

private struct EntriesListView: View {
    let model: DayViewModel
    @Binding var sheet: EditSheet?
    let now: Date

    var body: some View {
        if model.groupedEntries.isEmpty {
            EmptyDayView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.groupedEntries.enumerated()), id: \.element.id) { index, group in
                        EntryRow(group: group, now: now, dayKey: model.dayKey)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let entry = model.entries(for: group).first {
                                    sheet = .edit(entry)
                                }
                            }
                        if index < model.groupedEntries.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct EntryRow: View {
    let group: EntryGroup
    let now: Date
    let dayKey: String

    private let storage = Storage.shared

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(group.client)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(group.project)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(group.task)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(TimeFormat.hoursMinutes(group.displayedSeconds(at: now)))
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(.primary)
                .monospacedDigit()

            Button {
                if group.hasRunningEntry {
                    storage.stopTimer()
                } else {
                    storage.startTimer(
                        client: group.client,
                        project: group.project,
                        task: group.task,
                        on: dayKey
                    )
                }
            } label: {
                Image(systemName: group.hasRunningEntry ? "pause.circle.fill" : "play.circle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(group.hasRunningEntry ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(group.hasRunningEntry ? "Stop timer" : "Start timer")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(group.hasRunningEntry ? Color.accentColor.opacity(0.08) : Color.clear)
    }
}

private struct EmptyDayView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No time tracked")
                .font(.system(size: 13, weight: .medium))
            Text("Tap + to add an entry.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

private struct FooterView: View {
    @Binding var sheet: EditSheet?
    let dayKey: String

    var body: some View {
        HStack(spacing: 14) {
            Button {
                sheet = .new(date: dayKey)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("Add entry")
            .keyboardShortcut("n", modifiers: [.command])

            Menu {
                let favorites = Storage.shared.favorites
                if favorites.isEmpty {
                    Text("No favorites yet")
                } else {
                    ForEach(favorites, id: \.self) { fav in
                        Button("\(fav.client) — \(fav.project) — \(fav.task)") {
                            Storage.shared.startTimer(
                                client: fav.client,
                                project: fav.project,
                                task: fav.task,
                                on: dayKey
                            )
                        }
                    }
                }
            } label: {
                Image(systemName: "star")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Start timer for a favorite")

            Spacer()

            Button {
                SettingsWindowController.shared.show()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .keyboardShortcut(",", modifiers: [.command])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

#Preview {
    ContentView()
}
