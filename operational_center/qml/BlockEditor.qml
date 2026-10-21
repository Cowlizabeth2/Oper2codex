import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

ColumnLayout {
    id: editor
    required property var shell
    property var block: shell.state.selectedBlock
    property var fields: []
    property string currentId: ""
    property bool initialized: false
    spacing: 10
    function loadBlock() {
        if (!block) return
        currentId = block.id
        titleInput.text = block.title
        if (block.type === "text") {
            sourceArea.text = shell.state.templateSource || ""
            fields = JSON.parse(JSON.stringify(shell.state.templateFields || []))
        } else if (block.type === "contacts") {
            contactsPath.text = block.config.path || ""
            tagMapping.text = JSON.stringify(block.config.tag_map || {}, null, 2)
        } else {
            sources.text = (block.config.sources || []).join("\n")
            extensions.text = (block.config.extensions || []).join(", ")
            recursive.checked = !!block.config.recursive
            output.text = block.config.output || ""
        }
    }
    function changeField(index, key, value) { fields[index][key] = value }
    Component.onCompleted: { initialized = true; loadBlock() }
    onBlockChanged: if (initialized) loadBlock()
    Label { text: "Настройки блока"; color: Theme.text; font.pixelSize: 20; font.bold: true }
    Input { id: titleInput; Layout.fillWidth: true; placeholderText: "Название блока" }
    RowLayout {
        ActionButton { text: "Дублировать"; onClicked: shell.run("duplicate_block", {id:editor.block.id}) }
        ActionButton { text: "Удалить…"; danger: true; onClicked: shell.confirm("Удалить этот экземпляр блока и его связь? Изменение затронет только черновик.", function() { shell.run("delete_block", {id:editor.block.id}) }) }
    }
    ColumnLayout {
        visible: editor.block && editor.block.type === "text"
        Layout.fillWidth: true
        spacing: 10
        Label { text: "Произвольный текст шаблона"; color: Theme.text; font.bold: true }
        Label { text: "Выделите любой фрагмент или поставьте курсор, затем добавьте поле. Маркеры [[UUID]] обозначают поля только в конструкторе."; color: Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true; font.pixelSize: Theme.smallSize }
        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: 200
            contentWidth: availableWidth
            Area { id: sourceArea; width: parent.width; persistentSelection: true; placeholderText: "Введите произвольный текст…" }
        }
        Input { id: newFieldLabel; Layout.fillWidth: true; placeholderText: "Подпись нового поля" }
        ActionButton {
            text: "Добавить поле из выделения"
            Layout.fillWidth: true
            onClicked: {
                var result = backend.insertField(sourceArea.text, sourceArea.selectionStart, sourceArea.selectionEnd, JSON.stringify(editor.fields), newFieldLabel.text)
                if (result.source !== undefined) { sourceArea.text = result.source; editor.fields = result.fields }
            }
        }
        Repeater {
            model: editor.fields
            delegate: Rectangle {
                id: fieldCard
                required property var modelData
                required property int index
                Layout.fillWidth: true
                implicitHeight: fieldProperties.implicitHeight + 24
                radius: Theme.radius
                color: Theme.card
                ColumnLayout {
                    id: fieldProperties
                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 12
                    spacing: 6
                    Label { text: "Поле " + (fieldCard.index + 1); color: Theme.accent; font.bold: true }
                    Input { text: fieldCard.modelData.label || ""; placeholderText: "Подпись"; Layout.fillWidth: true; onEditingFinished: editor.changeField(fieldCard.index, "label", text) }
                    Input { text: fieldCard.modelData.placeholder || ""; placeholderText: "Подсказка"; Layout.fillWidth: true; onEditingFinished: editor.changeField(fieldCard.index, "placeholder", text) }
                    Input { text: fieldCard.modelData.default || ""; placeholderText: "Предзаполнение"; Layout.fillWidth: true; onEditingFinished: editor.changeField(fieldCard.index, "default", text) }
                    ComboBox { Layout.fillWidth: true; model: ["Текст", "Число", "Дата ГГГГ-ММ-ДД"]; currentIndex: ["text","number","date"].indexOf(fieldCard.modelData.type || "text"); onActivated: editor.changeField(fieldCard.index,"type",["text","number","date"][currentIndex]) }
                    CheckBox { text: "Обязательное"; checked: !!fieldCard.modelData.required; onToggled: editor.changeField(fieldCard.index,"required",checked) }
                    CheckBox { text: "Многострочное"; checked: !!fieldCard.modelData.multiline; onToggled: editor.changeField(fieldCard.index,"multiline",checked) }
                    Label { text: "Готовые фразы · одна на строку"; color: Theme.muted; font.pixelSize: Theme.smallSize }
                    Area { text: (fieldCard.modelData.phrases || []).join("\n"); Layout.fillWidth: true; implicitHeight: 80; onTextChanged: if (activeFocus) editor.changeField(fieldCard.index,"phrases",text.split("\n").filter(function(v) { return v.length > 0 })) }
                    ComboBox { Layout.fillWidth: true; model: ["Заменять значение", "Добавлять через пробел"]; currentIndex: fieldCard.modelData.phrase_mode === "append" ? 1 : 0; onActivated: editor.changeField(fieldCard.index,"phrase_mode",currentIndex === 1 ? "append" : "replace") }
                    Label { text: fieldCard.modelData.id; color: Theme.muted; font.pixelSize: 10; wrapMode: Text.Wrap; Layout.fillWidth: true }
                }
            }
        }
        ActionButton { text: "Сохранить шаблон"; primary: true; Layout.fillWidth: true; onClicked: { editor.forceActiveFocus(); backend.saveTemplate(editor.block.id, titleInput.text, sourceArea.text, JSON.stringify(editor.fields)) } }
    }
    ColumnLayout {
        visible: editor.block && editor.block.type === "contacts"
        Layout.fillWidth: true
        spacing: 10
        Label { text: "Справочник Excel"; color: Theme.text; font.bold: true }
        Input { id: contactsPath; Layout.fillWidth: true; placeholderText: "Полный путь к XLSX" }
        ActionButton { text: "Подключить существующий Excel…"; Layout.fillWidth: true; onClicked: shell.chooseFile(function(path) { contactsPath.text = path }, ["Excel (*.xlsx)"]) }
        ActionButton { text: "Создать справочник контактов…"; Layout.fillWidth: true; onClicked: shell.chooseFolder(function(path) { shell.run("create_contacts", {id:editor.block.id,folder:path}) }) }
        ActionButton { text: "Открыть справочник"; Layout.fillWidth: true; enabled: contactsPath.text.length > 0; onClicked: shell.run("open_folder", {path:contactsPath.text}) }
        Label { text: "Соответствие Excel-тегов системным тегам (JSON)"; color: Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
        Area { id: tagMapping; Layout.fillWidth: true; implicitHeight: 110; placeholderText: '{"ДТП": "dtp", "Столица": "stolica"}' }
        Label { text: "Ключ — понятный тег из Excel, значение — системный тег мастер-блока. Совпадение целиком, регистр и лишние пробелы не учитываются."; color: Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true; font.pixelSize: Theme.smallSize }
        ActionButton {
            text: "Сохранить контакты"; primary: true; Layout.fillWidth: true
            onClicked: { try { shell.run("save_block", {id:editor.block.id,title:titleInput.text,config:{path:contactsPath.text,tag_map:JSON.parse(tagMapping.text)}}) } catch(e) { shell.confirm("Проверьте формат JSON соответствия тегов: " + e, function() {}) } }
        }
    }
    ColumnLayout {
        visible: editor.block && (editor.block.type === "documents" || editor.block.type === "reference")
        Layout.fillWidth: true
        spacing: 10
        Label { text: "Источники · один полный путь на строку"; color: Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
        Area { id: sources; Layout.fillWidth: true; implicitHeight: 150; placeholderText: "Файлы и папки" }
        RowLayout {
            ActionButton { text: "+ Файл…"; onClicked: shell.chooseFile(function(path) { sources.text += (sources.text ? "\n" : "") + path }) }
            ActionButton { text: "+ Папка…"; onClicked: shell.chooseFolder(function(path) { sources.text += (sources.text ? "\n" : "") + path }) }
        }
        CheckBox { id: recursive; text: "Включая вложенные папки" }
        Input { id: extensions; Layout.fillWidth: true; placeholderText: "Расширения: docx, xlsx, pdf (пусто — все)" }
        Label { visible: editor.block && editor.block.type === "documents"; text: "Папка рабочих комплектов (пусто — в данных приложения)"; color: Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
        Input { id: output; visible: editor.block && editor.block.type === "documents"; Layout.fillWidth: true; placeholderText: "Папка вывода" }
        ActionButton { visible: editor.block && editor.block.type === "documents"; text: "Выбрать папку вывода…"; Layout.fillWidth: true; onClicked: shell.chooseFolder(function(path) { output.text = path }) }
        Label { text: editor.block && editor.block.type === "documents" ? "Все копии создаются автоматически при создании карточки. Исходники не изменяются." : "Просмотр открывает отдельную копию. «Копировать файлы» помещает файловые объекты в буфер Windows."; color: Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true; font.pixelSize: Theme.smallSize }
        ActionButton {
            text: "Сохранить настройки файлов"; primary: true; Layout.fillWidth: true
            onClicked: {
                var cfg = {sources:sources.text.split("\n").map(function(s) { return s.trim() }).filter(function(s) { return s.length > 0 }),recursive:recursive.checked,extensions:extensions.text.split(",").map(function(s) { return s.trim() }).filter(function(s) { return s.length > 0 })}
                if (editor.block.type === "documents") cfg.output = output.text
                shell.run("save_block", {id:editor.block.id,title:titleInput.text,config:cfg})
            }
        }
    }
    Label { text: editor.block ? "UUID блока: " + editor.block.id : ""; color: Theme.muted; font.pixelSize: Theme.smallSize; wrapMode: Text.Wrap; Layout.fillWidth: true }
}
