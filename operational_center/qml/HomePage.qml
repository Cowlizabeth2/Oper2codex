import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."
ScrollView {
    id: view
    required property var shell
    clip: true
    contentWidth: availableWidth
    function focusSearch() { search.forceActiveFocus() }
    ColumnLayout {
        width: view.availableWidth; spacing: Theme.s16
        RowLayout { Layout.fillWidth: true
            ColumnLayout { Layout.fillWidth: true; spacing: Theme.s4
                Label { text: "Новое происшествие"; color: Theme.text; font.pixelSize: Theme.titleSize; font.bold: true }
                Label { text: "Выберите сценарий. Каждое нажатие создаёт отдельную карточку."; color: Theme.muted; font.pixelSize: Theme.fontSize }
            }
            Input { id: search; objectName: "masterSearch"; Layout.preferredWidth: Theme.px(240); placeholderText: "Поиск сценария  ·  Ctrl K" }
        }
        GridLayout {
            Layout.fillWidth: true
            columns: Math.max(1,Math.floor(width / Theme.px(248)))
            columnSpacing: Theme.s12; rowSpacing: Theme.s12
            Repeater {
                model: shell.state.published.masters.filter(function(m) { return m.name.toLowerCase().indexOf(search.text.toLowerCase()) >= 0 })
                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    Layout.fillWidth: true; Layout.minimumWidth: Theme.px(208); implicitHeight: Theme.px(112)
                    radius: Theme.radius; color: mouse.containsMouse ? Theme.card : Theme.panel; border.color: mouse.containsMouse ? Theme.accent : Theme.border
                    ColumnLayout { anchors.fill: parent; anchors.margins: Theme.s16; spacing: Theme.s8
                        RowLayout { Layout.fillWidth: true
                            Item { width: Theme.icon; height: Theme.icon; implicitWidth: Theme.icon; implicitHeight: Theme.icon
                                Icon { visible: tile.modelData.icon==="!"; name: tile.modelData.tag.indexOf("dtp")===0 ? "car" : tile.modelData.tag==="fire" ? "flame" : tile.modelData.tag==="stolica" ? "building" : "events"; tint: Theme.accent }
                                Text { visible: tile.modelData.icon!=="!"; anchors.centerIn: parent; text: tile.modelData.icon; color: tile.modelData.color; font.pixelSize: Theme.headingSize }
                            }
                            Label { text: tile.modelData.name; color: Theme.text; font.pixelSize: Theme.headingSize; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                            Icon { name: "arrow"; tint: mouse.containsMouse ? Theme.accent : Theme.muted }
                        }
                        Item { Layout.fillHeight: true }
                        Label { text: tile.modelData.links.length + " блоков  ·  Новая карточка"; color: Theme.muted; font.pixelSize: Theme.smallSize }
                    }
                    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (shell.run("create_event",{id:tile.modelData.id})) shell.page = "events" }
                }
            }
        }
        Label { visible: shell.state.published.masters.length === 0; text: "Добавьте первый сценарий в конструкторе"; color: Theme.muted; font.pixelSize: Theme.fontSize }
        RowLayout { Layout.fillWidth: true; Layout.topMargin: Theme.s12
            Label { text: "Последние происшествия"; color: Theme.text; font.bold: true; font.pixelSize: Theme.headingSize; Layout.fillWidth: true }
            ActionButton { text: "Вся история"; iconName: "arrow"; quiet: true; onClicked: shell.page = "history" }
        }
        ColumnLayout {
            Layout.fillWidth: true; spacing: 0
            Repeater {
                model: shell.state.events.slice(0,5)
                delegate: Rectangle {
                    id: recent
                    required property var modelData
                    Layout.fillWidth: true; implicitHeight: Theme.row
                    color: recentMouse.containsMouse ? Theme.panel : "transparent"
                    RowLayout { anchors.fill: parent; anchors.leftMargin: Theme.s12; anchors.rightMargin: Theme.s12; spacing: Theme.s16
                        Label { text: "#" + recent.modelData.number; color: Theme.muted; font.pixelSize: Theme.fontSize; Layout.preferredWidth: Theme.px(56) }
                        Label { text: recent.modelData.name; color: Theme.text; font.pixelSize: Theme.fontSize; Layout.fillWidth: true; elide: Text.ElideRight }
                        Label { text: Qt.formatDateTime(new Date(recent.modelData.created),"dd.MM.yyyy HH:mm"); color: Theme.muted; font.pixelSize: Theme.smallSize }
                        Label { text: recent.modelData.archived ? "Архив" : "В работе"; color: recent.modelData.archived ? Theme.muted : Theme.success; font.pixelSize: Theme.smallSize; Layout.preferredWidth: Theme.px(72) }
                        Icon { name: "arrow" }
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border }
                    MouseArea { id: recentMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { shell.run("select_event",{id:recent.modelData.id}); shell.page = "events" } }
                }
            }
            Label { visible: shell.state.events.length === 0; text: "Здесь появятся созданные карточки. Настройте блоки в конструкторе и опубликуйте сценарий."; color: Theme.muted; font.pixelSize: Theme.fontSize; Layout.fillWidth: true; wrapMode: Text.Wrap; Layout.topMargin: Theme.s8 }
        }
    }
}
