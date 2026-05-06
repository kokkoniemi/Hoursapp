#!/usr/bin/env bash
# Populate ~/.hoursapp/hoursapp.sqlite with sample data for visual testing.
# Wipes any existing database. Run before launching Hoursapp to see a populated UI.
#
# The schema mirrors Hoursapp/Database/Migrations.swift; keep them in sync.
set -euo pipefail

DIR="$HOME/.hoursapp"
DB="$DIR/hoursapp.sqlite"

if pgrep -x Hoursapp >/dev/null 2>&1; then
  echo "Hoursapp is running — quit it first so the database isn't held open." >&2
  exit 1
fi

mkdir -p "$DIR"
rm -f "$DB" "$DB-wal" "$DB-shm" "$DIR/.migrated"
rm -rf "$DIR/legacy-csv-backup"

TODAY="$(date +%Y-%m-%d)"
YESTERDAY="$(date -v-1d +%Y-%m-%d)"
NOW_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

sqlite3 "$DB" <<SQL
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;

-- Schema (must match Hoursapp/Database/Migrations.swift v1)
CREATE TABLE clients (
    id          INTEGER PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE,
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL
);
CREATE TABLE projects (
    id          INTEGER PRIMARY KEY,
    client_id   INTEGER NOT NULL REFERENCES clients(id) ON DELETE RESTRICT,
    name        TEXT NOT NULL,
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL,
    UNIQUE(client_id, name)
);
CREATE INDEX idx_projects_client ON projects(client_id);

CREATE TABLE tasks (
    id          INTEGER PRIMARY KEY,
    client_id   INTEGER NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL,
    UNIQUE(client_id, name),
    UNIQUE(client_id, id)
);
CREATE INDEX idx_tasks_client ON tasks(client_id);

CREATE TABLE entries (
    id          TEXT PRIMARY KEY,
    date        TEXT NOT NULL,
    client_id   INTEGER NOT NULL REFERENCES clients(id)  ON DELETE RESTRICT,
    project_id  INTEGER NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
    task_id     INTEGER NOT NULL,
    seconds     INTEGER NOT NULL DEFAULT 0,
    notes       TEXT NOT NULL DEFAULT '',
    started_at  TEXT,
    stopped_at  TEXT,
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL,
    FOREIGN KEY (client_id, task_id)
        REFERENCES tasks(client_id, id) ON DELETE RESTRICT
);
CREATE INDEX idx_entries_date         ON entries(date);
CREATE INDEX idx_entries_running      ON entries(stopped_at) WHERE stopped_at IS NULL;
CREATE INDEX idx_entries_client_date  ON entries(client_id, project_id, task_id, date);
CREATE UNIQUE INDEX idx_entries_only_one_running
    ON entries((1)) WHERE stopped_at IS NULL;

CREATE TABLE favorites (
    id          INTEGER PRIMARY KEY,
    client_id   INTEGER NOT NULL REFERENCES clients(id)  ON DELETE CASCADE,
    project_id  INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    task_id     INTEGER NOT NULL,
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL,
    UNIQUE(client_id, project_id, task_id),
    FOREIGN KEY (client_id, task_id)
        REFERENCES tasks(client_id, id) ON DELETE CASCADE
);

-- Sample data
BEGIN;
INSERT INTO clients (id, name, created_at, updated_at) VALUES
    (1, 'Farringdon Inc',              '$NOW_UTC', '$NOW_UTC'),
    (2, 'Rotherhithe Design',          '$NOW_UTC', '$NOW_UTC'),
    (3, 'Spitalfields Communications', '$NOW_UTC', '$NOW_UTC');

INSERT INTO projects (id, client_id, name, created_at, updated_at) VALUES
    (1, 1, 'New Company Website',      '$NOW_UTC', '$NOW_UTC'),
    (2, 2, 'Product Launch',           '$NOW_UTC', '$NOW_UTC'),
    (3, 3, 'Mobile App',               '$NOW_UTC', '$NOW_UTC'),
    (4, 3, 'Summer Marketing Campaign','$NOW_UTC', '$NOW_UTC');

-- Tasks are scoped per client; same name can repeat under different clients.
INSERT INTO tasks (id, client_id, name, created_at, updated_at) VALUES
    (1, 1, 'Meetings',           '$NOW_UTC', '$NOW_UTC'),
    (2, 2, 'Project Management', '$NOW_UTC', '$NOW_UTC'),
    (3, 3, 'Design',             '$NOW_UTC', '$NOW_UTC'),
    (4, 3, 'Project Management', '$NOW_UTC', '$NOW_UTC'),
    (5, 3, 'Meetings',           '$NOW_UTC', '$NOW_UTC');

-- 0:48 = 2880s, 1:15 = 4500s, 2:21 = 8460s, 0:42 = 2520s, 0:02 = 120s (running)
INSERT INTO entries
    (id, date, client_id, project_id, task_id, seconds, notes, started_at, stopped_at, created_at, updated_at)
VALUES
    ('e1', '$TODAY',     1, 1, 1, 2880, '', NULL, '$NOW_UTC', '$NOW_UTC', '$NOW_UTC'),
    ('e2', '$TODAY',     2, 2, 2, 4500, '', NULL, '$NOW_UTC', '$NOW_UTC', '$NOW_UTC'),
    ('e3', '$TODAY',     3, 3, 3, 8460, '', NULL, '$NOW_UTC', '$NOW_UTC', '$NOW_UTC'),
    ('e4', '$TODAY',     3, 3, 4, 2520, '', NULL, '$NOW_UTC', '$NOW_UTC', '$NOW_UTC'),
    ('e5', '$TODAY',     3, 4, 5, 120,  '', '$NOW_UTC', NULL, '$NOW_UTC', '$NOW_UTC'),
    ('e6', '$YESTERDAY', 1, 1, 1, 3600, 'standup', NULL, '$NOW_UTC', '$NOW_UTC', '$NOW_UTC'),
    ('e7', '$YESTERDAY', 3, 3, 3, 5400, '', NULL, '$NOW_UTC', '$NOW_UTC', '$NOW_UTC');

INSERT INTO favorites (client_id, project_id, task_id, created_at, updated_at) VALUES
    (1, 1, 1, '$NOW_UTC', '$NOW_UTC'),
    (3, 3, 3, '$NOW_UTC', '$NOW_UTC');

COMMIT;
SQL

echo "Seeded $DB with sample data for $TODAY (and one prior day)."
echo "Includes one running entry (e5) so the menu-bar pill animates on launch."
