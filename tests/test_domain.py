import copy
import json

import pytest

from operational_center.domain import (field, render, parse_template, template_source,
    apply_phrase, validate_values, validate_config, new_block, duplicate_master)


def test_arbitrary_inline_fields_exact_whitespace():
    a, b, c = field("A"), field("B"), field("C")
    segments = [{"kind": "text", "text": "Начало: "}, a, {"kind": "text", "text": " / "}, b,
                {"kind": "text", "text": ".\n\nАбзац "}, c, {"kind": "text", "text": "  конец\n"}]
    restored = parse_template(template_source(segments), [a, b, c])
    assert restored == segments
    assert render(restored, {a["id"]: "первое", b["id"]: "второе", c["id"]: "значение"}) == "Начало: первое / второе.\n\nАбзац значение  конец\n"
    assert json.loads(json.dumps(segments)) == segments


def test_empty_field_insertion_and_adjacent_fields():
    a, b = field(), field()
    assert parse_template(f'[[{a["id"]}]][[{b["id"]}]]', [a, b]) == [a, b]
    assert render([a, b], {a["id"]: "x", b["id"]: "y"}) == "xy"


def test_markers_reject_unknown_and_reused_fields():
    a = field()
    with pytest.raises(ValueError):
        parse_template(f'[[{a["id"]}]]', [])
    with pytest.raises(ValueError):
        parse_template(f'[[{a["id"]}]][[{a["id"]}]]', [a])


def test_phrases_append_replace_and_manual_edit():
    assert apply_phrase("Перевозчик", "ТМП20", "append") == "Перевозчик ТМП20"
    assert apply_phrase("Перевозчик", "Стартранс", "replace") == "Стартранс"
    assert apply_phrase("", "ТМП20", "append") + " (дежурный)" == "ТМП20 (дежурный)"


def test_validation_required_number_date():
    a, b, c = field("Имя", required=True), field("Число", type="number"), field("Дата", type="date")
    assert len(validate_values([a, b, c], {a["id"]: "", b["id"]: "x", c["id"]: "2026-02-30"})) == 3
    assert not validate_values([a, b, c], {a["id"]: "ОК", b["id"]: "1,5", c["id"]: "2026-10-21"})


def test_duplicate_master_remaps_links_without_sharing(configured):
    master, block, _, _ = configured
    duplicate = duplicate_master(master)
    assert duplicate["id"] != master["id"]
    assert duplicate["tag"] != master["tag"]
    assert duplicate["links"] == [duplicate["blocks"][0]["id"]]
    duplicate["blocks"][0]["config"]["segments"][0]["text"] = "Изменено"
    assert block["config"]["segments"][0]["text"] == "Перевозчик "


def test_config_broken_links_rejected(store):
    _, config = store.config("draft")
    config["masters"][0]["links"] = ["missing"]
    with pytest.raises(ValueError):
        validate_config(config)


@pytest.mark.parametrize("axis,value", [("width", 10), ("height", -10), ("x", float("nan")), ("y", float("inf"))])
def test_invalid_geometry(store, axis, value):
    _, config = store.config("draft")
    block = new_block("text")
    block[axis] = value
    config["masters"][0]["blocks"] = [block]
    with pytest.raises(ValueError):
        validate_config(config)
