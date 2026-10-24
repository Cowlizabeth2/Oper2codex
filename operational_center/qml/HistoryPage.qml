import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."
ColumnLayout {
    id: view
    required property var shell
    spacing: Theme.s12
    function focusSearch() { search.forceActiveFocus() }
    property var filtered: shell.state.events.filter(function(e) { return (e.name+" "+e.number).toLowerCase().indexOf(search.text.toLowerCase()) >= 0 && (status.currentIndex === 0 || (status.currentIndex === 1 && !e.archived) || (status.currentIndex === 2 && !e.visible && !e.archived) || (status.currentIndex === 3 && e.archived)) })
    RowLayout { Layout.fillWidth: true
        Input { id: search; Layout.fillWidth: true; placeholderText: "Поиск по типу или номеру  ·  Ctrl K" }
        Choice { id: status; model: ["Все статусы","В работе","Скрытые вкладки","Архив"]; Layout.preferredWidth: Theme.px(176) }
        Label { text: view.filtered.length + " записей"; color: Theme.muted; font.pixelSize: Theme.smallSize }
    }
    RowLayout {
        Layout.fillWidth: true; Layout.leftMargin: Theme.s12; Layout.rightMargin: Theme.s12; spacing: Theme.s16
        Label { text: "НОМЕР"; color: Theme.muted; font.pixelSize: Theme.smallSize; Layout.preferredWidth: Theme.px(64) }
        Label { text: "ПРОИСШЕСТВИЕ"; color: Theme.muted; font.pixelSize: Theme.smallSize; Layout.fillWidth: true }
        Label { text: "СОЗДАНО"; color: Theme.muted; font.pixelSize: Theme.smallSize; Layout.preferredWidth: Theme.px(176) }
        Label { text: "СТАТУС"; color: Theme.muted; font.pixelSize: Theme.smallSize; Layout.preferredWidth: Theme.px(100) }
        Label { text: "ДЕЙСТВИЯ"; color: Theme.muted; font.pixelSize: Theme.smallSize; Layout.preferredWidth: Theme.px(176) }
    }
    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
    ListView {
        Layout.fillWidth: true; Layout.fillHeight: true; clip: true
        model: view.filtered
        ScrollBar.vertical: ScrollBar {}
        delegate: Rectangle {
            id: row
            required property var modelData
            width: ListView.view.width; height: Theme.row
            color: hover.hovered ? Theme.panel : "transparent"
            HoverHandler { id: hover }
            RowLayout { anchors.fill: parent; anchors.leftMargin: Theme.s12; anchors.rightMargin: Theme.s12; spacing: Theme.s16
                Label { text: "#"+row.modelData.number; color: Theme.muted; font.pixelSize: Theme.fontSize; Layout.preferredWidth: Theme.px(64) }
                Label { text: row.modelData.name; color: Theme.text; font.pixelSize: Theme.fontSize; elide: Text.ElideRight; Layout.fillWidth: true }
                Label { text: Qt.formatDateTime(new Date(row.modelData.created),"dd.MM.yyyy HH:mm"); color: Theme.muted; font.pixelSize: Theme.smallSize; Layout.preferredWidth: Theme.px(176) }
                Label { text: row.modelData.archived ? "Архив" : "В работе"; color: row.modelData.archived ? Theme.muted : Theme.success; font.pixelSize: Theme.smallSize; Layout.preferredWidth: Theme.px(100) }
                RowLayout { Layout.preferredWidth: Theme.px(176); spacing: Theme.s4
                    ActionButton { text: row.modelData.archived ? "Вернуть" : "Открыть"; quiet: true; onClicked: { shell.run("select_event",{id:row.modelData.id}); shell.page = "events" } }
                    ActionButton { iconName: "history"; quiet: true; tip: "Архивировать"; visible: !row.modelData.archived; onClicked: shell.confirm("Завершить происшествие? Данные сохранятся в истории.",function() { shell.run("archive_event",{id:row.modelData.id}) }) }
                }
            }
            Rectangle { width: parent.width; height: 1; anchors.bottom: parent.bottom; color: Theme.border }
        }
        Label { anchors.centerIn: parent; visible: parent.count === 0; text: "Нет записей по выбранным условиям"; color: Theme.muted; font.pixelSize: Theme.fontSize }
    }
}
