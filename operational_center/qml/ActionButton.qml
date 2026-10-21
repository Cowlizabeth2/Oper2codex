import QtQuick
import QtQuick.Controls.Basic
import "."

Button {
    id: control
    property bool primary: false
    property bool danger: false
    implicitHeight: 38
    implicitWidth: Math.max(38, contentItem.implicitWidth + 28)
    hoverEnabled: true
    padding: 10
    font.pixelSize: Theme.fontSize
    contentItem: Text {
        text: control.text
        font: control.font
        color: !control.enabled ? Theme.muted : control.danger ? Theme.error : control.primary ? Theme.background : Theme.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        radius: Theme.radius
        color: control.primary && control.enabled ? Theme.accent : control.down ? Theme.border : control.hovered ? Theme.card : Theme.panel
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? Theme.accent : Theme.border
        opacity: control.enabled ? 1 : 0.5
    }
}
