from pathlib import Path

import pytest

from operational_center.domain import new_block
from operational_center.files import DocumentService, ReferenceService, scan, atomic_copy


def setup_documents(store, source, output=""):
    _, config = store.config("draft")
    block = new_block("documents")
    block["config"].update(sources=[str(source)], recursive=True, output=str(output))
    master = config["masters"][0]
    master["blocks"] = [block]
    master["links"] = [block["id"]]
    store.save_draft(config)
    store.publish()
    return master, block


def test_copy_once_per_event_and_missing_warning(store, tmp_path):
    source = tmp_path / "original.docx"
    source.write_bytes(b"original")
    master, block = setup_documents(store, source)
    service = DocumentService(store, tmp_path / "data")
    first = service.initialize(store.create_event(master["id"])["id"])
    second = service.initialize(store.create_event(master["id"])["id"])
    a = Path(first["state"][block["id"]]["files"][0]["path"])
    b = Path(second["state"][block["id"]]["files"][0]["path"])
    assert a != b and a.read_bytes() == b.read_bytes() == b"original"
    a.write_bytes(b"edited")
    source.write_bytes(b"updated original")
    service.initialize(first["id"])
    assert a.read_bytes() == b"edited" and b.read_bytes() == b"original"
    a.unlink()
    reopened = service.initialize(first["id"])
    assert not a.exists()
    assert service.files(reopened["state"][block["id"]])[0]["status"] == "missing"


def test_recursive_copy_filters_and_output_guard(store, tmp_path):
    source = tmp_path / "sources"
    source.mkdir()
    (source / "nested").mkdir()
    (source / "nested" / "a.txt").write_text("A")
    (source / "b.pdf").write_text("B")
    found, errors = scan({"sources": [str(source)], "recursive": True, "extensions": [".txt"]})
    assert len(found) == 1 and not errors
    master, block = setup_documents(store, source, source / "bad-output")
    event = DocumentService(store, tmp_path / "data").initialize(store.create_event(master["id"])["id"])
    entries = event["state"][block["id"]]["files"]
    assert all(e["status"] == "error" for e in entries)
    assert not (source / "bad-output").exists()


def test_missing_file_does_not_block_other_sources(store, tmp_path):
    good = tmp_path / "good.txt"
    good.write_text("OK")
    master, block = setup_documents(store, good)
    _, config = store.config("draft")
    config["masters"][0]["blocks"][0]["config"]["sources"].append(str(tmp_path / "absent"))
    store.save_draft(config); store.publish()
    event = DocumentService(store, tmp_path / "data").initialize(store.create_event(master["id"])["id"])
    assert {f["status"] for f in event["state"][block["id"]]["files"]} == {"ready", "error"}


def test_atomic_copy_never_overwrites(tmp_path):
    source, target = tmp_path / "a", tmp_path / "b"
    source.write_text("a"); target.write_text("b")
    with pytest.raises(FileExistsError):
        atomic_copy(source, target)
    assert target.read_text() == "b"
    assert not list(tmp_path.glob(".copy-*"))


def test_preview_protects_original(tmp_path):
    original = tmp_path / "original.txt"
    original.write_text("original")
    service = ReferenceService(tmp_path / "data")
    preview = Path(service.preview(original))
    preview.write_text("edited")
    assert original.read_text() == "original"
    assert Path(service.preview(original)) != preview
    service.clear()
    assert original.exists() and not preview.exists()


def test_interrupted_manifest_not_recreated(store, tmp_path):
    original = tmp_path / "source.txt"
    original.write_text("original")
    master, block = setup_documents(store, original)
    event = store.create_event(master["id"])
    local = event["state"][block["id"]]
    target = tmp_path / "interrupted.txt"
    local.update(initialized=True, files=[{"path": str(target), "name": "source.txt", "status": "pending"}])
    store.save_state(event["id"], event["state"])
    service = DocumentService(store, tmp_path / "data")
    service.initialize(event["id"])
    assert not target.exists()
    assert service.files(local)[0]["status"] == "error"
