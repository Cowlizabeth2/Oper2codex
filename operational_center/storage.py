"""SQLite persistence, transactions and consistent backups."""
from __future__ import annotations

import json
import sqlite3
from contextlib import closing
from pathlib import Path

from .domain import now, uid, validate_config, new_master


def encode(value):
    return json.dumps(value, ensure_ascii=False)


class Store:
    SCHEMA = 1

    def __init__(self, path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(self.path)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA foreign_keys=ON")
        self.db.execute("PRAGMA busy_timeout=5000")
        version = self.db.execute("PRAGMA user_version").fetchone()[0]
        if version > self.SCHEMA:
            self.db.close()
            raise ValueError("База создана более новой версией программы")
        if version < self.SCHEMA:
            if self.path.stat().st_size:
                self.backup(self.path.parent / "backups" / f"before-migration-{uid()}.sqlite")
            self._migrate()
        self.db.execute("PRAGMA journal_mode=WAL")
        with self.db:
            if self.db.execute("SELECT 1 FROM config WHERE name='published'").fetchone() is None:
                config = {"format": 1, "masters": [new_master("ДТП", "dtp"), new_master("Пожар", "fire"), new_master("Столица", "stolica")]}
                for name in ("draft", "published"):
                    self.db.execute("INSERT INTO config VALUES(?,?,?)", (name, 1, encode(config)))

    def _migrate(self):
        self.db.executescript("""
        BEGIN IMMEDIATE;
        CREATE TABLE config(name TEXT PRIMARY KEY, version INTEGER NOT NULL, data TEXT NOT NULL);
        CREATE TABLE events(id TEXT PRIMARY KEY, number INTEGER UNIQUE NOT NULL, created TEXT NOT NULL,
          master_id TEXT NOT NULL, name TEXT NOT NULL, tag TEXT NOT NULL, config_version INTEGER NOT NULL,
          snapshot TEXT NOT NULL, state TEXT NOT NULL, visible INTEGER NOT NULL DEFAULT 1,
          archived INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE preferences(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE contacts_cache(path TEXT PRIMARY KEY, stamp TEXT NOT NULL, data TEXT NOT NULL);
        CREATE TABLE journal(id INTEGER PRIMARY KEY AUTOINCREMENT, created TEXT NOT NULL,
          level TEXT NOT NULL, message TEXT NOT NULL);
        PRAGMA user_version=1;
        COMMIT;
        """)

    def config(self, name="published"):
        row = self.db.execute("SELECT version,data FROM config WHERE name=?", (name,)).fetchone()
        return row["version"], json.loads(row["data"])

    def save_draft(self, config):
        validate_config(config)
        with self.db:
            self.db.execute("UPDATE config SET data=? WHERE name='draft'", (encode(config),))

    def publish(self):
        _, config = self.config("draft")
        validate_config(config)
        self.backup(self.path.parent / "backups" / f"before-publish-{uid()}.sqlite")
        with self.db:
            self.db.execute("UPDATE config SET version=version+1,data=? WHERE name='published'", (encode(config),))
            self.log("INFO", "Опубликована конфигурация конструктора")

    def create_event(self, master_id):
        version, config = self.config()
        master = next(m for m in config["masters"] if m["id"] == master_id)
        snapshot = json.loads(encode(master))
        snapshot["blocks"] = [b for b in snapshot["blocks"] if b["id"] in master["links"]]
        state = {b["id"]: {"values": {s["id"]: s.get("default", "") for s in b["config"].get("segments", []) if s["kind"] == "field"}, "files": [], "initialized": False, "selected": []} for b in snapshot["blocks"]}
        identity = uid()
        with self.db:
            # The transaction reserves the next number even across concurrent connections.
            self.db.execute("BEGIN IMMEDIATE")
            number = self.db.execute("SELECT COALESCE(MAX(number),0)+1 FROM events").fetchone()[0]
            self.db.execute("INSERT INTO events VALUES(?,?,?,?,?,?,?,?,?,1,0)",
                            (identity, number, now(), master_id, master["name"], master["tag"], version, encode(snapshot), encode(state)))
            self.log("INFO", f"Создано происшествие №{number}")
        return self.event(identity)

    @staticmethod
    def _event(row):
        if row is None:
            raise ValueError("Происшествие не найдено")
        result = dict(row)
        for key in ("snapshot", "state"):
            result[key] = json.loads(result[key])
        return result

    def event(self, identity):
        return self._event(self.db.execute("SELECT * FROM events WHERE id=?", (identity,)).fetchone())

    def events(self):
        rows = self.db.execute("SELECT id,number,created,name,visible,archived FROM events ORDER BY number DESC").fetchall()
        return [dict(r) for r in rows]

    def save_state(self, identity, state):
        with self.db:
            self.db.execute("UPDATE events SET state=? WHERE id=?", (encode(state), identity))

    def visibility(self, identity, visible=True, archived=None):
        with self.db:
            if archived is not None:
                self.db.execute("UPDATE events SET archived=? WHERE id=?", (int(archived), identity))
            self.db.execute("UPDATE events SET visible=? WHERE id=?", (int(visible), identity))

    def pref(self, key, default=None):
        row = self.db.execute("SELECT value FROM preferences WHERE key=?", (key,)).fetchone()
        if not row:
            return default
        try:
            return json.loads(row[0])
        except (ValueError, TypeError):
            return default

    def set_pref(self, key, value):
        with self.db:
            self.db.execute("INSERT OR REPLACE INTO preferences VALUES(?,?)", (key, encode(value)))

    def log(self, level, message):
        self.db.execute("INSERT INTO journal(created,level,message) VALUES(?,?,?)", (now(), level, message))

    def logs(self):
        return [dict(r) for r in self.db.execute("SELECT * FROM journal ORDER BY id DESC LIMIT 200")]

    def backup(self, destination):
        target = Path(destination)
        if target.resolve() == self.path.resolve():
            raise ValueError("Нельзя записать резервную копию поверх рабочей базы")
        target.parent.mkdir(parents=True, exist_ok=True)
        # Exclusive creation prevents replacing an existing backup.
        with target.open("xb"):
            pass
        try:
            with closing(sqlite3.connect(target)) as db:
                self.db.backup(db)
        except Exception:
            target.unlink(missing_ok=True)
            raise
        return str(target)

    def restore(self, source):
        candidate = Path(source)
        if not candidate.is_file() or candidate.resolve() == self.path.resolve():
            raise ValueError("Выберите существующую резервную копию")
        # Read-only validation before touching current data.
        uri = candidate.resolve().as_uri() + "?mode=ro"
        with closing(sqlite3.connect(uri, uri=True)) as db:
            if db.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
                raise ValueError("Резервная копия повреждена")
            if db.execute("PRAGMA user_version").fetchone()[0] != self.SCHEMA:
                raise ValueError("Неподдерживаемая версия резервной копии")
            validate_config(json.loads(db.execute("SELECT data FROM config WHERE name='published'").fetchone()[0]))
            validate_config(json.loads(db.execute("SELECT data FROM config WHERE name='draft'").fetchone()[0]))
            for row in db.execute("SELECT snapshot,state FROM events"):
                json.loads(row[0]); json.loads(row[1])
        before = self.backup(self.path.parent / "backups" / f"before-restore-{uid()}.sqlite")
        with closing(sqlite3.connect(uri, uri=True)) as source_db:
            source_db.backup(self.db)
        return before

    def close(self):
        self.db.close()
