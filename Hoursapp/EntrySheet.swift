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

    /// Snapshots of the entry's combo as of when the sheet opened, used by
    /// `save()` to detect "did the user change which combo this entry belongs
    /// to". Mutable so an inline rename can keep them in sync — otherwise
    /// renaming the client mid-edit would make `save()` think the combo
    /// changed and trigger its move-and-merge logic.
    @State private var originalClient: String?
    @State private var originalProject: String?
    @State private var originalTask: String?

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
            _originalClient = State(initialValue: nil)
            _originalProject = State(initialValue: nil)
            _originalTask = State(initialValue: nil)
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
            _originalClient = State(initialValue: entry.client)
            _originalProject = State(initialValue: entry.project)
            _originalTask = State(initialValue: entry.task)
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

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    PickerField(
                        title: "Client",
                        options: clients,
                        selection: $client,
                        onRename: { old, new in
                            guard storage.renameClient(from: old, to: new) else { return false }
                            if originalClient == old { originalClient = new }
                            return true
                        }
                    )
                    PickerField(
                        title: "Project",
                        options: projects,
                        selection: $project,
                        onRename: { old, new in
                            guard !trimmedClient.isEmpty else { return false }
                            guard storage.renameProject(client: trimmedClient, from: old, to: new) else { return false }
                            if originalProject == old { originalProject = new }
                            return true
                        }
                    )
                    PickerField(
                        title: "Task",
                        options: tasks,
                        selection: $task,
                        onRename: { old, new in
                            guard !trimmedClient.isEmpty else { return false }
                            guard storage.renameTask(client: trimmedClient, from: old, to: new) else { return false }
                            if originalTask == old { originalTask = new }
                            return true
                        }
                    )
                    HoursField(seconds: $seconds, isFocused: $hoursFocused, onUserEdit: {
                        hasManualHoursEdit = true
                    })
                    NotesField(text: $notes)
                    FavoriteRow(isOn: favoriteBinding, isEnabled: canSave)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

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
        .frame(width: 400)
        .frame(minHeight: 380, maxHeight: 600)
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

        // Use the (possibly rename-updated) snapshots for the combo identity,
        // not the immutable originalEntry, so an inline rename doesn't fool
        // save() into thinking the user changed which combo this entry
        // belongs to.
        let isEditingSameCombo = isEditing &&
            originalEntry!.date == date &&
            originalClient == trimmedClient &&
            originalProject == trimmedProject &&
            originalTask == trimmedTask

        if isEditing, !isEditingSameCombo,
           let oc = originalClient, let op = originalProject, let ot = originalTask {
            let oldGroup = storage.entries.filter {
                $0.date == originalEntry!.date &&
                $0.client == oc &&
                $0.project == op &&
                $0.task == ot
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
    /// Rename callback. Receives `(oldName, newName)`; returns `false` if the
    /// rename was rejected (e.g. name conflict) so the field can flag it.
    var onRename: ((String, String) -> Bool)? = nil

    @State private var mode: Mode = .picking
    @State private var draft = ""
    @State private var preEditSelection = ""
    @State private var renameError = false
    @FocusState private var inputFocused: Bool

    private enum Mode { case picking, adding, renaming }

    var body: some View {
        HStack {
            Text(title)
                .frame(width: 64, alignment: .trailing)
                .foregroundStyle(.secondary)

            switch mode {
            case .adding, .renaming:
                editor
            case .picking:
                picker
            }
        }
        .onAppear {
            if mode == .picking, options.isEmpty, selection.isEmpty {
                enterAddingMode()
            }
        }
    }

    private var editor: some View {
        HStack {
            TextField(mode == .adding ? "New \(title.lowercased())" : "Rename \(title.lowercased())",
                      text: $draft)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .focused($inputFocused)
                .onChange(of: draft) { _, value in
                    renameError = false
                    if mode == .adding {
                        // Live-sync to the parent so a Save-button click
                        // (which on macOS doesn't move focus) still picks up
                        // whatever has been typed.
                        selection = value
                    }
                }
                .onSubmit { commitEditor() }
                .onChange(of: inputFocused) { _, focused in
                    if !focused, mode != .picking { commitEditor() }
                }

            if renameError {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .help("Name already in use")
            }

            Button {
                cancelEditor()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Cancel")
        }
    }

    private var picker: some View {
        HStack {
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

            if onRename != nil, !selection.isEmpty {
                Button {
                    enterRenamingMode()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Rename \(title.lowercased())")
            }

            Button {
                enterAddingMode()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("Add new \(title.lowercased())")
        }
    }

    private func enterAddingMode() {
        preEditSelection = selection
        draft = ""
        selection = ""
        renameError = false
        mode = .adding
        focusInput()
    }

    private func enterRenamingMode() {
        preEditSelection = selection
        draft = selection
        renameError = false
        mode = .renaming
        focusInput()
    }

    private func focusInput() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000)
            inputFocused = true
        }
    }

    private func commitEditor() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .adding:
            if trimmed.isEmpty {
                selection = preEditSelection
            } else {
                selection = trimmed
            }
            mode = .picking
            draft = ""
        case .renaming:
            if trimmed.isEmpty || trimmed == preEditSelection {
                selection = preEditSelection
                mode = .picking
                draft = ""
            } else if let onRename, onRename(preEditSelection, trimmed) {
                selection = trimmed
                mode = .picking
                draft = ""
            } else {
                renameError = true
                // Stay in rename mode so the user can fix the name.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 30_000_000)
                    inputFocused = true
                }
            }
        case .picking:
            break
        }
    }

    private func cancelEditor() {
        // Order matters: clear mode first so the trailing focus-loss event
        // from removing the TextField doesn't fire commitEditor over the
        // restored selection.
        mode = .picking
        selection = preEditSelection
        draft = ""
        renameError = false
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
                .lineLimit(2...12)
        }
    }
}
