"""Copy-once documents and protected reference previews."""
from __future__ import annotations

import logging
import os
import shutil
import tempfile
from pathlib import Path

from .domain import uid

log = logging.getLogger(__name__)


def contains(parent, child):
    return child == parent or parent in child.parents


def scan(config):
    """Yield files with stable source-relative names, rejecting symlink escapes."""
    found, errors, seen = [], [], set()
    extensions = {str(e).lower().lstrip("*.") for e in config.get("extensions", [])}
    for index, raw in enumerate(config.get("sources", [])):
        source = Path(raw).expanduser().resolve()
        if not source.exists():
            errors.append({"name": str(source), "error": "Источник не найден"})
            continue
        try:
            candidates = [source] if source.is_file() else sorted(source.rglob("*") if config.get("recursive") else source.iterdir())
            for candidate in candidates:
                if not candidate.is_file():
                    continue
                real = candidate.resolve()
                if source.is_dir() and not contains(source, real):
                    raise ValueError("Ссылка выходит за пределы исходной папки")
                if real in seen or (extensions and candidate.suffix.lower().lstrip(".") not in extensions):
                    continue
                seen.add(real)
                relative = candidate.name if source.is_file() else str(candidate.relative_to(source))
                found.append({"source": str(real), "relative": str(Path(f"{index + 1}_{source.name}") / relative) if source.is_dir() else str(Path(f"{index + 1}") / relative), "name": candidate.name})
        except (OSError, ValueError) as exc:
            errors.append({"name": str(source), "error": str(exc)})
    return found, errors


def atomic_copy(source, destination):
    """Write to a same-directory temporary file, then publish without overwrite."""
    source, destination = Path(source), Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if shutil.disk_usage(destination.parent).free < source.stat().st_size + 1024 * 1024:
        raise OSError("Недостаточно свободного места")
    temp = destination.parent / (".copy-" + uid())
    try:
        with source.open("rb") as src, temp.open("xb") as dst:
            shutil.copyfileobj(src, dst)
            dst.flush()
            os.fsync(dst.fileno())
        # Windows rename refuses an existing destination and works on NTFS and
        # exFAT. POSIX rename overwrites, so publish with a hard link there.
        if os.name == "nt":
            os.rename(temp, destination)
        else:
            os.link(temp, destination)
    finally:
        temp.unlink(missing_ok=True)


class DocumentService:
    def __init__(self, store, data_dir):
        self.store = store
        self.data_dir = Path(data_dir)

    def initialize(self, identity):
        event = self.store.event(identity)
        for block in event["snapshot"]["blocks"]:
            if block["type"] != "documents":
                continue
            state = event["state"][block["id"]]
            if state["initialized"]:
                continue
            config = block["config"]
            output = Path(config.get("output") or self.data_dir / "documents").expanduser().resolve()
            folder = output / identity / block["id"]
            # Persist the intended manifest BEFORE copying: an interrupted run must
            # never silently replace an edited or missing event document.
            files, errors = scan(config)
            for raw in config.get("sources", []):
                source = Path(raw).expanduser().resolve()
                if source.is_dir() and contains(source, output):
                    files = []
                    errors.append({"name": str(output), "error": "Папка вывода находится внутри источника"})
                    break
            state.update(initialized=True, folder=str(folder), files=[{**f, "path": str(folder / f["relative"]), "status": "pending"} for f in files] + [{**e, "status": "error"} for e in errors])
            self.store.save_state(identity, event["state"])
            for entry in state["files"]:
                if entry["status"] != "pending":
                    log.warning("Ошибка подготовки документа: %s", entry.get("error"))
                    continue
                try:
                    atomic_copy(entry["source"], entry["path"])
                    entry["status"] = "ready"
                except (OSError, ValueError) as exc:
                    log.exception("Не удалось скопировать %s", entry["source"])
                    entry.update(status="error", error=str(exc))
                self.store.save_state(identity, event["state"])
        return self.store.event(identity)

    def files(self, block_state):
        result = []
        for entry in block_state["files"]:
            item = dict(entry)
            if entry.get("status") == "pending":
                item.update(status="error", error="Копирование было прервано. Проверьте рабочую папку; автоматического повтора нет.")
            elif entry.get("status") == "ready" and not Path(entry["path"]).is_file():
                item.update(status="missing", error="Рабочая копия отсутствует. Она не будет создана повторно без вашего решения.")
            result.append(item)
        return result


class ReferenceService:
    def __init__(self, data_dir):
        # Retain previews through the process lifetime and beyond: external Office
        # apps may keep files open. Cleanup is an explicit user action.
        self.folder = Path(data_dir) / "previews"

    def preview(self, source):
        source = Path(source)
        folder = self.folder / uid()
        destination = folder / source.name
        atomic_copy(source, destination)
        return str(destination)

    def clear(self):
        if self.folder.exists():
            shutil.rmtree(self.folder)
