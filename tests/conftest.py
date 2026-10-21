import os
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
if sys.platform != "win32":
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")

from operational_center.storage import Store


@pytest.fixture
def store(tmp_path):
    instance = Store(tmp_path / "app.sqlite")
    yield instance
    instance.close()


@pytest.fixture(scope="session")
def app():
    from PySide6.QtWidgets import QApplication
    instance = QApplication.instance() or QApplication([])
    yield instance
    instance.clipboard().clear()
    instance.processEvents()


@pytest.fixture
def configured(store):
    from operational_center.domain import new_block, field
    _, config = store.config("draft")
    master = config["masters"][0]
    block = new_block("text")
    a, b = field("Перевозчик", phrases=["ТМП20", "Стартранс"]), field("Автобус", required=True)
    block["config"]["segments"] = [{"kind": "text", "text": "Перевозчик "}, a, {"kind": "text", "text": ", автобус "}, b, {"kind": "text", "text": ".\nКонец сообщения."}]
    master["blocks"] = [block]
    master["links"] = [block["id"]]
    store.save_draft(config)
    store.publish()
    return master, block, a, b
