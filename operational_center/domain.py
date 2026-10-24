"""Serializable domain objects; no Qt or filesystem side effects."""
from __future__ import annotations

import copy
import re
import uuid
from datetime import datetime, timezone

BLOCK_TYPES = {"text", "static_text", "documents", "contacts", "reference"}
LABELS = {"text": "Текстовое сообщение", "documents": "Рабочие документы",
          "contacts": "Контакты", "reference": "Справочные файлы", "static_text": "Свободный текст"}


def uid():
    return str(uuid.uuid4())


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def normalize_tag(value):
    return " ".join(str(value).split()).casefold()


def new_master(name="Новое происшествие", tag=None):
    identity = uid()
    return {"id": identity, "name": name, "tag": tag or f"event_{identity[:8]}",
            "icon": "!", "color": "#8AB4FF", "links": [], "blocks": []}


def new_block(kind):
    if kind not in BLOCK_TYPES:
        raise ValueError("Неизвестный тип блока")
    config = {
        "static_text": {"text": "Информация для сотрудника", "format": "plain", "copy_enabled": True, "font_size": 13, "alignment": "left"},
        "text": {"segments": [{"kind": "text", "text": "Введите текст сообщения. Выделите фрагмент и нажмите «Добавить поле»."}]},
        "contacts": {"path": "", "tag_map": {}},
        "documents": {"sources": [], "output": "", "recursive": False, "extensions": []},
        "reference": {"sources": [], "recursive": False, "extensions": []},
    }[kind]
    return {"id": uid(), "type": kind, "title": LABELS[kind], "x": 36, "y": 36,
            "width": 400, "height": 220 if kind == "static_text" else 280, "config": config}


def field(label="Поле", **options):
    return {"kind": "field", "id": uid(), "label": label, "placeholder": "",
            "type": "text", "required": False, "multiline": False,
            "default": "", "phrases": [], "phrase_mode": "replace", **options}


def template_source(segments):
    return "".join(s["text"] if s["kind"] == "text" else "[[" + s["id"] + "]]" for s in segments)


def parse_template(source, fields):
    """Markers exist only in the builder; runtime output never contains them."""
    known = {f["id"]: f for f in fields}
    segments, position, used = [], 0, set()
    for match in re.finditer(r"\[\[([0-9a-f-]{36})\]\]", source):
        identity = match.group(1)
        if identity not in known or identity in used:
            raise ValueError("Неизвестное или повторно использованное поле шаблона")
        if match.start() > position:
            segments.append({"kind": "text", "text": source[position:match.start()]})
        segments.append(copy.deepcopy(known[identity]))
        used.add(identity)
        position = match.end()
    if source[position:]:
        segments.append({"kind": "text", "text": source[position:]})
    return segments


def editor_token(definition, number, occupied=""):
    label = " ".join(definition.get("label", "Поле").split())[:32] or "Поле"
    token = f"[{number} · {label}]"
    while token in occupied:
        number += 1
        token = f"[{number} · {label}]"
    return token


def editor_template(segments):
    """Readable editor markers are ephemeral; UUIDs remain the storage keys."""
    fields = []
    occupied = "".join(s.get("text", "") for s in segments if s["kind"] == "text")
    parts = []
    for segment in segments:
        if segment["kind"] == "text":
            parts.append(segment["text"])
        else:
            definition = copy.deepcopy(segment)
            token = editor_token(definition, len(fields)+1, occupied)
            occupied += token
            definition["_editor_token"] = token
            fields.append(definition)
            parts.append(token)
    return "".join(parts), fields


def parse_editor_template(source, fields):
    clean = []
    for definition in fields:
        definition = copy.deepcopy(definition)
        token = definition.pop("_editor_token", None)
        if token:
            source = source.replace(token, "[["+definition["id"]+"]]")
        clean.append(definition)
    return parse_template(source, clean)


def render(segments, values):
    return "".join(s["text"] if s["kind"] == "text" else str(values.get(s["id"], s.get("default", ""))) for s in segments)


def validate_values(segments, values):
    errors = []
    for s in segments:
        if s["kind"] != "field":
            continue
        value = str(values.get(s["id"], s.get("default", "")))
        label = s.get("label") or s["id"]
        if s.get("required") and not value.strip():
            errors.append(f"{label}: обязательное поле")
        elif value and s.get("type") == "number":
            try:
                float(value.replace(",", "."))
            except ValueError:
                errors.append(f"{label}: введите число")
        elif value and s.get("type") == "date":
            try:
                datetime.strptime(value, "%Y-%m-%d")
            except ValueError:
                errors.append(f"{label}: дата в формате ГГГГ-ММ-ДД")
    return errors


def apply_phrase(current, phrase, mode):
    return f"{current.rstrip()} {phrase}".strip() if mode == "append" else phrase


def inline_tokens(segments):
    """Presentation-only tokens. The original segments remain authoritative.

    Splitting whitespace for wrapping never changes copy output or field UUIDs.
    An explicit line-break token distinguishes a newline from automatic wrap.
    """
    result, line_start = [], True
    for segment in segments:
        if segment["kind"] == "field":
            result.append({**segment, "token": "field"})
            line_start = False
        else:
            for value in re.findall(r"\r\n|\r|\n|[^\S\r\n]+|[^\s]+", segment["text"]):
                if value in {"\r\n", "\r", "\n"}:
                    result.append({"token": "break", "blank": line_start, "text": value})
                    line_start = True
                else:
                    result.append({"token": "static", "text": value})
                    line_start = False
    return result


def validate_config(config):
    if not isinstance(config, dict) or config.get("format") != 1 or not isinstance(config.get("masters"), list):
        raise ValueError("Неподдерживаемый формат конфигурации")
    identities, tags = set(), set()
    for master in config["masters"]:
        identity = master["id"]
        uuid.UUID(identity)
        if identity in identities or not master["name"].strip() or not master["tag"].strip():
            raise ValueError("Некорректный мастер-блок")
        if not re.fullmatch(r"#[0-9a-fA-F]{6}", master.get("color", "")):
            raise ValueError("Цвет мастера должен иметь формат #RRGGBB")
        identities.add(identity)
        tag = normalize_tag(master["tag"])
        if tag in tags:
            raise ValueError("Системные теги мастер-блоков должны быть уникальны")
        tags.add(tag)
        for key in ("aliases", "tags"):
            if not isinstance(master.get(key, []), list) or not all(isinstance(t, str) for t in master.get(key, [])):
                raise ValueError("Алиасы и поисковые теги должны быть списками строк")
        if not all(isinstance(master.get(k, ""), str) for k in ("category", "km_code")):
            raise ValueError("Некорректные поисковые реквизиты мастера")
        blocks = set()
        for block in master["blocks"]:
            uuid.UUID(block["id"])
            if not isinstance(block.get("title"), str) or not block["title"].strip():
                raise ValueError("Введите название блока")
            if block.get("accent") and not re.fullmatch(r"#[0-9a-fA-F]{6}", block["accent"]):
                raise ValueError("Некорректный цвет блока")
            if block["id"] in identities or block["type"] not in BLOCK_TYPES:
                raise ValueError("Повторный ID или неизвестный тип блока")
            identities.add(block["id"])
            blocks.add(block["id"])
            for axis in ("x", "y", "width", "height"):
                value = block[axis]
                if not isinstance(value, (int, float)) or not 0 <= value <= 20000:
                    raise ValueError("Некорректная геометрия блока")
            min_width, min_height = (240, 180) if block["type"] == "static_text" else (320, 260)
            if block["width"] < min_width or block["height"] < min_height:
                raise ValueError(f"Блок меньше минимального размера {min_width}×{min_height}")
            cfg = block["config"]
            if block["type"] == "text":
                fields = set()
                for segment in cfg["segments"]:
                    if segment["kind"] == "field":
                        uuid.UUID(segment["id"])
                        if segment["id"] in fields or segment.get("type", "text") not in {"text", "number", "date"}:
                            raise ValueError("Некорректное поле")
                        fields.add(segment["id"])
                        if segment.get("phrase_mode", "replace") not in {"replace", "append"}:
                            raise ValueError("Некорректный режим готовых фраз")
                        if not isinstance(segment.get("phrases", []), list):
                            raise ValueError("Фразы должны быть списком")
                    elif segment["kind"] != "text" or not isinstance(segment["text"], str):
                        raise ValueError("Некорректный сегмент шаблона")
            elif block["type"] == "static_text":
                if (not isinstance(cfg.get("text"), str) or cfg.get("format", "plain") not in {"plain", "markdown"}
                        or not isinstance(cfg.get("copy_enabled", True), bool)
                        or cfg.get("alignment", "left") not in {"left", "center", "right"}
                        or type(cfg.get("font_size", 13)) is not int or not 10 <= cfg.get("font_size", 13) <= 32
                        or any(k in cfg for k in ("segments", "fields", "phrases"))):
                    raise ValueError("Некорректный блок свободного текста")
            elif block["type"] in {"documents", "reference"}:
                if not isinstance(cfg["sources"], list) or not all(isinstance(p, str) for p in cfg["sources"]):
                    raise ValueError("Источники должны быть списком путей")
                if not isinstance(cfg.get("extensions", []), list):
                    raise ValueError("Фильтры расширений должны быть списком")
            elif not isinstance(cfg.get("path", ""), str) or not isinstance(cfg.get("tag_map", {}), dict):
                raise ValueError("Некорректный справочник контактов")
        if len(master["links"]) != len(set(master["links"])) or not set(master["links"]) <= blocks:
            raise ValueError("Связь указывает на отсутствующий блок")
    catalogs = config.get("catalogs", [])
    if not isinstance(catalogs, list):
        raise ValueError("Каталоги должны быть списком")
    masters = {m["id"] for m in config["masters"]}
    for catalog in catalogs:
        uuid.UUID(catalog["id"])
        members = catalog.get("members", [])
        if (catalog["id"] in identities or catalog.get("type") != "master_catalog"
                or not isinstance(catalog.get("name"), str) or not catalog["name"].strip()
                or not isinstance(catalog.get("icon", ""), str)
                or not re.fullmatch(r"#[0-9a-fA-F]{6}", catalog.get("color", ""))
                or catalog.get("opening", "compact") not in {"compact", "wide"}
                or not isinstance(members, list) or len(members) != len(set(members))
                or not set(members) <= masters):
            raise ValueError("Некорректный каталог или ссылки на мастер-блоки")
        identities.add(catalog["id"])
    return config


def duplicate_master(master):
    result = copy.deepcopy(master)
    result["id"] = uid()
    result["name"] += " — копия"
    result["tag"] += "_" + result["id"][:6]
    remap = {b["id"]: uid() for b in result["blocks"]}
    for block in result["blocks"]:
        block["id"] = remap[block["id"]]
    result["links"] = [remap[identity] for identity in result["links"]]
    return result
