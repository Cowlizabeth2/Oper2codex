import QtQuick
import QtQuick.Controls.Basic
import "."
TextField {
    id: control
    implicitHeight: Theme.control
    font.pixelSize: Theme.fontSize
    color: Theme.text
    placeholderTextColor: Theme.muted
    selectionColor: Theme.accent
    selectedTextColor: Theme.background
    leftPadding: Theme.s8
    rightPadding: Theme.s8
    topPadding: Theme.s4
    bottomPadding: Theme.s4
    selectByMouse: true
    background: Rectangle { color: Theme.background; radius: Theme.radius; border.color: control.activeFocus ? Theme.accent : Theme.border; border.width: control.activeFocus ? 2 : 1 }
}
