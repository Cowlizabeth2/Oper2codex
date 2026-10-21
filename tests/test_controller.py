import copy
import ctypes
import json
import sys
from pathlib import Path

import pytest
from PySide6.QtCore import QUrl

from operational_center.controller import Controller
from operational_center.domain import new_block


def run(controller, action, **args):
    assert controller.command(action, json.dumps(args)), (action, args)


def test_builder_multiple_instances_layout_links_undo_restart(app, store, tmp_path):
    c = Controller(store, tmp_path)
    for kind in ["text", "text", "contacts", "contacts", "reference", "reference"]:
        run(c, "add_block", type=kind)
    blocks = c.state["master"]["blocks"]
    assert len({b["id"] for b in blocks}) == 6
    identity = blocks[0]["id"]
    run(c, "geometry", id=identity, x=123, y=456, width=540, height=390)
    run(c, "toggle_link", id=blocks[1]["id"])
    assert len(c.state["master"]["links"]) == 5
    run(c, "undo")
    assert len(c.state["master"]["links"]) == 6
    run(c, "redo")
    assert len(c.state["master"]["links"]) == 5
    run(c, "publish")
    run(c, "create_event", id=c.selected_master)
    assert len(c.state["event"]["snapshot"]["blocks"]) == 5
    restarted = Controller(store, tmp_path)
    restored = restarted.state["master"]["blocks"][0]
    assert (restored["x"], restored["y"], restored["width"], restored["height"]) == (123,456,540,390)
    assert restarted.active == c.active


def test_template_selection_unicode_phrase_and_clipboard(app, store, configured, tmp_path):
    master, block, a, b = configured
    c = Controller(store, tmp_path)
    run(c, "create_event", id=master["id"])
    c.setValue(block["id"], a["id"], "ТМП20")
    c.setValue(block["id"], b["id"], "42")
    run(c, "copy_text", id=block["id"])
    assert app.clipboard().text() == "Перевозчик ТМП20, автобус 42.\nКонец сообщения."
    run(c, "phrase", id=block["id"], field=a["id"], phrase="Стартранс")
    assert c.state["event"]["state"][block["id"]]["values"][a["id"]] == "Стартранс"
    inserted = c.insertField("🚒 До после", 3, 5, "[]", "Выделение")
    assert inserted["fields"][0]["default"] == "До"
    assert inserted["source"].startswith("🚒 [[")


def test_reference_multiselect_persists_file_objects(app, store, tmp_path):
    one, two = tmp_path / "один.txt", tmp_path / "два.txt"
    one.write_text("one"); two.write_text("two")
    c = Controller(store, tmp_path / "data")
    run(c, "add_block", type="reference")
    block = c.state["selectedBlock"]
    config = dict(block["config"], sources=[str(one), str(two)])
    run(c, "save_block", id=block["id"], title="Файлы", config=config)
    run(c, "publish"); run(c, "create_event", id=c.selected_master)
    c.selectFiles(block["id"], json.dumps([str(one), str(two)]))
    run(c, "copy_files", id=block["id"])
    assert [u.toLocalFile() for u in app.clipboard().mimeData().urls()] == [str(one), str(two)]
    assert store.event(c.active)["state"][block["id"]]["selected"] == [str(one), str(two)]


@pytest.mark.skipif(sys.platform != "win32", reason="Native CF_HDROP requires Windows")
def test_windows_native_clipboard_cf_hdrop(app, store, tmp_path):
    # Runs on Windows CI with the native Windows platform plugin, not offscreen.
    from PySide6.QtCore import QMimeData
    source = tmp_path / "передача.txt"
    source.write_text("clipboard test")
    mime = QMimeData()
    mime.setUrls([QUrl.fromLocalFile(str(source))])
    app.clipboard().setMimeData(mime)
    app.processEvents()
    user32 = ctypes.windll.user32
    assert user32.IsClipboardFormatAvailable(15), "Qt must export URL data as CF_HDROP"
    user32.GetClipboardData.restype = ctypes.c_void_p
    shell32 = ctypes.windll.shell32
    shell32.DragQueryFileW.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_wchar_p, ctypes.c_uint]
    assert user32.OpenClipboard(None)
    try:
        handle = user32.GetClipboardData(15)
        buffer = ctypes.create_unicode_buffer(32768)
        shell32.DragQueryFileW(handle, 0, buffer, len(buffer))
        assert Path(buffer.value) == source
    finally:
        user32.CloseClipboard()
        app.clipboard().clear()


def test_theme_persistence_fallback_and_export_import(app, store, tmp_path):
    c = Controller(store, tmp_path)
    run(c, "theme", name="light")
    assert c.state["tokens"]["background"] == "#F2F5FA"
    run(c, "scale", value=1.25)
    assert Controller(store, tmp_path).state["scale"] == 1.25
    export = tmp_path / "config.json"
    run(c, "export", path=str(export))
    before = store.config("draft")[1]
    run(c, "new_master")
    run(c, "import", path=str(export))
    assert store.config("draft")[1] == before
    store.set_pref("theme", ["invalid"])
    assert c.state["theme"] == "dark"


def test_invalid_action_reports_error_without_false_success(app, store, tmp_path):
    c = Controller(store, tmp_path)
    messages = []
    c.notice.connect(messages.append)
    assert not c.command("not_an_action", "{}")
    assert messages and store.logs()[0]["level"] == "ERROR"
