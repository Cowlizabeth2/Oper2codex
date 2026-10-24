pragma Singleton
import QtQuick
QtObject {
    readonly property var manager: backend.themeManager
    readonly property var tokens: manager.tokens
    readonly property real scale: manager.uiScale
    function px(n) { return Math.round(n * scale) }
    readonly property color background: tokens.background
    readonly property color panel: tokens.panel
    readonly property color card: tokens.card
    readonly property color border: tokens.border
    readonly property color accent: tokens.accent
    readonly property color text: tokens.text
    readonly property color muted: tokens.muted
    readonly property color success: tokens.success
    readonly property color warning: tokens.warning
    readonly property color error: tokens.error
    readonly property int s4: px(4)
    readonly property int s8: px(8)
    readonly property int s12: px(12)
    readonly property int s16: px(16)
    readonly property int s24: px(24)
    readonly property int s32: px(32)
    readonly property int radius: px(8)
    readonly property int gap: s8
    readonly property int fontSize: px(13)
    readonly property int titleSize: px(22)
    readonly property int headingSize: px(16)
    readonly property int smallSize: px(11)
    readonly property int control: px(32)
    readonly property int smallControl: px(28)
    readonly property int icon: px(18)
    readonly property int row: px(48)
    readonly property int sidebar: px(184)
    readonly property int sidebarNarrow: px(56)
    readonly property int inspector: px(320)
    readonly property int paletteWidth: px(152)
    readonly property int toolbar: px(44)
    readonly property int header: px(52)
    readonly property int fieldWidth: px(144)
    readonly property int fieldCompact: px(96)
    readonly property int fieldWide: px(300)
    readonly property int fieldMaxHeight: px(128)
    readonly property int grid: 20
    readonly property int canvasMargin: 24
    readonly property int canvasExtra: 600
    readonly property int minBlockWidth: 320
    readonly property int minBlockHeight: 260
    readonly property int nodeWidth: 208
    readonly property int nodeHeight: 88
    readonly property int masterWidth: 176
    readonly property int masterHeight: 88
    readonly property int guideTolerance: 6
    readonly property int resizeHit: 12
    readonly property int resizeMark: 4
}
