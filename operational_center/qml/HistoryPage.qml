import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

ColumnLayout {
    required property var shell
    spacing: 14
    Input { id: search; Layout.fillWidth: true; placeholderText: "Поиск по названию или номеру" }
    Label { visible: shell.state.events.length === 0; text: "Происшествий пока нет"; color: Theme.muted }
    ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 8
        model: shell.state.events.filter(function(e) { return (e.name + " " + e.number).toLowerCase().indexOf(search.text.toLowerCase()) !== -1 })
        ScrollBar.vertical: ScrollBar {}
        delegate: Rectangle {
            required property var modelData
            width: ListView.view.width
            height: 84
            radius: Theme.radius
            color: Theme.panel
            border.color: Theme.border
            RowLayout {
                anchors.fill: parent
                anchors.margins: 15
                ColumnLayout {
                    Layout.fillWidth: true
                    Label { text: modelData.name + " №" + modelData.number; color: Theme.text; font.bold: true }
                    Label { text: new Date(modelData.created).toLocaleString(Qt.locale("ru_RU")) + (modelData.archived ? " · Архив" : " · В работе"); color: Theme.muted; font.pixelSize: Theme.smallSize }
                }
                ActionButton { text: modelData.archived ? "Вернуть в работу" : "Открыть"; onClicked: { shell.run("select_event", {id:modelData.id}); shell.page = "events" } }
                ActionButton { text: "Архивировать"; visible: !modelData.archived; onClicked: shell.confirm("Завершить происшествие? Его можно будет вернуть из истории.", function() { shell.run("archive_event", {id:modelData.id}) }) }
            }
        }
    }
}
