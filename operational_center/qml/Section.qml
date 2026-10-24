import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."
ColumnLayout {
    id: section
    default property alias body: contents.data
    property string title: ""
    property bool expanded: true
    Layout.fillWidth: true
    spacing: Theme.s8
    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
    Item {
        Layout.fillWidth: true; implicitHeight: Theme.control
        Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: section.title; color: Theme.text; font.pixelSize: Theme.fontSize; font.bold: true }
        Icon { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; name: "chevron"; rotation: section.expanded ? 0 : -90 }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: section.expanded = !section.expanded }
    }
    ColumnLayout { id: contents; visible: section.expanded; Layout.fillWidth: true; spacing: Theme.s8 }
}
