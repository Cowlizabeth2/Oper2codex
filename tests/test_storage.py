import json
import sqlite3

import pytest

from operational_center.storage import Store


def test_independent_incidents_and_history(store, configured):
    master, block, a, b = configured
    first, second = store.create_event(master["id"]), store.create_event(master["id"])
    fire_id = store.config()[1]["masters"][1]["id"]
    third = store.create_event(fire_id)
    assert len({first["id"], second["id"], third["id"]}) == 3
    assert [e["number"] for e in (first, second, third)] == [1, 2, 3]
    first["state"][block["id"]]["values"][a["id"]] = "Первое"
    store.save_state(first["id"], first["state"])
    assert store.event(second["id"])["state"][block["id"]]["values"][a["id"]] == ""
    store.visibility(first["id"], False)
    assert not store.event(first["id"])["visible"]
    store.visibility(first["id"], True)
    assert store.event(first["id"])["state"][block["id"]]["values"][a["id"]] == "Первое"
    store.visibility(third["id"], False, True)
    assert store.event(third["id"])["archived"]


def test_snapshots_and_published_draft_separation(store, configured):
    master, block, _, _ = configured
    old = store.create_event(master["id"])
    _, config = store.config("draft")
    config["masters"][0]["blocks"][0]["title"] = "Новая версия"
    store.save_draft(config)
    intermediate = store.create_event(master["id"])
    assert intermediate["snapshot"] == old["snapshot"]
    store.publish()
    new = store.create_event(master["id"])
    assert new["snapshot"]["blocks"][0]["title"] == "Новая версия"
    assert store.event(old["id"])["snapshot"]["blocks"][0]["title"] == block["title"]
    assert new["config_version"] > old["config_version"]


def test_restart_restores_visible_sessions_and_preferences(tmp_path, configured, store):
    master, block, a, _ = configured
    event = store.create_event(master["id"])
    event["state"][block["id"]]["values"][a["id"]] = "Сохранено"
    store.save_state(event["id"], event["state"])
    store.set_pref("theme", "light")
    other = Store(store.path)
    try:
        assert other.pref("theme") == "light"
        assert other.event(event["id"])["visible"]
        assert other.event(event["id"])["state"] == event["state"]
    finally:
        other.close()


def test_backup_consistency_and_restore(store, configured, tmp_path):
    master, _, _, _ = configured
    first = store.create_event(master["id"])
    backup = tmp_path / "backup.sqlite"
    store.backup(backup)
    store.create_event(master["id"])
    previous = store.restore(backup)
    assert len(store.events()) == 1
    assert store.events()[0]["id"] == first["id"]
    with sqlite3.connect(previous) as db:
        assert db.execute("SELECT count(*) FROM events").fetchone()[0] == 2
    with pytest.raises(FileExistsError):
        store.backup(backup)


def test_invalid_backup_leaves_current_database(store, configured, tmp_path):
    master, _, _, _ = configured
    store.create_event(master["id"])
    invalid = tmp_path / "broken.sqlite"
    invalid.write_text("not sqlite")
    with pytest.raises(sqlite3.DatabaseError):
        store.restore(invalid)
    assert len(store.events()) == 1


def test_schema_newer_than_app_never_modified(tmp_path):
    path = tmp_path / "future.sqlite"
    with sqlite3.connect(path) as db:
        db.execute("PRAGMA user_version=999")
    with pytest.raises(ValueError):
        Store(path)
    with sqlite3.connect(path) as db:
        assert db.execute("PRAGMA user_version").fetchone()[0] == 999


def test_corrupt_preference_uses_fallback(store):
    with store.db:
        store.db.execute("INSERT INTO preferences VALUES('theme','broken-json')")
    from operational_center.theme import theme
    assert theme(store)[0] == "dark"


def test_committed_event_survives_abrupt_process_exit(tmp_path):
    import os
    import subprocess
    import sys
    path = tmp_path / "crash-test.sqlite"
    program = """
import os, sys
from operational_center.storage import Store
s = Store(sys.argv[1])
m = s.config()[1]['masters'][0]['id']
event = s.create_event(m)
s.set_pref('crash-test', 'committed')
os._exit(0)
"""
    subprocess.run([sys.executable, "-c", program, str(path)], check=True, timeout=15)
    restarted = Store(path)
    try:
        assert len(restarted.events()) == 1
        assert restarted.events()[0]["visible"]
        assert restarted.pref("crash-test") == "committed"
    finally:
        restarted.close()
