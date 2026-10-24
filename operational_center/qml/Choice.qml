import QtQuick
import QtQuick.Controls.Basic
import "."
ComboBox {
    id: control
    implicitHeight: Theme.control
    implicitWidth: Theme.fieldWidth
    font.pixelSize: Theme.fontSize
    leftPadding: Theme.s8
    rightPadding: Theme.s24
    contentItem: Text { text: control.displayText; color: Theme.text; font: control.font; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
    indicator: Icon { name: "chevron"; tint: Theme.muted; x: control.width - width - Theme.s8; anchors.verticalCenter: parent.verticalCenter }
    background: Rectangle { color: control.hovered ? Theme.card : Theme.background; radius: Theme.radius; border.color: control.activeFocus ? Theme.accent : Theme.border }
    delegate: ItemDelegate { width: control.width; text: control.textRole ? modelData[control.textRole] : modelData; font.pixelSize: Theme.fontSize; palette.text: Theme.text; highlighted: control.highlightedIndex === index }
    popup: Popup {
        y: control.height + Theme.s4
        width: Math.max(control.width, Theme.fieldWidth)
        padding: Theme.s4
        implicitHeight: Math.min(contentItem.implicitHeight + Theme.s8, Theme.px(320))
        background: Rectangle { color: Theme.panel; border.color: Theme.border; radius: Theme.radius }
        contentItem: ListView { clip: true; implicitHeight: contentHeight; model: control.popup.visible ? control.delegateModel : null; currentIndex: control.highlightedIndex; ScrollBar.vertical: ScrollBar {} }
    }
}
