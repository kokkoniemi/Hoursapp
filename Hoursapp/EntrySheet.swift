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

    private let originalEntry: Entry?
    private let date: String

    init(sheet: EditSheet, onDismiss: @escaping () -> Void) {
        self.sheet = sheet
        self.onDismiss = onDismiss
        switch sheet {
        case .new(let date):
            self.originalEntry = nil
            self.date = date
            _client = State(initialValue: "")
            _project = State(initialValue: "")
            _task = State(initialValue: "")
            _seconds = State(initialValue: 0)
            _notes = State(initialValue: "")
        case .edit(let entry):
            self.originalEntry = entry
            self.date = entry.date
            _client = State(initialValue: entry.client)
            _project = State(initialValue: entry.project)
            _task = State(initialValue: entry.task)
            _seconds = State(initialValue: entry.seconds)
            _notes = State(initialValue: entry.notes)
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

    private var isEditing: Bool { originalEntry != nil }

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
                LookupField(title: "Client", options: clients, selection: $client)
                LookupField(title: "Project", options: projects, selection: $project)
                LookupField(title: "Task", options: tasks, selection: $task)
                HoursField(seconds: $seconds)
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

    private func save() {
        storage.addClient(ClientProject(client: trimmedClient, project: trimmedProject))
        storage.addTask(TaskType(name: trimmedTask))

        let now = DateFormat.timestamp(from: .now)
        let started = originalEntry?.startedAt
        let stopped = originalEntry?.stoppedAt ?? now

        let entry = Entry(
            id: originalEntry?.id ?? UUID().uuidString,
            date: date,
            client: trimmedClient,
            project: trimmedProject,
            task: trimmedTask,
            seconds: seconds,
            notes: notes,
            startedAt: started,
            stoppedAt: stopped
        )
        storage.upsertEntry(entry)
        onDismiss()
    }
}

private struct LookupField: View {
    let title: String
    let options: [String]
    @Binding var selection: String

    var body: some View {
        HStack {
            Text(title)
                .frame(width: 64, alignment: .trailing)
                .foregroundStyle(.secondary)

            TextField(title, text: $selection)
                .textFieldStyle(.roundedBorder)

            Menu {
                if options.isEmpty {
                    Text("No saved \(title.lowercased())s yet")
                } else {
                    ForEach(options, id: \.self) { option in
                        Button(option) { selection = option }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

private struct HoursField: View {
    @Binding var seconds: Int

    @State private var text: String = ""
    @State private var initialized = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text("Hours")
                .frame(width: 64, alignment: .trailing)
                .foregroundStyle(.secondary)

            TextField("0:00", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onAppear {
                    guard !initialized else { return }
                    text = format(seconds)
                    initialized = true
                }
                .onChange(of: focused) { _, nowFocused in
                    if !nowFocused { commit() }
                }
                .onSubmit { commit() }

            Spacer()
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
