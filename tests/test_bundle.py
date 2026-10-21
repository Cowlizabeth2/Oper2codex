import zipfile

import pytest

from tools.make_bundle import make_bundle
from tools.validate_bundle import extract
from pathlib import Path


def test_actual_source_bundle_roundtrip(tmp_path):
    root = Path(__file__).resolve().parents[1]
    first, second = tmp_path / "one.zip", tmp_path / "two.zip"
    make_bundle(root, first); make_bundle(root, second)
    assert first.read_bytes() == second.read_bytes()
    extracted = extract(first, tmp_path / "build")
    assert (extracted / "main.py").read_bytes() == (root / "main.py").read_bytes()
    assert (extracted / "operational_center" / "qml" / "Main.qml").exists()


@pytest.mark.parametrize("path", ["../escape.py", "/absolute.py", "C:/drive.py", "foo\\..\\escape.py", "foo:bar.py", "bad./x"])
def test_rejects_unsafe_archive_paths(tmp_path, path):
    archive = tmp_path / "bad.zip"
    with zipfile.ZipFile(archive, "w") as z:
        z.writestr(path, "unsafe")
    with pytest.raises(ValueError):
        extract(archive, tmp_path / "output")
    assert not (tmp_path / "output").exists()
