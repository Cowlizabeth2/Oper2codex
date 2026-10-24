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
        width: Math.min(view.availableWidth,Theme.px(880)); spacing: Theme.s16
        Section { title: "Оформление"
            RowLayout {
                ActionButton { text: "Тёмная"; iconName: "moon"; primary: shell.state.theme==="dark"; onClicked: shell.run("theme",{name:"dark"}) }
                ActionButton { text: "Светлая"; iconName: "sun"; primary: shell.state.theme==="light"; onClicked: shell.run("theme",{name:"light"}) }
                Label { text: "Масштаб интерфейса"; color: Theme.muted; font.pixelSize: Theme.fontSize; Layout.leftMargin: Theme.s16 }
                Choice { model: ["85%","100%","110%","125%","150%"]; currentIndex: [.85,1,1.1,1.25,1.5].indexOf(shell.state.uiScale); Layout.preferredWidth: Theme.px(96); onActivated: shell.run("ui_scale",{value:[.85,1,1.1,1.25,1.5][currentIndex]}) }
            }
            Label { text: "Масштаб холста меняется отдельно в рабочей карточке или конструкторе. Логические координаты блоков сохраняются."; color: Theme.muted; font.pixelSize: Theme.smallSize; Layout.fillWidth: true; wrapMode: Text.Wrap }
        }
        Section { title: "Хранилище и резервные копии"
            Label { text: shell.state.dataDir; color: Theme.muted; font.pixelSize: Theme.fontSize; wrapMode: Text.Wrap; Layout.fillWidth: true }
            Flow { Layout.fillWidth: true; spacing: Theme.s8
                ActionButton { text: "Папка данных"; iconName: "reference"; onClicked: shell.run("open_folder",{path:shell.state.dataDir}) }
                ActionButton { text: "Создать копию БД"; iconName: "save"; onClicked: shell.run("backup") }
                ActionButton { text: "Восстановить…"; iconName: "history"; onClicked: shell.chooseFile(function(path) { shell.confirm("Заменить базу выбранной копией? Текущая база сначала будет сохранена. Внешние документы в копию SQLite не входят.",function() { shell.run("restore",{path:path}) }) },["База SQLite (*.sqlite)"]) }
            }
            Label { text: "SQLite содержит настройки и карточки. Документы, Excel и рабочие комплекты резервируйте отдельно."; color: Theme.warning; font.pixelSize: Theme.smallSize; Layout.fillWidth: true; wrapMode: Text.Wrap }
        }
        Section { title: "Перенос сценариев"
            Flow { Layout.fillWidth: true; spacing: Theme.s8
                ActionButton { text: "Экспорт черновика…"; iconName: "documents"; onClicked: shell.chooseFile(function(path) { shell.run("export",{path:path}) },["Конфигурация JSON (*.json)"],true) }
                ActionButton { text: "Импорт черновика…"; iconName: "plus"; onClicked: shell.chooseFile(function(path) { shell.confirm("Заменить черновик импортированной конфигурацией? Происшествия и опубликованные настройки сохранятся.",function() { shell.run("import",{path:path}) }) },["Конфигурация JSON (*.json)"]) }
            }
        }
        Section { title: "Диагностика старых текстовых шаблонов"
            Label { text: "Проверка читает черновик, опубликованные шаблоны и снимки происшествий. Преобразование выполняется только после просмотра выбранных записей; перед записью обязательно создаётся копия БД."; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.muted; font.pixelSize: Theme.fontSize }
            ActionButton { objectName: "inspectTemplates"; text: "Проверить структуру шаблонов…"; iconName: "search"; onClicked: shell.inspectTemplates() }
        }
        Section { title: "Копии для безопасного просмотра"; expanded: false
            Label { text: "Сначала закройте документы во внешних приложениях. Очистка удалит только временные копии, исходники сохранятся."; color: Theme.muted; font.pixelSize: Theme.fontSize; wrapMode: Text.Wrap; Layout.fillWidth: true }
            ActionButton { text: "Очистить копии просмотра…"; iconName: "trash"; danger: true; onClicked: shell.confirm("Удалить временные копии просмотра? Убедитесь, что они закрыты во внешних программах.",function() { shell.run("clear_previews") }) }
        }
        Label { text: "Оперативный центр "+shell.state.version; color: Theme.muted; font.pixelSize: Theme.smallSize }
        Label { text: "Полный SHA коммита сборки"; color: Theme.muted; font.pixelSize: Theme.smallSize }
        TextEdit { objectName: "buildCommit"; text: shell.state.commit; readOnly: true; selectByMouse: true; wrapMode: TextEdit.WrapAnywhere; color: Theme.text; font.pixelSize: Theme.fontSize; Layout.fillWidth: true }
    }
}
