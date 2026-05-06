import SwiftUI

enum EditSheet: Identifiable {
    case new(date: String)
    case edit(Entry)

    var id: String {
        switch self {
        case .new(let d): return "new-\(d)"
        case .edit(let e): return "edit-\(e.id)"
        }
    }
}

struct EntrySheet: View {
    let sheet: EditSheet
    let onDismiss: () -> Void

    private let storage = Storage.shared

    @State private var client: String
    @State private var project: String
    @State private var task: String
    @State private var seconds: Int
    @State private var notes: String
    @State private var showDeleteConfirm = false
    @State private var hasManualHoursEdit = false
    @FocusState private var hoursFocused: Bool

    private let originalEntry: Entry?
    private let date: String
    private let runningStart: Date?
    private let runningBaseSeconds: Int
    private let runningEntryId: String?

    init(sheet: EditSheet, onDismiss: @escaping () -> Void) {
        self.sheet = sheet
        self.onDismiss = onDismiss
        switch sheet {
        case .new(let date):
            self.originalEntry = nil
            self.date = date
            self.runningStart = nil
            self.runningBaseSeconds = 0
            self.runningEntryId = nil
            let last = Storage.shared.mostRecentEntry()
            _client = State(initialValue: last?.client ?? "")
            _project = State(initialValue: last?.project ?? "")
            _task = State(initialValue: last?.task ?? "")
            _seconds = State(initialValue: 0)
            _notes = State(initialValue: "")
        case .edit(let entry):
            self.originalEntry = entry
            self.date = entry.date
            let siblings = Storage.shared.entries.filter {
                $0.date == entry.date &&
                $0.client == entry.client &&
                $0.project == entry.project &&
                $0.task == entry.task
            }
            let combinedSeconds = siblings.reduce(0) { $0 + $1.seconds }
            let combinedNotes = siblings
                .map(\.notes)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .joined(separator: "\n")
            let runningSibling = siblings.first(where: \.isRunning)
            let startDate = runningSibling?.startedAt
                .flatMap { DateFormat.timestampFormatter.date(from: $0) }
            self.runningStart = startDate
            self.runningBaseSeconds = combinedSeconds
            self.runningEntryId = runningSibling?.id
            let initialSeconds: Int = {
                guard let start = startDate else { return combinedSeconds }
                return combinedSeconds + max(0, Int(Date.now.timeIntervalSince(start)))
            }()
            _client = State(initialValue: entry.client)
            _project = State(initialValue: entry.project)
            _task = State(initialValue: entry.task)
            _seconds = State(initialValue: initialSeconds)
            _notes = State(initialValue: combinedNotes)
        }
    }

    private var isRunning: Bool { runningStart != nil }

    private var clients: [String] { storage.uniqueClientNames() }
    private var projects: [String] { storage.projects(for: client) }
    private var tasks: [String] { storage.taskNames(for: trimmedClient) }

    private var trimmedClient: String { client.trimmingCharacters(in: .whitespaces) }
    private var trimmedProject: String { project.trimmingCharacters(in: .whitespaces) }
    private var trimmedTask: String { task.trimmingCharacters(in: .whitespaces) }

    private var canSave: Bool {
        !trimmedClient.isEmpty && !trimmedProject.isEmpty && !trimmedTask.isEmpty && seconds >= 0
    }

    private var isEditing: Bool { originalEntry != nil }

    private var favoriteBinding: Binding<Bool> {
        Binding(
            get: {
                guard canSave else { return false }
                return storage.isFavorite(client: trimmedClient, project: trimmedProject, task: trimmedTask)
            },
            set: { newValue in
                guard canSave else { return }
                let fav = Favorite(client: trimmedClient, project: trimmedProject, task: trimmedTask)
                if newValue { storage.addFavorite(fav) }
                else { storage.removeFavorite(fav) }
            }
        )
    }

    var body: some View {
        Group {
            if isRunning && !hasManualHoursEdit {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    content
                        .onChange(of: context.date) { _, newNow in
                            tickRunningSeconds(at: newNow)
                        }
                }
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEditing ? "Edit Entry" : "New Entry")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                PickerField(title: "Client", options: clients, selection: $client)
                PickerField(title: "Project", options: projects, selection: $project)
                PickerField(title: "Task", options: tasks, selection: $task)
                HoursField(seconds: $seconds, isFocused: $hoursFocused, onUserEdit: {
                    hasManualHoursEdit = true
                })
                NotesField(text: $notes)
                FavoriteRow(isOn: favoriteBinding, isEnabled: canSave)
            }
            .padding()

            Spacer(minLength: 0)

            Divider()

            HStack {
                if isEditing {
                    Button("Delete", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
                Spacer()
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 400, height: 380)
        .onAppear {
            if (isEditing || canSave) && !isRunning {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    hoursFocused = true
                }
            }
        }
        .onChange(of: client) { _, newClient in
            cascadeFromClient(newClient)
        }
        .onChange(of: project) { _, newProject in
            cascadeFromProject(newProject)
        }
        .confirmationDialog("Delete this entry?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let id = originalEntry?.id {
                    storage.deleteEntry(id: id)
                }
                onDismiss()
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private func tickRunningSeconds(at now: Date) {
        guard let start = runningStart, !hasManualHoursEdit else { return }
        let live = runningBaseSeconds + max(0, Int(now.timeIntervalSince(start)))
        if seconds != live { seconds = live }
    }

    private func cascadeFromClient(_ newClient: String) {
        guard !newClient.isEmpty else { return }
        let projectsForClient = storage.projects(for: newClient)
        let tasksForClient = storage.taskNames(for: newClient)

        let projectStillValid = projectsForClient.contains(project)
        let taskStillValid = tasksForClient.contains(task)

        guard !projectStillValid || !taskStillValid else { return }

        if let recent = storage.mostRecentEntry(client: newClient) {
            project = recent.project
            task = recent.task
        } else {
            project = projectsForClient.first ?? ""
            task = ""
        }
    }

    private func cascadeFromProject(_ newProject: String) {
        guard !newProject.isEmpty, !client.isEmpty else { return }
        if task.isEmpty || !storage.taskNames(for: client).contains(task) {
            if let recent = storage.mostRecentEntry(client: client, project: newProject) {
                task = recent.task
            }
        }
    }

    private func save() {
        storage.addClient(ClientProject(client: trimmedClient, project: trimmedProject))
        storage.addTask(name: trimmedTask, for: trimmedClient)

        let isEditingSameCombo = isEditing &&
            originalEntry!.date == date &&
            originalEntry!.client == trimmedClient &&
            originalEntry!.project == trimmedProject &&
            originalEntry!.task == trimmedTask

        if isEditing, !isEditingSameCombo {
            let oldGroup = storage.entries.filter {
                $0.date == originalEntry!.date &&
                $0.client == originalEntry!.client &&
                $0.project == originalEntry!.project &&
                $0.task == originalEntry!.task
            }
            for entry in oldGroup {
                storage.deleteEntry(id: entry.id)
            }
        }

        let targetSiblings = storage.entries.filter {
            $0.date == date &&
            $0.client == trimmedClient &&
            $0.project == trimmedProject &&
            $0.task == trimmedTask
        }

        let finalSeconds: Int
        let finalNotes: String
        if isEditingSameCombo {
            finalSeconds = seconds
            finalNotes = notes
        } else {
            finalSeconds = targetSiblings.reduce(0) { $0 + $1.seconds } + seconds
            let existingNotes = targetSiblings
                .map(\.notes)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .joined(separator: "\n")
            let entered = notes.trimmingCharacters(in: .whitespaces)
            finalNotes = [existingNotes, entered]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }

        let preserveRunning = isRunning && isEditingSameCombo
        let keepId: String = isEditingSameCombo
            ? (preserveRunning ? (runningEntryId ?? originalEntry!.id) : originalEntry!.id)
            : (targetSiblings.first?.id ?? UUID().uuidString)

        for sibling in targetSiblings where sibling.id != keepId {
            storage.deleteEntry(id: sibling.id)
        }

        let nowDate = Date.now
        let nowText = DateFormat.timestamp(from: nowDate)

        let savedSeconds: Int
        let savedStartedAt: String?
        let savedStoppedAt: String?
        if preserveRunning {
            if hasManualHoursEdit {
                savedSeconds = finalSeconds
                savedStartedAt = nowText
            } else {
                savedSeconds = runningBaseSeconds
                savedStartedAt = runningStart.map { DateFormat.timestamp(from: $0) }
                    ?? originalEntry?.startedAt
            }
            savedStoppedAt = nil
        } else {
            savedSeconds = finalSeconds
            savedStartedAt = targetSiblings.compactMap(\.startedAt).min()
                ?? originalEntry?.startedAt
            savedStoppedAt = nowText
        }

        storage.upsertEntry(Entry(
            id: keepId,
            date: date,
            client: trimmedClient,
            project: trimmedProject,
            task: trimmedTask,
            seconds: savedSeconds,
            notes: finalNotes,
            startedAt: savedStartedAt,
            stoppedAt: savedStoppedAt
        ))
        onDismiss()
    }
}

private struct PickerField: View {
    let title: String
    let options: [String]
    @Binding var selection: String

    @State private var isAdding = false
    @State private var newValue = ""
    @State private var preAddingSelection = ""
    @FocusState private var newValueFocused: Bool

    var body: some View {
        HStack {
            Text(title)
                .frame(width: 64, alignment: .trailing)
                .foregroundStyle(.secondary)

            if isAdding {
                TextField("New \(title.lowercased())", text: $newValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .focused($newValueFocused)
                    .onChange(of: newValue) { _, value in
                        // Live-sync to the parent so a Save-button click
                        // (which on macOS doesn't move focus) still picks up
                        // whatever has been typed.
                        selection = value
                    }
                    .onSubmit { commitNew() }
                    .onChange(of: newValueFocused) { _, focused in
                        if !focused && isAdding { commitNew() }
                    }

                Button {
                    cancelNew()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Cancel")
            } else {
                Picker("", selection: $selection) {
                    if selection.isEmpty {
                        Text("Choose…").tag("")
                    } else if !options.contains(selection) {
                        Text(selection).tag(selection)
                    }
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 220, alignment: .leading)

                Spacer(minLength: 0)

                Button {
                    enterAddingMode()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add new \(title.lowercased())")
            }
        }
        .onAppear {
            if options.isEmpty && selection.isEmpty {
                enterAddingMode()
            }
        }
    }

    private func enterAddingMode() {
        preAddingSelection = selection
        newValue = ""
        selection = ""
        isAdding = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000)
            newValueFocused = true
        }
    }

    private func commitNew() {
        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            // Empty edit → fall back to whatever was selected before adding.
            selection = preAddingSelection
        } else {
            selection = trimmed
        }
        isAdding = false
        newValue = ""
    }

    private func cancelNew() {
        // Order matters: clear isAdding first so the trailing focus-loss
        // event from removing the TextField doesn't fire commitNew over the
        // restored selection.
        isAdding = false
        selection = preAddingSelection
        newValue = ""
    }
}

enum HoursInput {
    /// Parses a duration string into seconds. Accepted forms:
    ///   - Empty                       → 0
    ///   - `1:30`                      → h:mm (minutes 0–59)
    ///   - `1.5`                       → bare decimal hours
    ///   - `1h`, `5m`, `300min`, …     → unit-suffixed value
    ///   - `1h 5m`, `1h5m`, `1.5h 30m` → multiple unit-suffixed values, summed
    /// Units are case-insensitive: `h`/`hr`/`hrs`/`hour`/`hours` for hours,
    /// `m`/`min`/`mins`/`minute`/`minutes` for minutes. Negatives are rejected.
    static func parse(_ s: String) -> Int? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return 0 }

        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":")
            guard parts.count == 2,
                  let h = Int(parts[0]), h >= 0,
                  let m = Int(parts[1]), m >= 0, m < 60 else { return nil }
            return h * 3600 + m * 60
        }

        if let f = Double(trimmed), f >= 0 {
            return Int((f * 3600).rounded())
        }

        return parseUnits(trimmed.lowercased())
    }

    private static func parseUnits(_ s: String) -> Int? {
        let chars = Array(s)
        var i = 0
        var totalSeconds = 0.0
        var sawAnyToken = false

        while i < chars.count {
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            guard i < chars.count else { break }

            let numStart = i
            while i < chars.count, chars[i].isNumber || chars[i] == "." {
                i += 1
            }
            guard numStart < i, let value = Double(String(chars[numStart..<i])), value >= 0 else {
                return nil
            }

            while i < chars.count, chars[i].isWhitespace { i += 1 }

            let unitStart = i
            while i < chars.count, chars[i].isLetter { i += 1 }
            let unit = String(chars[unitStart..<i])

            let factor: Double
            switch unit {
            case "h", "hr", "hrs", "hour", "hours":   factor = 3600
            case "m", "min", "mins", "minute", "minutes": factor = 60
            default: return nil  // bare number was handled in `parse`; mixed tokens require units
            }

            totalSeconds += value * factor
            sawAnyToken = true
        }

        guard sawAnyToken else { return nil }
        return Int(totalSeconds.rounded())
    }
}

private struct HoursField: View {
    @Binding var seconds: Int
    @FocusState.Binding var isFocused: Bool
    var onUserEdit: () -> Void = {}

    @State private var text: String = ""
    @State private var initialized = false

    var body: some View {
        HStack {
            Text("Hours")
                .frame(width: 64, alignment: .trailing)
                .foregroundStyle(.secondary)

            TextField("0:00", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .focused($isFocused)
                .onAppear {
                    guard !initialized else { return }
                    text = format(seconds)
                    initialized = true
                }
                .onChange(of: seconds) { _, newSeconds in
                    if !isFocused { text = format(newSeconds) }
                }
                .onChange(of: text) { oldText, newText in
                    guard isFocused, oldText != newText else { return }
                    onUserEdit()
                    // Live-parse so a Save click without blur still gets the
                    // latest typed value. Invalid partials leave seconds at
                    // its last valid parse — that's reformatted on blur.
                    if let parsed = HoursInput.parse(newText) {
                        seconds = parsed
                    }
                }
                .onChange(of: isFocused) { _, nowFocused in
                    if !nowFocused { commit() }
                }
                .onSubmit { commit() }
        }
    }

    private func commit() {
        if let parsed = HoursInput.parse(text) { seconds = parsed }
        text = format(seconds)
    }

    private func format(_ seconds: Int) -> String {
        TimeFormat.hoursMinutes(seconds)
    }
}

private struct FavoriteRow: View {
    @Binding var isOn: Bool
    let isEnabled: Bool

    var body: some View {
        HStack {
            Color.clear.frame(width: 64)
            Toggle(isOn: $isOn) {
                Label("Favorite", systemImage: isOn ? "star.fill" : "star")
            }
            .toggleStyle(.checkbox)
            .disabled(!isEnabled)
            Spacer()
        }
    }
}

private struct NotesField: View {
    @Binding var text: String

    var body: some View {
        HStack(alignment: .top) {
            Text("Notes")
                .frame(width: 64, alignment: .trailing)
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            TextField("Optional", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
        }
    }
}
