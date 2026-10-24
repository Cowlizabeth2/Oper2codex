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
    minimumWidth: Math.min(1080, Screen.desktopAvailableWidth)
    minimumHeight: Math.min(680, Screen.desktopAvailableHeight)
    visible: true
    title: "Оперативный центр · " + window.state.version
    color: Theme.background
    font.family: Qt.platform.os === "windows" ? "Segoe UI" : "DejaVu Sans"
    font.pixelSize: Theme.fontSize
    palette.window: Theme.panel
    palette.windowText: Theme.text
    palette.base: Theme.background
    palette.text: Theme.text
    palette.button: Theme.card
    palette.buttonText: Theme.text
    palette.highlight: Theme.accent
    palette.highlightedText: Theme.background
    property var state: backend.state
    property string page: "home"
    property bool collapsed: window.state.sidebarCollapsed
    property bool editingText: activeFocusItem && typeof activeFocusItem.insert === "function"
    property var pendingAction: function() {}
    property var fileCallback: function(path) {}
    property var folderCallback: function(path) {}
    property alias activePage: pages.item
    property bool catalogModal: catalogSearch.visible || catalogManager.visible || scenarioImport.visible
    function run(action, args) { return backend.command(action, JSON.stringify(args || {})) }
    function confirm(text, callback) { confirmationText.text = text; pendingAction = callback; confirmation.open() }
    function chooseFile(callback, filters, save) { fileCallback = callback; filePicker.nameFilters = filters || ["Все файлы (*)"]; filePicker.fileMode = save ? FileDialog.SaveFile : FileDialog.OpenFile; filePicker.open() }
    function chooseFolder(callback) { folderCallback = callback; folderPicker.open() }
    function openCatalog(item) { catalogSearch.showCatalog(item) }
    function openAllScenarios() { openCatalog({id:"",name:"Все сценарии",opening:"compact",members:[]}) }
    function manageCatalogs() { catalogManager.open() }
    function importScenarios() { scenarioImport.open() }
    CatalogSearch { id: catalogSearch; shell: window }
    CatalogManager { id: catalogManager; shell: window }
    ScenarioImport { id: scenarioImport; shell: window }
    function titleForPage() { return page === "events" && state.event ? state.event.name + " №" + state.event.number : ({home:"Главная",events:"Происшествия",history:"История",builder:"Конструктор",settings:"Настройки",logs:"Журнал"})[page] }
    FileDialog { id: filePicker; onAccepted: window.fileCallback(backend.localPath(selectedFile.toString())) }
    FolderDialog { id: folderPicker; onAccepted: window.folderCallback(backend.localPath(selectedFolder.toString())) }
    Dialog { id: confirmation; objectName: "confirmationDialog"; title: "Подтверждение"; anchors.centerIn: parent; width: Math.min(Theme.px(520),window.width-Theme.s32); modal: true; standardButtons: Dialog.Ok | Dialog.Cancel; contentItem: Label { id: confirmationText; wrapMode: Text.Wrap; color: Theme.text; font.pixelSize: Theme.fontSize } onAccepted: window.pendingAction() }
    Dialog { id: notification; title: "Оперативный центр"; anchors.centerIn: parent; width: Math.min(Theme.px(560),window.width-Theme.s32); standardButtons: Dialog.Ok; contentItem: Label { id: notificationText; wrapMode: Text.Wrap; color: Theme.text; font.pixelSize: Theme.fontSize } }
    Connections { target: backend; function onNotice(message) { notificationText.text = message; notification.open() } }
    Shortcut { sequences: [StandardKey.Undo]; enabled: page === "builder" && !window.editingText && !window.catalogModal; onActivated: window.run("undo") }
    Shortcut { sequences: [StandardKey.Redo]; enabled: page === "builder" && !window.editingText && !window.catalogModal; onActivated: window.run("redo") }
    Shortcut { sequence: "Ctrl+K"; enabled: !window.catalogModal; onActivated: if (pages.item && typeof pages.item.focusSearch === "function") pages.item.focusSearch() }
    RowLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.preferredWidth: window.collapsed ? Theme.sidebarNarrow : Theme.sidebar
            Layout.fillHeight: true
            color: Theme.panel
            ColumnLayout {
                anchors.fill: parent; anchors.margins: Theme.s8; spacing: Theme.s4
                RowLayout {
                    Layout.fillWidth: true; Layout.preferredHeight: Theme.header
                    Rectangle { width: Theme.control; height: width; radius: Theme.radius; color: Theme.accent; Text { anchors.centerIn: parent; text: "ОЦ"; font.bold: true; font.pixelSize: Theme.smallSize; color: Theme.background } }
                    Label { visible: !window.collapsed; text: "Оперативный\nцентр"; color: Theme.text; font.bold: true; font.pixelSize: Theme.fontSize; Layout.fillWidth: true }
                }
                Repeater {
                    model: [{key:"home",label:"Главная"},{key:"events",label:"Происшествия"},{key:"history",label:"История"},{key:"builder",label:"Конструктор"},{key:"settings",label:"Настройки"},{key:"logs",label:"Журнал"}]
                    delegate: Rectangle {
                        id: nav
                        required property var modelData
                        Layout.fillWidth: true; implicitHeight: Theme.control + Theme.s4
                        radius: Theme.radius; color: window.page === modelData.key || navMouse.containsMouse ? Theme.card : "transparent"
                        RowLayout { anchors.fill: parent; anchors.leftMargin: Theme.s12; anchors.rightMargin: Theme.s8; spacing: Theme.s12
                            Icon { name: nav.modelData.key; tint: window.page === nav.modelData.key ? Theme.accent : Theme.muted }
                            Label { visible: !window.collapsed; text: nav.modelData.label; Layout.fillWidth: true; color: window.page === nav.modelData.key ? Theme.text : Theme.muted; font.pixelSize: Theme.fontSize; font.bold: window.page === nav.modelData.key }
                        }
                        MouseArea { id: navMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.page = nav.modelData.key }
                        ToolTip.visible: window.collapsed && navMouse.containsMouse
                        ToolTip.text: modelData.label
                    }
                }
                Item { Layout.fillHeight: true }
                Label { visible: !window.collapsed; text: "●  Локальные данные"; color: Theme.success; font.pixelSize: Theme.smallSize; Layout.leftMargin: Theme.s12 }
                RowLayout { Layout.fillWidth: true
                    ActionButton { iconName: "collapse"; quiet: true; rotation: window.collapsed ? 180 : 0; tip: window.collapsed ? "Развернуть меню" : "Свернуть меню"; onClicked: window.run("sidebar",{collapsed:!window.collapsed}) }
                    Label { visible: !window.collapsed; text: "v" + window.state.version; color: Theme.muted; font.pixelSize: Theme.smallSize; Layout.fillWidth: true }
                }
            }
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.border }
        }
        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
            Item {
                Layout.fillWidth: true; Layout.preferredHeight: Theme.header
                RowLayout { anchors.fill: parent; anchors.leftMargin: Theme.s24; anchors.rightMargin: Theme.s16; spacing: Theme.s12
                    Label { text: window.titleForPage(); color: Theme.text; font.pixelSize: Theme.headingSize; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                    Label { text: "ЧЕРНОВИК"; visible: page === "builder"; color: Theme.warning; font.pixelSize: Theme.smallSize }
                    Label { text: "ОФЛАЙН"; color: Theme.muted; font.pixelSize: Theme.smallSize }
                    ActionButton { iconName: window.state.theme === "dark" ? "sun" : "moon"; quiet: true; tip: "Переключить тему"; onClicked: window.run("theme", {name:window.state.theme === "dark" ? "light" : "dark"}) }
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
            ScrollView {
                Layout.fillWidth: true; Layout.preferredHeight: Theme.toolbar
                visible: window.state.events.some(function(e) { return e.visible && !e.archived })
                ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                Row { spacing: Theme.s4; leftPadding: Theme.s16; topPadding: Theme.s4
                    Repeater {
                        model: window.state.events.filter(function(e) { return e.visible && !e.archived })
                        delegate: Rectangle {
                            id: tab
                            required property var modelData
                            property bool selected: window.state.event && window.state.event.id === modelData.id && page === "events"
                            width: tabRow.implicitWidth + Theme.s12; height: Theme.control; radius: Theme.radius; color: selected ? Theme.card : "transparent"
                            RowLayout { id: tabRow; anchors.centerIn: parent; spacing: 0
                                ActionButton { text: tab.modelData.name + " №" + tab.modelData.number; quiet: true; onClicked: { window.run("select_event",{id:tab.modelData.id}); window.page = "events" } }
                                ActionButton { iconName: "close"; quiet: true; tip: "Скрыть вкладку; событие останется в истории"; onClicked: window.run("hide_event",{id:tab.modelData.id}) }
                            }
                            Rectangle { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; width: parent.width - Theme.s16; height: 2; color: Theme.accent; visible: tab.selected }
                        }
                    }
                }
            }
            Loader {
                id: pages
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.leftMargin: Theme.s16; Layout.rightMargin: Theme.s16; Layout.bottomMargin: Theme.s16; Layout.topMargin: Theme.s12
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
