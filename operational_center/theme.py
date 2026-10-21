"""Shared design tokens, loaded once per theme change."""
PALETTES = {
    "dark": {"background": "#11151D", "panel": "#1B2330", "card": "#222D3B", "border": "#344153", "accent": "#8AB4FF", "text": "#EEF2F8", "muted": "#9BAFC0", "success": "#88D4B0", "warning": "#FFD18A", "error": "#FF9DAB"},
    "light": {"background": "#F2F5FA", "panel": "#FFFFFF", "card": "#E8EEF6", "border": "#CBD5E1", "accent": "#2563EB", "text": "#172235", "muted": "#64748B", "success": "#16724E", "warning": "#805400", "error": "#B42340"},
}


def theme(store):
    name = store.pref("theme", "dark")
    if not isinstance(name, str) or name not in PALETTES:
        name = "dark"
    return name, dict(PALETTES[name])
