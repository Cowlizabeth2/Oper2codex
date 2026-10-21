import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

ColumnLayout {
    required property var shell
    spacing: 14
    Label { text: "Ошибки Python и QML записываются в startup.log и application.log."; color: Theme.muted }
    ActionButton { text: "Открыть папку логов"; onClicked: shell.run("open_folder", {path:shell.state.dataDir}) }
    ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 8
        model: shell.state.logs
        ScrollBar.vertical: ScrollBar {}
        delegate: Label {
            required property var modelData
            width: ListView.view.width - 16
            text: modelData.created + "  [" + modelData.level + "]  " + modelData.message
            color: modelData.level === "ERROR" ? Theme.error : Theme.muted
            wrapMode: Text.Wrap
        }
    }
}
