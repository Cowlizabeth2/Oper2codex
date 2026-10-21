import QtQuick
import QtQuick.Controls.Basic
import "."

TextArea {
    id: control
    color: Theme.text
    font.pixelSize: Theme.fontSize
    placeholderTextColor: Theme.muted
    selectionColor: Theme.accent
    selectedTextColor: Theme.background
    padding: 10
    wrapMode: TextEdit.Wrap
    selectByMouse: true
    background: Rectangle {
        color: Theme.background
        radius: Theme.radius
        border.color: control.activeFocus ? Theme.accent : Theme.border
    }
}
