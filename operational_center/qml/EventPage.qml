import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

ColumnLayout {
    id: view
    required property var shell
    spacing: 14
    Label { visible: !shell.state.event; text: "Выберите мастер-кнопку на главной или откройте происшествие из истории."; color: Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
    RowLayout {
        visible: shell.state.event !== null
        Layout.fillWidth: true
        ColumnLayout {
            Layout.fillWidth: true
            Label { text: shell.state.event ? shell.state.event.name + " №" + shell.state.event.number : ""; color: Theme.text; font.bold: true; font.pixelSize: 22 }
            Label { text: shell.state.event ? new Date(shell.state.event.created).toLocaleString(Qt.locale("ru_RU")) + " · Конфигурация v" + shell.state.event.config_version : ""; color: Theme.muted; font.pixelSize: Theme.smallSize }
        }
        ActionButton { text: "Завершить / архивировать"; onClicked: shell.confirm("Завершить происшествие? Данные сохранятся в истории.", function() { shell.run("archive_event", {id:shell.state.event.id}) }) }
    }
    Label { visible: shell.state.event !== null && shell.state.event.snapshot.blocks.length === 0; text: "В этой версии мастер-кнопки нет связанных блоков. Настройте и опубликуйте её в конструкторе, затем создайте новое происшествие."; color: Theme.warning; wrapMode: Text.Wrap; Layout.fillWidth: true }
    Flickable {
        id: scroll
        visible: shell.state.event !== null
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: Math.max(scroll.width - 16, stage.width * shell.state.scale)
        contentHeight: Math.max(scroll.height - 16, stage.height * shell.state.scale)
        ScrollBar.vertical: ScrollBar {}
        ScrollBar.horizontal: ScrollBar {}
        Item {
            id: stage
            width: shell.state.event ? shell.state.event.snapshot.blocks.reduce(function(acc,b) { return Math.max(acc, b.x+b.width+30) }, 800) : 800
            height: shell.state.event ? shell.state.event.snapshot.blocks.reduce(function(acc,b) { return Math.max(acc, b.y+b.height+30) }, 600) : 600
            scale: shell.state.scale
            transformOrigin: Item.TopLeft
            Repeater {
                model: shell.state.event ? shell.state.event.snapshot.blocks : []
                RuntimeBlock {
                    required property var modelData
                    block: modelData
                    shell: view.shell
                    x: modelData.x
                    y: modelData.y
                    width: modelData.width
                    height: modelData.height
                }
            }
        }
    }
}
