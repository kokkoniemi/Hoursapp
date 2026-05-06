# Hoursapp

A minimal macOS menu-bar time tracker. Lives entirely in your menu bar, stores everything in a local SQLite database under `~/.hoursapp/`, no accounts or cloud.

## Features

- Menu-bar pill that turns into a white capsule with a live clock-face icon while a timer runs
- Day view with week strip and a month-picker popover (days with entries get a dot marker)
- Per-entry timer start/stop, manual hours editing, notes, favorites for one-click starts
- Idle detection: prompts to keep / discard / stop when you've been away while a timer is running
- Sleep handling: pauses on system sleep, resumes on wake
- Long-run warning: nudges you if a timer has been on for unusually long
- Right-click the menu-bar icon for a quick-add menu (today's entries, favorites, stop, quit)
- Launch at login (toggle in Settings)
- Export to Excel (`.xlsx`) — pick a month or "All months", get a workbook with a Summary sheet (totals by client/project/task) plus an Entries sheet. The all-months variant gives one sheet per month + a cross-sheet summary. Available from the right-click menu (`⌘E`).
- SQLite storage at `~/.hoursapp/hoursapp.sqlite` with foreign keys, audit timestamps, and per-client task scoping.

## Requirements

- macOS 14.0+
- Xcode 15+ (for building from source)

## Build

The project is generated from [project.yml](project.yml) via [XcodeGen](https://github.com/yonaskolb/XcodeGen). The committed `Hoursapp.xcodeproj` is in sync; you only need XcodeGen if you change `project.yml`.

Release build + zip:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Hoursapp.xcodeproj -scheme Hoursapp -configuration Release \
  -derivedDataPath build/dist clean build

cp -R build/dist/Build/Products/Release/Hoursapp.app dist/Hoursapp.app
ditto -c -k --keepParent dist/Hoursapp.app dist/Hoursapp.zip
```

The bundle is ad-hoc signed with hardened runtime — first launch needs right-click → Open, or `xattr -dr com.apple.quarantine dist/Hoursapp.app`.

## Tests

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Hoursapp.xcodeproj -scheme Hoursapp test
```

Covers the GRDB-backed `Storage` (entries, favorites, timer flow, idle/long-run engines), the SQLite schema/FK invariants, the day view-model, the time-formatter and hours-input parser, and the `.xlsx` exporter (workbook serialization, period selection, single-month and all-months layouts).

## Tools

- [tools/seed.sh](tools/seed.sh) — wipes `~/.hoursapp/hoursapp.sqlite` and writes sample data straight into the database. Quit Hoursapp before running.
- [tools/generate_icon.swift](tools/generate_icon.swift) — regenerates the app icon PNGs into the asset catalog. Run from the repo root:

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift \
    tools/generate_icon.swift
  ```

## Data

All state lives in `~/.hoursapp/`:

| File | Contents |
| --- | --- |
| `hoursapp.sqlite` | Single SQLite database. Tables: `clients`, `projects` (FK→clients), `tasks` (FK→clients, unique per client), `entries` (FK→clients/projects/tasks, with composite FK ensuring tasks stay client-scoped), `favorites`. Each row carries `created_at` / `updated_at` timestamps. WAL mode is enabled (`-wal` / `-shm` sidecar files). |

A running entry is the row with `stopped_at IS NULL`. A partial unique index (`idx_entries_only_one_running`) enforces that at most one row may be running at a time. Writes are synchronous local SQLite transactions — no debounce, no `flushPendingWrites` needed.

You can poke at the data directly:

```sh
sqlite3 ~/.hoursapp/hoursapp.sqlite \
  "SELECT date, c.name, p.name, t.name, seconds FROM entries e
     JOIN clients c ON c.id = e.client_id
     JOIN projects p ON p.id = e.project_id
     JOIN tasks t ON t.id = e.task_id
   ORDER BY date DESC LIMIT 20;"
```
