import QtQuick
import QtQuick.Controls.Basic
import "."
Button {
    id: control
    property bool primary: false
    property bool danger: false
    property bool quiet: false
    property string iconName: ""
    property string tip: ""
    implicitHeight: Theme.control
    implicitWidth: Math.max(Theme.control, contentItem.implicitWidth + Theme.s16)
    hoverEnabled: true
    padding: Theme.s8
    font.pixelSize: Theme.fontSize
    Accessible.name: text || tip
    ToolTip.visible: hovered && tip.length > 0
    ToolTip.text: tip
    ToolTip.delay: 500
    contentItem: Row {
        spacing: control.text && control.iconName ? Theme.s8 : 0
        Icon { visible: control.iconName.length > 0; name: control.iconName; tint: control.primary ? Theme.background : control.danger ? Theme.error : Theme.muted; anchors.verticalCenter: parent.verticalCenter }
        Text { text: control.text; font: control.font; color: !control.enabled ? Theme.muted : control.danger ? Theme.error : control.primary ? Theme.background : Theme.text; anchors.verticalCenter: parent.verticalCenter }
    }
    background: Rectangle {
        radius: Theme.radius
        color: control.primary && control.enabled ? Theme.accent : control.down ? Theme.border : control.hovered ? Theme.card : control.quiet ? "transparent" : Theme.panel
        border.width: control.activeFocus ? 2 : control.quiet ? 0 : 1
        border.color: control.activeFocus ? Theme.accent : Theme.border
        opacity: control.enabled ? 1 : 0.45
    }
}
