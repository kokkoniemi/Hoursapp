import Foundation
import GRDB

enum Migrations {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
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
            """)
        }
    }
}
