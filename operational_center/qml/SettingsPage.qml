import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

ScrollView {
    id: view
    required property var shell
    contentWidth: availableWidth
    clip: true
    ColumnLayout {
        width: view.availableWidth
        spacing: 18
        Label { text: "Оформление и масштаб холста"; color: Theme.text; font.pixelSize: 20; font.bold: true }
        RowLayout {
            ActionButton { text: "Тёмная"; primary: shell.state.theme === "dark"; onClicked: shell.run("theme", {name:"dark"}) }
            ActionButton { text: "Светлая"; primary: shell.state.theme === "light"; onClicked: shell.run("theme", {name:"light"}) }
            Repeater {
                model: [1.0, 1.1, 1.25, 1.5]
                ActionButton { required property real modelData; text: Math.round(modelData * 100) + "%"; primary: shell.state.scale === modelData; onClicked: shell.run("scale", {value:modelData}) }
            }
        }
        Label { text: "Данные и резервирование"; color: Theme.text; font.pixelSize: 20; font.bold: true; Layout.topMargin: 18 }
        Label { text: shell.state.dataDir; color: Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
        RowLayout {
            ActionButton { text: "Открыть папку данных"; onClicked: shell.run("open_folder", {path:shell.state.dataDir}) }
            ActionButton { text: "Создать резервную копию"; onClicked: shell.run("backup") }
            ActionButton {
                text: "Восстановить базу…"
                onClicked: shell.chooseFile(function(path) { shell.confirm("Заменить текущую базу выбранной копией? Перед восстановлением текущая база будет сохранена. Рабочие документы в резервную копию базы не входят.", function() { shell.run("restore", {path:path}) }) }, ["База SQLite (*.sqlite)"])
            }
        }
        Label { text: "Резервная копия содержит SQLite, настройки и состояния карточек. Исходные файлы, рабочие документы и Excel сохраняйте отдельно вместе с папками, на которые ссылается база."; Layout.fillWidth: true; color: Theme.warning; wrapMode: Text.Wrap }
        Label { text: "Перенос конфигурации"; color: Theme.text; font.pixelSize: 20; font.bold: true; Layout.topMargin: 18 }
        RowLayout {
            ActionButton { text: "Экспорт черновика…"; onClicked: shell.chooseFile(function(path) { shell.run("export", {path:path}) }, ["Конфигурация JSON (*.json)"], true) }
            ActionButton { text: "Импорт черновика…"; onClicked: shell.chooseFile(function(path) { shell.confirm("Заменить черновик конструктора импортированной конфигурацией? Опубликованные настройки и происшествия сохранятся.", function() { shell.run("import", {path:path}) }) }, ["Конфигурация JSON (*.json)"]) }
        }
        Label { text: "Временные копии для просмотра"; color: Theme.text; font.pixelSize: 20; font.bold: true; Layout.topMargin: 18 }
        Label { text: "Копии справочных файлов сохраняются до явной очистки, чтобы не удалить документ, открытый во внешней программе. Перед очисткой закройте приложения, использующие эти копии."; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        ActionButton { text: "Очистить копии просмотра"; danger: true; onClicked: shell.confirm("Удалить временные копии просмотра? Сначала закройте открытые документы.", function() { shell.run("clear_previews") }) }
    }
}
