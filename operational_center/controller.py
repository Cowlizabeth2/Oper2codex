"""Qt adapter. All durable state lives in SQLite, not in QML delegates."""
from __future__ import annotations

import copy
import json
import logging
import re
from pathlib import Path

from PySide6.QtCore import QObject, Property, Signal, Slot, QUrl, QMimeData
from PySide6.QtGui import QDesktopServices, QGuiApplication

from . import __version__
from .contacts import ContactsService, create_directory
from .domain import (new_master, new_block, uid, duplicate_master, validate_config,
                     field, parse_template, template_source, render, validate_values, apply_phrase, inline_tokens,
                     editor_template, editor_token, parse_editor_template)
from .files import DocumentService, ReferenceService, scan, atomic_copy
from .theme import theme, ThemeManager

log = logging.getLogger(__name__)


class Controller(QObject):
    stateChanged = Signal()
    notice = Signal(str)
    contentChanged = Signal(str, str, str, str)
    valueChanged = Signal(str, str, str, str)

    def __init__(self, store, data_dir, commit="development"):
        super().__init__()
        self.store = store
        self.data_dir = Path(data_dir)
        self.documents = DocumentService(store, data_dir)
        self.references = ReferenceService(data_dir)
        self.contacts = ContactsService(store)
        self.commit = commit
        self.themes = ThemeManager(store, self)
        self.block_clipboard = []
        self.active = next((e["id"] for e in store.events() if e["visible"] and not e["archived"]), "")
        self.selected_master = store.config("draft")[1]["masters"][0]["id"] if store.config("draft")[1]["masters"] else ""
        self.selected_block = ""
        self.undo_stack, self.redo_stack = [], []
        for event in store.events():
            if event["visible"] and not event["archived"]:
                self.documents.initialize(event["id"])

    def get_state(self):
        version, published = self.store.config()
        _, draft = self.store.config("draft")
        current_master = next((m for m in draft["masters"] if m["id"] == self.selected_master), None)
        selected = next((b for b in current_master["blocks"] if b["id"] == self.selected_block), None) if current_master else None
        event = self.store.event(self.active) if self.active else None
        if event:
            for block in event["snapshot"]["blocks"]:
                local = event["state"][block["id"]]
                block["runtime"] = local
                if block["type"] == "text":
                    segments = block["config"]["segments"]
                    block["fields"] = [s for s in segments if s["kind"] == "field"]
                    block["tokens"] = inline_tokens(segments)
                    block["preview"] = render(segments, local["values"])
                    block["validation"] = "\n".join(validate_values(segments, local["values"]))
                elif block["type"] == "documents":
                    block["files"] = self.documents.files(local)
                elif block["type"] == "reference":
                    block["files"], errors = scan(block["config"])
                    block["warning"] = "\n".join(e["name"] + ": " + e["error"] for e in errors)
                elif block["type"] == "contacts":
                    block["contacts"], block["warning"] = self.contacts.load(block["config"].get("path"), event["tag"], block["config"].get("tag_map"))
        name, tokens = theme(self.store)
        result = {"version": __version__, "commit": self.commit, "theme": name, "tokens": tokens,
                  "scale": self.store.pref("scale", 1.0), "uiScale": self.themes.uiScale,
                  "sidebarCollapsed": self.store.pref("sidebar_collapsed", False),
                  "published": published, "configVersion": version,
                  "draft": draft, "master": current_master, "selectedBlock": selected, "event": event,
                  "events": self.store.events(), "canUndo": bool(self.undo_stack), "canRedo": bool(self.redo_stack),
                  "logs": self.store.logs(), "dataDir": str(self.data_dir)}
        if selected and selected["type"] == "text":
            result["templateSource"], result["templateFields"] = editor_template(selected["config"]["segments"])
        return result

    state = Property("QVariantMap", get_state, notify=stateChanged)
    themeManager = Property(QObject, lambda self: self.themes, constant=True)

    def change_draft(self, mutation):
        _, before = self.store.config("draft")
        after = copy.deepcopy(before)
        mutation(after)
        self.store.save_draft(after)
        self.undo_stack.append(before)
        self.undo_stack = self.undo_stack[-100:]
        self.redo_stack.clear()

    def master(self, config):
        return next(m for m in config["masters"] if m["id"] == self.selected_master)

    def block(self, config, identity):
        return next(b for b in self.master(config)["blocks"] if b["id"] == identity)

    @Slot(str, str, result=bool)
    def command(self, action, payload="{}"):
        try:
            args = json.loads(payload)
            self._command(action, args)
            if action in {"create_event", "select_event", "hide_event", "archive_event", "copy_text", "copy_phone", "copy_files", "open_document", "repair_document", "preview"}:
                identity = args.get("id") if action in {"select_event", "hide_event", "archive_event"} else self.active
                messages = {"create_event":"Создана карточка происшествия", "select_event":"Открыта карточка", "hide_event":"Вкладка скрыта", "archive_event":"Происшествие архивировано", "copy_text":"Сообщение скопировано", "copy_phone":"Номер скопирован", "copy_files":"Файлы помещены в буфер", "open_document":"Открыта рабочая копия", "repair_document":"Рабочая копия восстановлена из оригинала", "preview":"Открыта безопасная копия справочного файла"}
                if identity:
                    self.store.record_action(identity, messages[action])
            if action not in {"phrase", "copy_text", "copy_phone", "copy_files", "open_folder", "open_parent", "open_document", "preview", "backup", "export", "copy_blocks"}:
                self.stateChanged.emit()
            return True
        except Exception as exc:
            log.exception("Операция %s не выполнена", action)
            with self.store.db:
                self.store.log("ERROR", f"{action}: {exc}")
            self.notice.emit(f"Не удалось выполнить действие: {exc}")
            return False

    def _command(self, action, a):
        if action == "create_event":
            event = self.store.create_event(a["id"])
            self.active = event["id"]
            self.documents.initialize(self.active)
        elif action == "select_event":
            self.store.visibility(a["id"], True, False)
            self.active = a["id"]
            self.documents.initialize(self.active)
        elif action in {"hide_event", "archive_event"}:
            self.store.visibility(a["id"], False, True if action == "archive_event" else None)
            if self.active == a["id"]:
                self.active = next((e["id"] for e in self.store.events() if e["visible"] and not e["archived"]), "")
        elif action == "select_master":
            self.selected_master, self.selected_block = a["id"], ""
        elif action == "select_block":
            self.selected_block = a["id"]
        elif action == "new_master":
            master = new_master()
            self.change_draft(lambda c: c["masters"].append(master))
            self.selected_master, self.selected_block = master["id"], ""
        elif action == "duplicate_master":
            _, config = self.store.config("draft")
            master = duplicate_master(self.master(config))
            self.change_draft(lambda c: c["masters"].append(master))
            self.selected_master, self.selected_block = master["id"], ""
        elif action == "delete_master":
            self.change_draft(lambda c: c["masters"].remove(self.master(c)))
            self.selected_master = next((m["id"] for m in self.store.config("draft")[1]["masters"]), "")
            self.selected_block = ""
        elif action == "save_master":
            def update(c):
                self.master(c).update(name=a["name"], tag=a["tag"], icon=a["icon"], color=a["color"])
            self.change_draft(update)
        elif action == "add_block":
            block = new_block(a["type"])
            def add(c):
                master = self.master(c)
                block.update(x=232 + (len(master["blocks"]) % 2) * 432, y=40 + (len(master["blocks"]) // 2) * 312)
                master["blocks"].append(block)
                master["links"].append(block["id"])
            self.change_draft(add)
            self.selected_block = block["id"]
        elif action == "duplicate_block":
            _, config = self.store.config("draft")
            block = copy.deepcopy(self.block(config, a["id"]))
            block.update(id=uid(), title=block["title"] + " — копия", x=block["x"] + 40, y=block["y"] + 40)
            def duplicate(c):
                self.master(c)["blocks"].append(block)
                self.master(c)["links"].append(block["id"])
            self.change_draft(duplicate)
            self.selected_block = block["id"]
        elif action == "delete_block":
            def remove(c):
                master = self.master(c)
                master["blocks"].remove(self.block(c, a["id"]))
                master["links"] = [i for i in master["links"] if i != a["id"]]
            self.change_draft(remove)
            self.selected_block = ""
        elif action == "geometry":
            def geometry(c):
                self.block(c, a["id"]).update(x=max(0, a["x"]), y=max(0, a["y"]), width=max(320, a["width"]), height=max(260, a["height"]))
            self.change_draft(geometry)
            self.selected_block = a["id"]
        elif action == "geometry_batch":
            def batch(c):
                for item in a["items"]:
                    self.block(c, item["id"]).update({key: item[key] for key in ("x", "y", "width", "height")})
            self.change_draft(batch)
            if a["items"]:
                self.selected_block = a["items"][0]["id"]
        elif action == "copy_blocks":
            _, config = self.store.config("draft")
            self.block_clipboard = copy.deepcopy([b for b in self.master(config)["blocks"] if b["id"] in a["ids"]])
        elif action in {"paste_blocks", "duplicate_blocks"}:
            _, config = self.store.config("draft")
            originals = self.block_clipboard if action == "paste_blocks" else [b for b in self.master(config)["blocks"] if b["id"] in a["ids"]]
            blocks = copy.deepcopy(originals)
            for block in blocks:
                block.update(id=uid(), x=block["x"] + 32, y=block["y"] + 32, title=block["title"] + " — копия")
            if blocks:
                def paste(c):
                    self.master(c)["blocks"].extend(blocks)
                    self.master(c)["links"].extend(b["id"] for b in blocks)
                self.change_draft(paste)
                self.selected_block = blocks[0]["id"]
        elif action == "delete_blocks":
            def delete(c):
                master = self.master(c)
                master["blocks"] = [b for b in master["blocks"] if b["id"] not in a["ids"]]
                master["links"] = [i for i in master["links"] if i not in a["ids"]]
            self.change_draft(delete)
            self.selected_block = ""
        elif action == "toggle_link":
            def toggle(c):
                master = self.master(c)
                self.block(c, a["id"])
                if a["id"] in master["links"]:
                    master["links"].remove(a["id"])
                else:
                    master["links"].append(a["id"])
            self.change_draft(toggle)
        elif action == "save_block":
            def save(c):
                self.block(c, a["id"]).update(title=a["title"], config=a["config"])
                if "accent" in a:
                    self.block(c, a["id"])["accent"] = a["accent"]
            self.change_draft(save)
        elif action == "block_accent":
            color = a["color"].strip()
            if color and not re.fullmatch(r"#[0-9a-fA-F]{6}", color):
                raise ValueError("Цвет должен иметь формат #RRGGBB")
            self.change_draft(lambda c: self.block(c, a["id"]).update(accent=color))
        elif action in {"undo", "redo"}:
            origin, destination = (self.undo_stack, self.redo_stack) if action == "undo" else (self.redo_stack, self.undo_stack)
            if origin:
                _, current = self.store.config("draft")
                self.store.save_draft(origin[-1])
                origin.pop()
                destination.append(current)
                master = next((m for m in self.store.config("draft")[1]["masters"] if m["id"] == self.selected_master), None)
                if not master:
                    self.selected_master = next((m["id"] for m in self.store.config("draft")[1]["masters"]), "")
                    self.selected_block = ""
        elif action == "publish":
            self.store.publish()
            self.notice.emit("Конфигурация опубликована. Уже созданные происшествия сохраняют прежние настройки.")
        elif action == "theme":
            if a["name"] not in {"dark", "light"}:
                raise ValueError("Неизвестная тема")
            self.store.set_pref("theme", a["name"])
            self.themes.reload()
        elif action == "ui_scale":
            if a["value"] not in [.85, 1.0, 1.1, 1.25, 1.5]:
                raise ValueError("Некорректный масштаб интерфейса")
            self.store.set_pref("ui_scale", a["value"])
            self.themes.reload()
        elif action == "sidebar":
            self.store.set_pref("sidebar_collapsed", bool(a["collapsed"]))
        elif action == "scale":
            if not isinstance(a["value"], (int, float)) or not .1 <= a["value"] <= 3:
                raise ValueError("Некорректный масштаб")
            self.store.set_pref("scale", a["value"])
        elif action == "copy_text":
            event, block, state = self.event_block(a["id"])
            segments = block["config"]["segments"]
            errors = validate_values(segments, state["values"])
            if errors:
                self.notice.emit("Проверьте сообщение перед отправкой:\n" + "\n".join(errors))
            QGuiApplication.clipboard().setText(render(segments, state["values"]))
        elif action == "copy_phone":
            QGuiApplication.clipboard().setText(a["phone"])
        elif action == "phrase":
            event, block, state = self.event_block(a["id"])
            f = next(s for s in block["config"]["segments"] if s.get("id") == a["field"])
            value = apply_phrase(state["values"].get(f["id"], ""), a["phrase"], f.get("phrase_mode", "replace"))
            self._set_value(a["id"], f["id"], value)
        elif action == "select_files":
            event, block, state = self.event_block(a["id"])
            state["selected"] = a["paths"]
            self.store.save_state(event["id"], event["state"])
        elif action == "copy_files":
            event, block, state = self.event_block(a["id"])
            allowed = {f["source"] for f in scan(block["config"])[0]}
            paths = state.get("selected", [])
            if not paths or not set(paths) <= allowed:
                raise ValueError("Выберите доступные файлы")
            mime = QMimeData()
            mime.setUrls([QUrl.fromLocalFile(p) for p in paths])
            # Qt's Windows clipboard integration exports these URLs as CF_HDROP.
            QGuiApplication.clipboard().setMimeData(mime)
            self.notice.emit("Файлы помещены в буфер. Вставка зависит от поддержки получателем.")
        elif action == "preview":
            event, block, state = self.event_block(a["id"])
            allowed = {f["source"] for f in scan(block["config"])[0]}
            if a["path"] not in allowed:
                raise ValueError("Файл не относится к блоку")
            self.open_path(self.references.preview(a["path"]))
        elif action == "open_document":
            _, block, state = self.event_block(a["id"])
            item = next(f for f in self.documents.files(state) if f.get("path") == a["path"])
            if item["status"] != "ready":
                raise ValueError(item.get("error", "Копия недоступна"))
            self.open_path(item["path"])
        elif action == "repair_document":
            event, block, state = self.event_block(a["id"])
            item = next(f for f in state["files"] if f.get("path") == a["path"])
            atomic_copy(item["source"], item["path"])
            item.update(status="ready")
            item.pop("error", None)
            self.store.save_state(event["id"], event["state"])
        elif action == "open_parent":
            self.open_path(str(Path(a["path"]).parent))
        elif action == "open_folder":
            self.open_path(a["path"])
        elif action == "refresh_contacts":
            event, block, _ = self.event_block(a["id"])
            self.contacts.load(block["config"].get("path"), event["tag"], block["config"].get("tag_map"), True)
        elif action == "create_contacts":
            path = create_directory(Path(a["folder"]) / "Контакты.xlsx")
            def attach(c):
                self.block(c, a["id"])["config"]["path"] = path
            self.change_draft(attach)
            self.notice.emit("Создан справочник: " + path)
        elif action == "backup":
            path = self.store.backup(self.data_dir / "backups" / f"manual-{uid()}.sqlite")
            self.notice.emit("Резервная копия создана: " + path)
        elif action == "restore":
            before = self.store.restore(a["path"])
            self.active = ""
            self.selected_master = next((m["id"] for m in self.store.config("draft")[1]["masters"]), "")
            self.selected_block = ""
            self.undo_stack.clear(); self.redo_stack.clear()
            self.themes.reload()
            self.notice.emit("База восстановлена. Предыдущая база сохранена: " + before)
        elif action == "export":
            _, config = self.store.config("draft")
            with Path(a["path"]).open("x", encoding="utf-8") as stream:
                json.dump(config, stream, ensure_ascii=False, indent=2)
        elif action == "import":
            config = json.loads(Path(a["path"]).read_text(encoding="utf-8"))
            validate_config(config)
            self.store.backup(self.data_dir / "backups" / f"before-import-{uid()}.sqlite")
            self.change_draft(lambda c: (c.clear(), c.update(config)))
            self.selected_master = next((m["id"] for m in config["masters"]), "")
            self.selected_block = ""
        elif action == "clear_previews":
            self.references.clear()
        else:
            raise ValueError("Неизвестное действие: " + action)

    def event_block(self, identity):
        event = self.store.event(self.active)
        block = next(b for b in event["snapshot"]["blocks"] if b["id"] == identity)
        return event, block, event["state"][identity]

    def open_path(self, path):
        if not Path(path).exists():
            raise FileNotFoundError("Путь не найден: " + path)
        if not QDesktopServices.openUrl(QUrl.fromLocalFile(str(Path(path).resolve()))):
            raise OSError("Система не смогла открыть файл или папку")

    def _set_value(self, block_id, field_id, value):
        event, block, state = self.event_block(block_id)
        if field_id not in {s.get("id") for s in block["config"]["segments"] if s["kind"] == "field"}:
            raise ValueError("Поле не найдено")
        state["values"][field_id] = value
        self.store.save_state(event["id"], event["state"])
        definition = next(s for s in block["config"]["segments"] if s.get("id") == field_id)
        self.store.record_action(event["id"], "Изменено поле «" + definition.get("label", "Поле") + "»", "field:" + block_id + ":" + field_id)
        self.valueChanged.emit(event["id"], block_id, field_id, value)
        segments = block["config"]["segments"]
        self.contentChanged.emit(event["id"], block_id, render(segments, state["values"]), "\n".join(validate_values(segments, state["values"])))

    @Slot(str, str, str)
    def setValue(self, block_id, field_id, value):
        try:
            self._set_value(block_id, field_id, value)
        except Exception as exc:
            log.exception("Не удалось сохранить поле")
            self.notice.emit("Значение не сохранено: " + str(exc))

    @Slot(str, str)
    def selectFiles(self, identity, paths_json):
        # Preserve the view's Shift anchor and keyboard focus while persisting.
        try:
            event, block, state = self.event_block(identity)
            allowed = {f["source"] for f in scan(block["config"])[0]}
            paths = json.loads(paths_json)
            if not isinstance(paths, list) or not set(paths) <= allowed:
                raise ValueError("Выбран недоступный файл")
            state["selected"] = paths
            self.store.save_state(event["id"], event["state"])
        except Exception as exc:
            log.exception("Выбор файлов не сохранён")
            self.notice.emit(str(exc))

    @Slot(str, int, int, str, str, result="QVariantMap")
    def insertField(self, source, start, end, fields_json, label):
        try:
            fields = json.loads(fields_json)
            # QML cursor positions are UTF-16 code units, Python indexes codepoints.
            raw = source.encode("utf-16-le")
            before, selected, after = (raw[:start * 2].decode("utf-16-le"), raw[start * 2:end * 2].decode("utf-16-le"), raw[end * 2:].decode("utf-16-le"))
            parse_editor_template(source, fields)
            markers = [f.get("_editor_token", "[["+f["id"]+"]]") for f in fields]
            selection_start, selection_end = len(before), len(before)+len(selected)
            overlaps = any((source.find(marker) < selection_end and source.find(marker)+len(marker) > selection_start) or (selection_start == selection_end and source.find(marker) < selection_start < source.find(marker)+len(marker)) for marker in markers if marker in source)
            if overlaps:
                raise ValueError("Выделение не должно пересекать существующие поля")
            new = field(label or "Поле", default=selected)
            new["_editor_token"] = editor_token(new, len(fields)+1, source)
            source = before + new["_editor_token"] + after
            fields.append(new)
            parse_editor_template(source, fields)
            return {"source": source, "fields": fields}
        except Exception as exc:
            self.notice.emit("Поле не добавлено: " + str(exc))
            return {}

    @Slot(str, str, str, str, result=bool)
    @Slot(str, str, str, str, str, result=bool)
    def saveTemplate(self, identity, title, source, fields_json, accent=None):
        try:
            segments = parse_editor_template(source, json.loads(fields_json))
            payload = {"id": identity, "title": title, "config": {"segments": segments}}
            if accent is not None:
                payload["accent"] = accent
            return self.command("save_block", json.dumps(payload))
        except Exception as exc:
            self.notice.emit("Шаблон не сохранён: " + str(exc))
            return False

    @Slot(str, result=str)
    def localPath(self, url):
        return QUrl(url).toLocalFile()

    @Slot(str, result="QVariantList")
    def eventHistory(self, identity):
        return list(reversed(self.store.event(identity)["state"].get("_history", [])))
