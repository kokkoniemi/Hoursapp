import SwiftUI

struct ContentView: View {
    @State private var model = DayViewModel(storage: .shared)
    @State private var sheet: EditSheet?
    @State private var visibleToastAction: Storage.UndoableAction?
    @State private var toastDismissTask: Task<Void, Never>?
    private let storage = Storage.shared

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
            .background(undoShortcut)
            .overlay(alignment: .bottom) {
                if let action = visibleToastAction {
                    UndoToast(action: action) {
                        storage.undoLastAction()
                    }
                    .padding(.bottom, 50)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(item: $sheet) { item in
            EntrySheet(sheet: item) { sheet = nil }
        }
        .onChange(of: storage.lastUndoableAction) { _, newAction in
            handleUndoableChange(newAction)
        }
    }

    private func handleUndoableChange(_ action: Storage.UndoableAction?) {
        toastDismissTask?.cancel()
        guard let action else {
            withAnimation(.snappy(duration: 0.2)) { visibleToastAction = nil }
            return
        }
        withAnimation(.snappy(duration: 0.2)) { visibleToastAction = action }
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.25)) { visibleToastAction = nil }
        }
    }

    /// Hidden ⌘Z handler. Lives in the view hierarchy so the popover's window
    /// receives the shortcut; disabled when nothing is undoable so the
    /// keystroke falls through to focused text fields (e.g. notes editing).
    private var undoShortcut: some View {
        Button("Undo") {
            storage.undoLastAction()
        }
        .keyboardShortcut("z", modifiers: .command)
        .disabled(storage.lastUndoableAction == nil)
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

            HStack(spacing: 6) {
                Text(model.dayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                if !model.isToday {
                    Button {
                        model.goToToday()
                    } label: {
                        Text("Today")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.accentColor.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Jump to today")
                }
            }

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

    private var displayedSeconds: Int { day.displayedSeconds(at: now) }

    /// Dim weekend pills that have no tracked time and aren't highlighted, so
    /// the eye reads weekdays first and isn't tricked into thinking Saturday
    /// was forgotten.
    private var isDimmed: Bool {
        day.isWeekend && displayedSeconds == 0 && !day.isSelected && !day.isToday
    }

    private var labelColor: Color {
        if day.isSelected { return .white }
        if day.isToday { return .accentColor }
        return isDimmed ? .secondary : .primary
    }

    private var timeColor: Color {
        if day.isSelected { return .primary }
        return isDimmed ? .secondary : .secondary
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

            Text(TimeFormat.hoursMinutes(displayedSeconds))
                .font(.system(size: 11))
                .foregroundStyle(timeColor)
                .monospacedDigit()
        }
        .opacity(isDimmed ? 0.45 : 1.0)
    }
}

private struct EntriesListView: View {
    let model: DayViewModel
    @Binding var sheet: EditSheet?
    let now: Date

    var body: some View {
        if model.groupedEntries.isEmpty {
            EmptyDayView(dayKey: model.dayKey)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.groupedEntries.enumerated()), id: \.element.id) { index, group in
                        EntryRow(group: group, now: now, dayKey: model.dayKey) {
                            if let entry = model.entries(for: group).first {
                                sheet = .edit(entry)
                            }
                        }
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity.combined(with: .move(edge: .leading))
                            ))
                        if index < model.groupedEntries.count - 1 {
                            Divider()
                        }
                    }
                }
                .animation(.snappy(duration: 0.22), value: model.groupedEntries.map(\.id))
            }
        }
    }
}

private struct EntryRow: View {
    let group: EntryGroup
    let now: Date
    let dayKey: String
    let onEditTap: () -> Void

    private let storage = Storage.shared

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onEditTap) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.client)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        Text(group.project)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if group.hasNotes {
                            Image(systemName: "note.text")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .help(notesTooltip)
                        }
                    }
                    Text(group.task)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            InlineEditableTime(
                seconds: group.displayedSeconds(at: now),
                running: group.hasRunningEntry,
                onCommit: { newSeconds in
                    commitInlineEdit(seconds: newSeconds)
                }
            )

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
        .contextMenu {
            if group.hasRunningEntry {
                Button("Stop timer", systemImage: "pause.fill") {
                    storage.stopTimer()
                }
            } else {
                Button("Start timer", systemImage: "play.fill") {
                    storage.startTimer(
                        client: group.client,
                        project: group.project,
                        task: group.task,
                        on: dayKey
                    )
                }
            }

            let todayKey = DateFormat.day(from: .now)
            if dayKey != todayKey {
                Button("Start on today", systemImage: "arrow.uturn.forward") {
                    storage.startTimer(
                        client: group.client,
                        project: group.project,
                        task: group.task,
                        on: todayKey
                    )
                }
            }

            Button("Edit…", systemImage: "pencil") {
                onEditTap()
            }

            Divider()

            Button("Delete entry", systemImage: "trash", role: .destructive) {
                deleteAllInGroup()
            }
        }
    }

    /// Truncates the group's combined notes for the `.help` tooltip so a long
    /// note doesn't paint a giant rectangle next to the cursor.
    private var notesTooltip: String {
        let limit = 240
        if group.notes.count > limit {
            return group.notes.prefix(limit) + "…"
        }
        return group.notes
    }

    /// Deletes every sibling entry sharing this group's combo on the current
    /// day. The row visually represents the whole group, so a single "Delete"
    /// should clear it rather than leaving stray siblings behind.
    private func deleteAllInGroup() {
        let siblings = storage.entries.filter {
            $0.date == dayKey &&
            $0.client == group.client &&
            $0.project == group.project &&
            $0.task == group.task
        }
        for sib in siblings {
            storage.deleteEntry(id: sib.id)
        }
    }

    /// Consolidates all sibling entries of this group on the current day into a
    /// single entry with the given total seconds (notes preserved). Mirrors the
    /// EntrySheet "same combo, not running" save branch.
    private func commitInlineEdit(seconds newSeconds: Int) {
        let siblings = storage.entries.filter {
            $0.date == dayKey &&
            $0.client == group.client &&
            $0.project == group.project &&
            $0.task == group.task
        }
        guard let keeper = siblings.first else { return }

        let combinedNotes = siblings
            .map(\.notes)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")

        for sib in siblings where sib.id != keeper.id {
            storage.deleteEntry(id: sib.id)
        }

        let stoppedAt = keeper.stoppedAt ?? DateFormat.timestamp(from: .now)
        let startedAt = siblings.compactMap(\.startedAt).min() ?? keeper.startedAt

        storage.upsertEntry(Entry(
            id: keeper.id,
            date: keeper.date,
            client: keeper.client,
            project: keeper.project,
            task: keeper.task,
            seconds: max(0, newSeconds),
            notes: combinedNotes,
            startedAt: startedAt,
            stoppedAt: stoppedAt
        ))
    }
}

/// Time readout that toggles into an inline editor on click. When `running`,
/// drives a smooth opacity pulse via `TimelineView(.animation)` instead — a
/// `withAnimation(.repeatForever)` inside the surrounding 1-second TimelineView
/// gets reset on every tick and never actually oscillates, so we compute
/// opacity from the wall clock each frame instead. Inline edit is disabled
/// while running: a live timer needs the pause/manual-edit dance from the full
/// sheet, not a quick adjust.
private struct InlineEditableTime: View {
    let seconds: Int
    let running: Bool
    let onCommit: (Int) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @State private var isHovered = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        if isEditing {
            editor
        } else if running {
            pulsing
        } else {
            display
        }
    }

    private var display: some View {
        Button {
            beginEdit()
        } label: {
            Text(TimeFormat.hoursMinutes(seconds))
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Edit time")
    }

    private var pulsing: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = (cos(t * .pi) + 1) / 2  // 0…1, 2 s cycle
            Text(TimeFormat.hoursMinutes(seconds))
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .opacity(0.55 + 0.45 * phase)
        }
    }

    private var editor: some View {
        TextField("", text: $draft)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 14, weight: .light))
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
            .focused($fieldFocused)
            .onSubmit { commit() }
            .onExitCommand { cancel() }
            .onChange(of: fieldFocused) { _, focused in
                if !focused { commit() }
            }
            .onKeyPress(.upArrow) {
                adjustDraft(by: 60)
                return .handled
            }
            .onKeyPress(.downArrow) {
                adjustDraft(by: -60)
                return .handled
            }
    }

    private func adjustDraft(by deltaSeconds: Int) {
        let current = HoursInput.parse(draft) ?? seconds
        let adjusted = max(0, current + deltaSeconds)
        draft = TimeFormat.hoursMinutes(adjusted)
    }

    private func beginEdit() {
        guard !running else { return }
        draft = TimeFormat.hoursMinutes(seconds)
        isEditing = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000)
            fieldFocused = true
        }
    }

    private func commit() {
        guard isEditing else { return }
        if let parsed = HoursInput.parse(draft), parsed != seconds {
            onCommit(parsed)
        }
        isEditing = false
        draft = ""
    }

    private func cancel() {
        isEditing = false
        draft = ""
    }
}

private struct UndoToast: View {
    let action: Storage.UndoableAction
    let onUndo: () -> Void

    private var message: String {
        switch action {
        case .deletedEntry:   return "Entry deleted"
        case .discardedIdle:  return "Idle time subtracted"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
            Button(action: onUndo) {
                HStack(spacing: 4) {
                    Text("Undo")
                        .font(.system(size: 12, weight: .semibold))
                    Text("⌘Z")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 8, y: 2)
    }
}

private struct EmptyDayView: View {
    let dayKey: String

    private let storage = Storage.shared

    private var favorites: [Favorite] {
        Array(storage.favorites.prefix(4))
    }

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("No time tracked")
                    .font(.system(size: 13, weight: .medium))
                Text(favorites.isEmpty ? "Tap + to add an entry." : "Start a favorite, or tap + to add an entry.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if !favorites.isEmpty {
                VStack(spacing: 6) {
                    ForEach(favorites, id: \.self) { fav in
                        FavoriteQuickStart(favorite: fav, dayKey: dayKey)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 4)
            }
        }
        .padding()
    }
}

private struct FavoriteQuickStart: View {
    let favorite: Favorite
    let dayKey: String

    @State private var isHovered = false

    var body: some View {
        Button {
            Storage.shared.startTimer(
                client: favorite.client,
                project: favorite.project,
                task: favorite.task,
                on: dayKey
            )
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.circle")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(favorite.client)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(favorite.project)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(favorite.task)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(isHovered ? 0.08 : 0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
