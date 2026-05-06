# Hoursapp

A minimal macOS menu-bar time tracker. Lives entirely in your menu bar, stores everything as plain CSV files in `~/.hoursapp/`, no accounts or cloud.

## Features

- Menu-bar pill that turns into a white capsule with a live clock-face icon while a timer runs
- Day view with week strip and a month-picker popover (days with entries get a dot marker)
- Per-entry timer start/stop, manual hours editing, notes, favorites for one-click starts
- Idle detection: prompts to keep / discard / stop when you've been away while a timer is running
- Sleep handling: pauses on system sleep, resumes on wake
- Long-run warning: nudges you if a timer has been on for unusually long
- Right-click the menu-bar icon for a quick-add menu (today's entries, favorites, stop, quit)
- Launch at login (toggle in Settings)
- CSV-only storage at `~/.hoursapp/{clients,tasks,entries,favorites}.csv` — easy to back up, version, or edit by hand

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

Covers CSV round-tripping and `Storage` (entries, favorites, bootstrap, idempotent inserts).

## Tools

- [tools/seed.sh](tools/seed.sh) — wipes `~/.hoursapp/` and writes sample clients/projects/tasks/entries for visual testing.
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
| `clients.csv` | `client,project` pairs |
| `tasks.csv` | task names |
| `entries.csv` | `id,date,client,project,task,seconds,notes,started_at,stopped_at` |
| `favorites.csv` | `client,project,task` |

A running entry is one with an empty `stopped_at`. Writes are debounced (500 ms); the app flushes pending writes before quitting.
