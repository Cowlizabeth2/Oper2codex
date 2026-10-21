import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

ScrollView {
    id: view
    required property var shell
    clip: true
    contentWidth: availableWidth
    ColumnLayout {
        width: view.availableWidth
        spacing: 22
        Label { text: "Новое происшествие"; color: Theme.text; font.pixelSize: Theme.titleSize; font.bold: true }
        Label { text: "Каждое нажатие создаёт отдельную карточку со своими данными и рабочими документами."; color: Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
        Flow {
            Layout.fillWidth: true
            spacing: 18
            Repeater {
                model: shell.state.published.masters
                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    width: 285
                    height: 190
                    radius: Theme.radius
                    color: mouse.containsMouse ? Theme.card : Theme.panel
                    border.color: mouse.containsMouse ? Theme.accent : Theme.border
                    Rectangle { x: 20; y: 22; width: 42; height: 42; radius: Theme.radius; color: tile.modelData.color
                        Label { anchors.centerIn: parent; text: tile.modelData.icon; color: Theme.background; font.bold: true; font.pixelSize: 22 }
                    }
                    Label { x: 20; y: 82; width: parent.width - 40; text: tile.modelData.name; elide: Text.ElideRight; color: Theme.text; font.pixelSize: 21; font.bold: true }
                    Label { x: 20; y: 119; text: tile.modelData.links.length + " блоков · новая карточка"; color: Theme.muted }
                    Label { x: 20; y: 155; text: "Создать происшествие  →"; color: Theme.accent }
                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { if (shell.run("create_event", {id:tile.modelData.id})) shell.page = "events" }
                    }
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: hint.implicitHeight + 36
            radius: Theme.radius
            color: Theme.panel
            border.color: Theme.border
            Label { id: hint; anchors.fill: parent; anchors.margins: 18; color: Theme.muted; wrapMode: Text.Wrap; text: "Начните с конструктора: добавьте блоки, настройте их и опубликуйте конфигурацию. В новой установке мастер-кнопки пустые — демонстрационные данные не подменяют ваши файлы и контакты." }
        }
    }
}
