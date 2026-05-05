import SwiftUI

struct ContentView: View {
    @State private var model = DayViewModel(storage: .shared)

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(model: model)
            Divider()
            WeekStripView(model: model)
            Divider()
            EntriesListView(model: model)
            Divider()
            FooterView()
        }
        .frame(width: 480, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
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

    var body: some View {
        HStack(spacing: 0) {
            ForEach(model.weekDays) { day in
                Button {
                    model.select(date: day.date)
                } label: {
                    DayPill(day: day)
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

    private var labelColor: Color {
        if day.isSelected { return .white }
        return day.isToday ? .accentColor : .primary
    }

    private var totalColor: Color {
        day.isSelected ? .primary : .secondary
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

            Text(TimeFormat.hoursMinutes(day.totalSeconds))
                .font(.system(size: 11))
                .foregroundStyle(totalColor)
                .monospacedDigit()
        }
    }
}

private struct EntriesListView: View {
    let model: DayViewModel

    var body: some View {
        if model.groupedEntries.isEmpty {
            EmptyDayView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.groupedEntries.enumerated()), id: \.element.id) { index, group in
                        EntryRow(group: group)
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

            Text(TimeFormat.hoursMinutes(group.totalSeconds))
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(.primary)
                .monospacedDigit()

            Image(systemName: group.hasRunningEntry ? "pause.circle" : "play.circle")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(group.hasRunningEntry ? Color.accentColor : .secondary)
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
    var body: some View {
        HStack(spacing: 14) {
            Button { } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("Add entry (Phase 3)")

            Button { } label: {
                Image(systemName: "star")
            }
            .buttonStyle(.borderless)
            .help("Favorites (Phase 5)")

            Spacer()

            Button { } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings (Phase 5)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

#Preview {
    ContentView()
}
