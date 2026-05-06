#!/usr/bin/env bash
# Generate docs/screenshot.png by launching Hoursapp against an isolated data
# directory, seeding the current week, and capturing the popover window.
#
# Your real ~/.hoursapp/ is never touched. The app is launched with
# HOURSAPP_DATA_DIR pointing at a throwaway tempdir; Storage.swift checks for
# that env var before falling back to ~/.hoursapp.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
SWIFT="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
XCODEBUILD="$DEVELOPER_DIR/usr/bin/xcodebuild"

SCREENSHOT_PATH="$ROOT/docs/screenshot.png"
SHOT_TMP="$(mktemp -d -t hoursapp-shot)"
DB_DIR="$SHOT_TMP/data"
DB="$DB_DIR/hoursapp.sqlite"

if pgrep -x Hoursapp >/dev/null 2>&1; then
  echo "Hoursapp is already running — quit it first so the screenshot copy can launch." >&2
  exit 1
fi

mkdir -p "$DB_DIR" "$ROOT/docs"

cleanup() {
  if [[ -n "${APP_PID:-}" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "Keeping $SHOT_TMP"
  else
    rm -rf "$SHOT_TMP"
  fi
}
trap cleanup EXIT

echo "Building Hoursapp.app (Release)…"
DERIVED="$ROOT/build/screenshot"
DEVELOPER_DIR="$DEVELOPER_DIR" "$XCODEBUILD" \
  -project Hoursapp.xcodeproj -scheme Hoursapp -configuration Release \
  -derivedDataPath "$DERIVED" build >/dev/null
APP="$DERIVED/Build/Products/Release/Hoursapp.app"
BIN="$APP/Contents/MacOS/Hoursapp"

NOW_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TODAY_DOW=$(date +%u)  # 1=Mon … 7=Sun

# Compute Mon..today date strings into DATES[0..n-1] (DATES[0]=Mon).
declare -a DATES=()
for ((i=0; i<TODAY_DOW; i++)); do
  back=$((TODAY_DOW - 1 - i))
  DATES+=("$(date -v-${back}d +%Y-%m-%d)")
done
LAST_IDX=$((${#DATES[@]} - 1))

ENTRIES_SQL=""
add() {
  # add <id> <date> <client> <project> <task> <seconds> <notes> <started_sql> <stopped_sql>
  ENTRIES_SQL+="INSERT INTO entries (id,date,client_id,project_id,task_id,seconds,notes,started_at,stopped_at,created_at,updated_at) VALUES ('$1','$2',$3,$4,$5,$6,'$7',$8,$9,'$NOW_UTC','$NOW_UTC');"$'\n'
}

for i in "${!DATES[@]}"; do
  d="${DATES[$i]}"
  case "$i" in
    0)  # Mon — meeting-heavy
      add "e${i}a" "$d" 1 1 1 3600  ""             "NULL" "'$NOW_UTC'"
      add "e${i}b" "$d" 2 2 2 5400  "kickoff call" "NULL" "'$NOW_UTC'"
      add "e${i}c" "$d" 3 3 3 9000  ""             "NULL" "'$NOW_UTC'"
      ;;
    1)  # Tue — deep work
      add "e${i}a" "$d" 3 3 3 14400 ""             "NULL" "'$NOW_UTC'"
      add "e${i}b" "$d" 3 3 4 4500  ""             "NULL" "'$NOW_UTC'"
      ;;
    2)  # Wed — mixed
      add "e${i}a" "$d" 1 1 1 1800  "standup"      "NULL" "'$NOW_UTC'"
      add "e${i}b" "$d" 2 2 2 10800 ""             "NULL" "'$NOW_UTC'"
      add "e${i}c" "$d" 3 3 3 9000  ""             "NULL" "'$NOW_UTC'"
      ;;
    3|4)  # Thu/Fri — design-heavy
      add "e${i}a" "$d" 3 3 3 18000 ""             "NULL" "'$NOW_UTC'"
      add "e${i}b" "$d" 1 1 1 3600  ""             "NULL" "'$NOW_UTC'"
      ;;
    *)  # Weekend — light
      add "e${i}a" "$d" 3 3 3 5400  ""             "NULL" "'$NOW_UTC'"
      ;;
  esac
done

# Add a running entry on the latest day so the UI shows the running-pill state.
LAST_DATE="${DATES[$LAST_IDX]}"
add "running" "$LAST_DATE" 3 4 5 120 "" "'$NOW_UTC'" "NULL"

echo "Seeding $DB"
sqlite3 "$DB" <<SQL
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;

-- GRDB's migrator looks for this table on launch. Pre-mark v1 as applied so
-- it doesn't try to recreate the schema and fail with "table already exists".
CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
INSERT INTO grdb_migrations (identifier) VALUES ('v1');

CREATE TABLE clients (
    id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE,
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE TABLE projects (
    id INTEGER PRIMARY KEY,
    client_id INTEGER NOT NULL REFERENCES clients(id) ON DELETE RESTRICT,
    name TEXT NOT NULL,
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
    UNIQUE(client_id, name)
);
CREATE INDEX idx_projects_client ON projects(client_id);
CREATE TABLE tasks (
    id INTEGER PRIMARY KEY,
    client_id INTEGER NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
    UNIQUE(client_id, name), UNIQUE(client_id, id)
);
CREATE INDEX idx_tasks_client ON tasks(client_id);
CREATE TABLE entries (
    id TEXT PRIMARY KEY, date TEXT NOT NULL,
    client_id INTEGER NOT NULL REFERENCES clients(id) ON DELETE RESTRICT,
    project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
    task_id INTEGER NOT NULL,
    seconds INTEGER NOT NULL DEFAULT 0,
    notes TEXT NOT NULL DEFAULT '',
    started_at TEXT, stopped_at TEXT,
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
    FOREIGN KEY (client_id, task_id) REFERENCES tasks(client_id, id) ON DELETE RESTRICT
);
CREATE INDEX idx_entries_date         ON entries(date);
CREATE INDEX idx_entries_running      ON entries(stopped_at) WHERE stopped_at IS NULL;
CREATE INDEX idx_entries_client_date  ON entries(client_id, project_id, task_id, date);
CREATE UNIQUE INDEX idx_entries_only_one_running ON entries((1)) WHERE stopped_at IS NULL;
CREATE TABLE favorites (
    id INTEGER PRIMARY KEY,
    client_id INTEGER NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    task_id INTEGER NOT NULL,
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
    UNIQUE(client_id, project_id, task_id),
    FOREIGN KEY (client_id, task_id) REFERENCES tasks(client_id, id) ON DELETE CASCADE
);

BEGIN;
INSERT INTO clients (id, name, created_at, updated_at) VALUES
    (1, 'Farringdon Inc',              '$NOW_UTC', '$NOW_UTC'),
    (2, 'Rotherhithe Design',          '$NOW_UTC', '$NOW_UTC'),
    (3, 'Spitalfields Communications', '$NOW_UTC', '$NOW_UTC');

INSERT INTO projects (id, client_id, name, created_at, updated_at) VALUES
    (1, 1, 'New Company Website',       '$NOW_UTC', '$NOW_UTC'),
    (2, 2, 'Product Launch',            '$NOW_UTC', '$NOW_UTC'),
    (3, 3, 'Mobile App',                '$NOW_UTC', '$NOW_UTC'),
    (4, 3, 'Summer Marketing Campaign', '$NOW_UTC', '$NOW_UTC');

INSERT INTO tasks (id, client_id, name, created_at, updated_at) VALUES
    (1, 1, 'Meetings',           '$NOW_UTC', '$NOW_UTC'),
    (2, 2, 'Project Management', '$NOW_UTC', '$NOW_UTC'),
    (3, 3, 'Design',             '$NOW_UTC', '$NOW_UTC'),
    (4, 3, 'Project Management', '$NOW_UTC', '$NOW_UTC'),
    (5, 3, 'Meetings',           '$NOW_UTC', '$NOW_UTC');

$ENTRIES_SQL

INSERT INTO favorites (client_id, project_id, task_id, created_at, updated_at) VALUES
    (1, 1, 1, '$NOW_UTC', '$NOW_UTC'),
    (3, 3, 3, '$NOW_UTC', '$NOW_UTC');
COMMIT;
SQL

echo "Launching app with HOURSAPP_DATA_DIR=$DB_DIR"
HOURSAPP_DATA_DIR="$DB_DIR" HOURSAPP_AUTO_OPEN_POPOVER=1 "$BIN" >/dev/null 2>&1 &
APP_PID=$!

# Poll for the popover window — give the app time to launch + open.
WINDOW_ID=""
for _ in $(seq 1 40); do
  sleep 0.25
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "App exited unexpectedly." >&2
    exit 1
  fi
  if WINDOW_ID=$("$SWIFT" "$ROOT/tools/find_popover_window.swift" "$APP_PID" 2>/dev/null); then
    break
  fi
done

if [[ -z "$WINDOW_ID" ]]; then
  echo "Could not locate popover window after waiting." >&2
  exit 1
fi

echo "Capturing window $WINDOW_ID → $SCREENSHOT_PATH"
# -o: no shadow, -x: no sound, -l <id>: capture by window id
screencapture -o -x -l "$WINDOW_ID" "$SCREENSHOT_PATH"

echo "Done."
