import QtQuick
import QtQuick.Controls.Basic
import "."
CheckBox {
    id: control
    implicitHeight: Theme.control
    spacing: Theme.s8
    indicator: Rectangle { x: 0; y: (control.height-height)/2; width: Theme.icon; height: Theme.icon; radius: Theme.s4; color: control.checked ? Theme.accent : Theme.background; border.color: control.activeFocus ? Theme.accent : Theme.border
        Icon { anchors.centerIn: parent; name: "check"; tint: Theme.background; visible: control.checked; width: Theme.px(14); height: width }
    }
    contentItem: Text { text: control.text; leftPadding: Theme.icon + Theme.s8; verticalAlignment: Text.AlignVCenter; color: control.enabled ? Theme.text : Theme.muted; font.pixelSize: Theme.fontSize; elide: Text.ElideRight }
}
