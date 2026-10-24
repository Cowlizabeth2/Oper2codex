import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."
ColumnLayout {
    required property var shell
    spacing: Theme.s12
    RowLayout { Layout.fillWidth: true
        Input { id: search; Layout.fillWidth: true; placeholderText: "Поиск в журнале" }
        ActionButton { text: "Папка логов"; iconName: "reference"; onClicked: shell.run("open_folder",{path:shell.state.dataDir}) }
    }
    Label { text: "Python и QML · startup.log / application.log"; color: Theme.muted; font.pixelSize: Theme.smallSize }
    ListView {
        Layout.fillWidth: true; Layout.fillHeight: true; clip: true
        model: shell.state.logs.filter(function(e) { return e.message.toLowerCase().indexOf(search.text.toLowerCase())>=0 })
        ScrollBar.vertical: ScrollBar {}
        delegate: ColumnLayout {
            required property var modelData
            width: ListView.view.width; spacing: Theme.s4
            Label { text: Qt.formatDateTime(new Date(modelData.created),"dd.MM.yyyy HH:mm")+" · "+modelData.level; color: modelData.level==="ERROR" ? Theme.error : Theme.muted; font.pixelSize: Theme.smallSize }
            Label { text: modelData.message; color: Theme.text; font.pixelSize: Theme.fontSize; wrapMode: Text.Wrap; Layout.fillWidth: true }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; Layout.topMargin: Theme.s8; Layout.bottomMargin: Theme.s8 }
        }
    }
}
