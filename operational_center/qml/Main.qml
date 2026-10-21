import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs
import "."

ApplicationWindow {
    id: window
    width: Math.min(1480, Screen.desktopAvailableWidth)
    height: Math.min(940, Screen.desktopAvailableHeight)
    minimumWidth: Math.min(1120, Screen.desktopAvailableWidth)
    minimumHeight: Math.min(720, Screen.desktopAvailableHeight)
    visible: true
    title: "Оперативный центр · " + window.state.version
    color: Theme.background
    font.family: Qt.platform.os === "windows" ? "Segoe UI" : "DejaVu Sans"
    font.pixelSize: Theme.fontSize
    palette.window: Theme.background
    palette.windowText: Theme.text
    palette.base: Theme.background
    palette.text: Theme.text
    palette.button: Theme.panel
    palette.buttonText: Theme.text
    palette.highlight: Theme.accent
    palette.highlightedText: Theme.background
    property var state: backend.state
    property string page: "home"
    property var pendingAction: function() {}
    property var fileCallback: function(path) {}
    property var folderCallback: function(path) {}

    function run(action, args) { return backend.command(action, JSON.stringify(args || {})) }
    function confirm(text, callback) { confirmationText.text = text; pendingAction = callback; confirmation.open() }
    function chooseFile(callback, filters, save) {
        fileCallback = callback
        filePicker.nameFilters = filters || ["Все файлы (*)"]
        filePicker.fileMode = save ? FileDialog.SaveFile : FileDialog.OpenFile
        filePicker.open()
    }
    function chooseFolder(callback) { folderCallback = callback; folderPicker.open() }
    function titleForPage() {
        return ({home:"Главная", events:"Активные происшествия", history:"История", builder:"Конструктор", settings:"Настройки", logs:"Журнал"})[page]
    }

    FileDialog { id: filePicker; onAccepted: window.fileCallback(backend.localPath(selectedFile.toString())) }
    FolderDialog { id: folderPicker; onAccepted: window.folderCallback(backend.localPath(selectedFolder.toString())) }
    Dialog {
        id: confirmation
        title: "Подтверждение"
        anchors.centerIn: parent
        width: 500
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        contentItem: Label { id: confirmationText; wrapMode: Text.WordWrap; color: Theme.text }
        onAccepted: window.pendingAction()
    }
    Dialog {
        id: notification
        title: "Оперативный центр"
        anchors.centerIn: parent
        width: 620
        standardButtons: Dialog.Ok
        contentItem: Label { id: notificationText; wrapMode: Text.Wrap; color: Theme.text }
    }
    Connections {
        target: backend
        function onNotice(message) { notificationText.text = message; notification.open() }
    }
    Shortcut { sequences: [StandardKey.Undo]; enabled: page === "builder"; onActivated: window.run("undo") }
    Shortcut { sequences: [StandardKey.Redo]; enabled: page === "builder"; onActivated: window.run("redo") }

    RowLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.preferredWidth: 216
            Layout.fillHeight: true
            color: Theme.panel
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 10
                Label { text: "ОЦ"; color: Theme.accent; font.pixelSize: 36; font.bold: true; Layout.topMargin: 8 }
                Label { text: "ОПЕРАТИВНЫЙ\nЦЕНТР"; color: Theme.text; font.bold: true; font.letterSpacing: 2; Layout.bottomMargin: 30 }
                Repeater {
                    model: [{key:"home", label:"Главная"}, {key:"events", label:"Происшествия"}, {key:"history", label:"История"}, {key:"builder", label:"Конструктор"}, {key:"settings", label:"Настройки"}, {key:"logs", label:"Журнал"}]
                    delegate: ActionButton {
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData.label
                        primary: window.page === modelData.key
                        onClicked: window.page = modelData.key
                    }
                }
                Item { Layout.fillHeight: true }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
                Label { text: "Локальное рабочее место"; color: Theme.muted; font.pixelSize: Theme.smallSize }
                Label { text: "v" + window.state.version + " · " + window.state.commit.slice(0, 8); color: Theme.muted; font.pixelSize: Theme.smallSize }
                Label { text: "Данные сохраняются автоматически"; wrapMode: Text.Wrap; Layout.fillWidth: true; color: Theme.success; font.pixelSize: Theme.smallSize }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 78
                color: Theme.background
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    Label { text: window.titleForPage(); color: Theme.text; font.pixelSize: Theme.titleSize; font.bold: true; Layout.fillWidth: true }
                    Label { text: "КОНСТРУКТОР · ЧЕРНОВИК"; visible: page === "builder"; color: Theme.warning; font.pixelSize: Theme.smallSize }
                    ActionButton { text: window.state.theme === "dark" ? "Светлая тема" : "Тёмная тема"; onClicked: window.run("theme", {name: window.state.theme === "dark" ? "light" : "dark"}) }
                }
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                visible: window.state.events.some(function(e) { return e.visible && !e.archived })
                ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                Row {
                    spacing: 6
                    leftPadding: 22
                    Repeater {
                        model: window.state.events.filter(function(e) { return e.visible && !e.archived })
                        delegate: Row {
                            required property var modelData
                            spacing: 2
                            ActionButton {
                                text: modelData.name + " №" + modelData.number
                                primary: window.state.event !== null && window.state.event.id === modelData.id && page === "events"
                                onClicked: { window.run("select_event", {id:modelData.id}); window.page = "events" }
                            }
                            ActionButton { text: "×"; onClicked: window.run("hide_event", {id:modelData.id}); ToolTip.visible: hovered; ToolTip.text: "Скрыть вкладку. Событие останется в истории." }
                        }
                    }
                }
            }
            Loader {
                id: pages
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 22
                sourceComponent: page === "home" ? home : page === "events" ? events : page === "builder" ? builder : page === "history" ? history : page === "settings" ? settings : logs
            }
        }
    }
    Component { id: home; HomePage { shell: window } }
    Component { id: events; EventPage { shell: window } }
    Component { id: builder; BuilderPage { shell: window } }
    Component { id: history; HistoryPage { shell: window } }
    Component { id: settings; SettingsPage { shell: window } }
    Component { id: logs; LogsPage { shell: window } }
}
