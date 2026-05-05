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

            Button(action: model.goToToday) {
                Image(systemName: "calendar")
            }
            .buttonStyle(.borderless)
            .help("Go to today")

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
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 10)
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
