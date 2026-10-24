"""Shared design tokens, loaded once per theme change."""
PALETTES = {
    "dark": {"background": "#11151D", "panel": "#181F2B", "card": "#202A38", "border": "#344153", "accent": "#8AB4FF", "text": "#EEF2F8", "muted": "#9BAFC0", "success": "#88D4B0", "warning": "#FFD18A", "error": "#FF9DAB"},
    "light": {"background": "#F2F5FA", "panel": "#FFFFFF", "card": "#E8EEF6", "border": "#CBD5E1", "accent": "#2563EB", "text": "#172235", "muted": "#64748B", "success": "#16724E", "warning": "#805400", "error": "#B42340"},
}


def theme(store):
    name = store.pref("theme", "dark")
    if not isinstance(name, str) or name not in PALETTES:
        name = "dark"
    return name, dict(PALETTES[name])


from PySide6.QtCore import QObject, Property, Signal


class ThemeManager(QObject):
    """Cached tokens for the whole UI; no control performs SQLite queries."""
    changed = Signal()

    def __init__(self, store, parent=None):
        super().__init__(parent)
        self.store = store
        self._name, self._tokens = theme(store)
        scale = store.pref("ui_scale", 1.0)
        self._scale = scale if isinstance(scale, (int, float)) and .85 <= scale <= 1.5 else 1.0

    def reload(self):
        self._name, self._tokens = theme(self.store)
        scale = self.store.pref("ui_scale", 1.0)
        self._scale = scale if isinstance(scale, (int, float)) and .85 <= scale <= 1.5 else 1.0
        self.changed.emit()

    tokens = Property("QVariantMap", lambda self: dict(self._tokens), notify=changed)
    name = Property(str, lambda self: self._name, notify=changed)
    uiScale = Property(float, lambda self: self._scale, notify=changed)
