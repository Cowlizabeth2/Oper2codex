pragma Singleton
import QtQuick

QtObject {
    property var tokens: backend.state.tokens
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
    readonly property int radius: 10
    readonly property int gap: 12
    readonly property int fontSize: 14
    readonly property int titleSize: 25
    readonly property int smallSize: 12
}
