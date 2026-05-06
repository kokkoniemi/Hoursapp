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
    @FocusState private var hoursFocused: Bool

    private let originalEntry: Entry?
    private let date: String

    init(sheet: EditSheet, onDismiss: @escaping () -> Void) {
        self.sheet = sheet
        self.onDismiss = onDismiss
        switch sheet {
        case .new(let date):
            self.originalEntry = nil
            self.date = date
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
            _client = State(initialValue: entry.client)
            _project = State(initialValue: entry.project)
            _task = State(initialValue: entry.task)
            _seconds = State(initialValue: combinedSeconds)
            _notes = State(initialValue: combinedNotes)
        }
    }

    private var clients: [String] { storage.uniqueClientNames() }
    private var projects: [String] { storage.projects(for: client) }
    private var tasks: [String] { storage.taskNames() }

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
                HoursField(seconds: $seconds, isFocused: $hoursFocused)
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
            if isEditing || canSave {
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

    private func cascadeFromClient(_ newClient: String) {
        guard !newClient.isEmpty else { return }
        let projectsForClient = storage.projects(for: newClient)
        if !projectsForClient.contains(project) {
            if let recent = storage.mostRecentEntry(client: newClient) {
                project = recent.project
                task = recent.task
            } else {
                project = projectsForClient.first ?? ""
                task = ""
            }
        }
    }

    private func cascadeFromProject(_ newProject: String) {
        guard !newProject.isEmpty, !client.isEmpty else { return }
        if task.isEmpty || !storage.taskNames().contains(task) {
            if let recent = storage.mostRecentEntry(client: client, project: newProject) {
                task = recent.task
            }
        }
    }

    private func save() {
        storage.addClient(ClientProject(client: trimmedClient, project: trimmedProject))
        storage.addTask(TaskType(name: trimmedTask))

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

        let keepId: String = isEditingSameCombo
            ? originalEntry!.id
            : (targetSiblings.first?.id ?? UUID().uuidString)

        for sibling in targetSiblings where sibling.id != keepId {
            storage.deleteEntry(id: sibling.id)
        }

        let earliestStarted = targetSiblings.compactMap(\.startedAt).min()
            ?? originalEntry?.startedAt
        let nowText = DateFormat.timestamp(from: .now)

        storage.upsertEntry(Entry(
            id: keepId,
            date: date,
            client: trimmedClient,
            project: trimmedProject,
            task: trimmedTask,
            seconds: finalSeconds,
            notes: finalNotes,
            startedAt: earliestStarted,
            stoppedAt: nowText
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
                    .onSubmit { commitNew() }

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
        isAdding = true
        newValue = ""
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000)
            newValueFocused = true
        }
    }

    private func commitNew() {
        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            cancelNew()
            return
        }
        selection = trimmed
        isAdding = false
        newValue = ""
    }

    private func cancelNew() {
        isAdding = false
        newValue = ""
    }
}

private struct HoursField: View {
    @Binding var seconds: Int
    @FocusState.Binding var isFocused: Bool

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
                .onChange(of: isFocused) { _, nowFocused in
                    if !nowFocused { commit() }
                }
                .onSubmit { commit() }
        }
    }

    private func commit() {
        if let parsed = parse(text) { seconds = parsed }
        text = format(seconds)
    }

    private func parse(_ s: String) -> Int? {
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
        return nil
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
