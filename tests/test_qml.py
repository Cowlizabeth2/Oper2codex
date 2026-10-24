import json
from pathlib import Path

from PySide6.QtCore import QUrl, QObject, QPoint, QPointF, Qt
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow
from PySide6.QtTest import QTest

from operational_center.controller import Controller


def visual_child(item, name):
    if item.objectName() == name:
        return item
    for child in item.childItems():
        found = visual_child(child, name)
        if found is not None:
            return found
    return None


def test_real_mouse_drag_resize_and_window_resize_preserve_coordinates(app, store, tmp_path):
    c = Controller(store, tmp_path)
    assert c.command("add_block", json.dumps({"type": "text"}))
    identity = c.selected_block
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("backend", c)
    engine.load(QUrl.fromLocalFile(str(Path(__file__).resolve().parents[1] / "operational_center" / "qml" / "Main.qml")))
    assert engine.rootObjects()
    root = engine.rootObjects()[0]
    root.setPosition(0, 0)
    root.resize(1480, 940)
    root.setProperty("page", "builder")
    QTest.qWait(150)
    try:
        handle = visual_child(root.contentItem(), "dragHandle-" + identity)
        assert handle is not None
        start = handle.mapToScene(QPointF(30, 20)).toPoint()
        before = c.state["master"]["blocks"][0].copy()
        QTest.mousePress(root, Qt.LeftButton, Qt.NoModifier, start)
        QTest.mouseMove(root, start + QPoint(20, 20), 30)
        QTest.mouseMove(root, start + QPoint(80, 80), 30)
        QTest.mouseRelease(root, Qt.LeftButton, Qt.NoModifier, start + QPoint(80, 80))
        QTest.qWait(100)
        moved = c.state["master"]["blocks"][0].copy()
        assert moved["x"] > before["x"] and moved["y"] > before["y"]
        # Native Windows mouse events must stay on the actual desktop, even
        # when the test window exceeds the runner's display. Scroll the grip
        # into view rather than injecting a click outside the screen.
        viewport = visual_child(root.contentItem(), "builderViewport")
        flickable = viewport.property("contentItem")
        flickable.setProperty("contentX", max(0, moved["x"] + moved["width"] - min(380,viewport.width()/2)))
        flickable.setProperty("contentY", max(0, moved["y"] + moved["height"] - min(220,viewport.height()/2)))
        QTest.qWait(100)
        handle = visual_child(root.contentItem(), "resizeHandle-" + identity)
        assert handle is not None
        start = handle.mapToScene(QPointF(handle.width()/2, handle.height()/2)).toPoint()
        local=handle.mapToItem(viewport,QPointF(handle.width()/2,handle.height()/2))
        assert 0<local.x()<viewport.width() and 0<local.y()<viewport.height()
        QTest.mousePress(root, Qt.LeftButton, Qt.NoModifier, start)
        assert handle.property("pressed"), {"pointer": (start.x(),start.y()), "window": (root.width(),root.height()), "canvasOffset": (flickable.property("contentX"),flickable.property("contentY"))}
        QTest.mouseMove(root, start + QPoint(20, 20), 30)
        QTest.mouseMove(root, start + QPoint(60, 50), 30)
        QTest.mouseRelease(root, Qt.LeftButton, Qt.NoModifier, start + QPoint(60, 50))
        QTest.qWait(100)
        resized = c.state["master"]["blocks"][0].copy()
        assert resized["width"] > moved["width"] and resized["height"] > moved["height"]
        root.resize(1200, 780)
        QTest.qWait(100)
        assert c.state["master"]["blocks"][0] == resized
        c.command("theme", json.dumps({"name": "light"}))
        QTest.qWait(50)
        assert root.property("color").name() == "#f2f5fa"
    finally:
        root.close()
        del root
        del engine
