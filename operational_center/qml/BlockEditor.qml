import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."
ColumnLayout {
    id: editor
    objectName: "blockInspector"
    required property var shell
    property var block: shell.state.selectedBlock
    property var fields: []
    property int fieldIndex: 0
    property var selectedField: fields.length ? fields[Math.min(fieldIndex,fields.length-1)] : null
    property bool initialized: false
    property bool dirty: false
    property string fingerprint: ""
    property string loadedIdentity: ""
    spacing: Theme.s12
    function loadBlock() {
        if(!block) return
        var next=JSON.stringify([block.id,block.title,block.config,block.accent || ""])
        if(next===fingerprint) return
        var previous=loadedIdentity===block.id && selectedField ? selectedField.id : ""
        loadedIdentity=block.id;fingerprint=next;titleInput.text=block.title;accent.text=block.accent || ""
        if(block.type==="text") { sourceArea.text=shell.state.templateSource || "";fields=JSON.parse(JSON.stringify(shell.state.templateFields || []));fieldIndex=Math.max(0,fields.findIndex(function(f) { return f.id===previous }));loadField() }
        else if(block.type==="static_text") { staticSource.text=block.config.text;staticFormat.currentIndex=block.config.format==="markdown" ? 1 : 0;staticCopy.checked=block.config.copy_enabled!==false;staticSize.text=String(block.config.font_size || 13);staticAlignment.currentIndex=Math.max(0,["left","center","right"].indexOf(block.config.alignment || "left")) }
        else if(block.type==="contacts") { contactsPath.text=block.config.path || "";tagMapping.text=JSON.stringify(block.config.tag_map || {},null,2) }
        else { sources.text=(block.config.sources || []).join("\n");extensions.text=(block.config.extensions || []).join(", ");recursive.checked=!!block.config.recursive;output.text=block.config.output || "" }
        dirty=false
    }
    function loadField() {
        if(!selectedField) return
        fieldLabel.text=selectedField.label || "";fieldHint.text=selectedField.placeholder || "";fieldDefault.text=selectedField.default || "";phrases.text=(selectedField.phrases || []).join("\n")
    }
    function changeField(key,value) { if(selectedField) { selectedField[key]=value;dirty=true } }
    function insert(area) {
        var result=backend.insertField(area.text,area.selectionStart,area.selectionEnd,JSON.stringify(fields),newFieldLabel.text)
        if(result.source!==undefined) { area.text=result.source;fields=result.fields;fieldIndex=fields.length-1;loadField();dirty=true }
    }
    function save() {
        editor.forceActiveFocus()
        var cfg
        if(block.type==="text") { if(backend.saveTemplate(block.id,titleInput.text,sourceArea.text,JSON.stringify(fields),accent.text)) dirty=false;return }
        if(block.type==="static_text") { cfg={text:staticSource.text,format:staticFormat.currentIndex===1 ? "markdown" : "plain",copy_enabled:staticCopy.checked,font_size:Number(staticSize.text),alignment:["left","center","right"][staticAlignment.currentIndex]} }
        else if(block.type==="contacts") {
            try { cfg={path:contactsPath.text,tag_map:JSON.parse(tagMapping.text)} } catch(e) { shell.confirm("Проверьте JSON соответствия тегов: "+e,function() {});return }
        } else {
            cfg={sources:sources.text.split("\n").map(function(s) { return s.trim() }).filter(function(s) { return s.length>0 }),recursive:recursive.checked,extensions:extensions.text.split(",").map(function(s) { return s.trim() }).filter(function(s) { return s.length>0 })}
            if(block.type==="documents") cfg.output=output.text
        }
        if(shell.run("save_block",{id:block.id,title:titleInput.text,config:cfg,accent:accent.text})) dirty=false
    }
    Component.onCompleted: { initialized=true;loadBlock() }
    onBlockChanged: if(initialized) loadBlock()
    RowLayout { Layout.fillWidth: true
        Label { text: "Свойства блока"; color: Theme.text; font.pixelSize: Theme.headingSize; font.bold: true; Layout.fillWidth: true }
        ActionButton { iconName: "copy"; quiet: true; tip: "Дублировать"; onClicked: shell.run("duplicate_block",{id:editor.block.id}) }
        ActionButton { iconName: "trash"; quiet: true; danger: true; tip: "Удалить"; onClicked: shell.confirm("Удалить этот блок из черновика?",function() { shell.run("delete_block",{id:editor.block.id}) }) }
    }
    Section { title: "Общее"
        Input { id: titleInput; Layout.fillWidth: true; placeholderText: "Название блока"; onTextEdited: editor.dirty=true }
        Label { text: editor.block ? ({text:"Текстовый шаблон",static_text:"Свободный текст · без полей",contacts:"Контакты Excel",documents:"Рабочие документы",reference:"Сопутствующие файлы"})[editor.block.type] : ""; color: Theme.muted; font.pixelSize: Theme.smallSize }
    }
    Section {
        title: "Свободный текст"; visible: editor.block && editor.block.type==="static_text"
        ScrollView { Layout.fillWidth: true; Layout.preferredHeight: Theme.px(220); contentWidth: availableWidth
            Area { id: staticSource; objectName: "staticTextEditor"; placeholderText: "Текст для сотрудника"; onTextChanged: if(activeFocus) editor.dirty=true }
        }
        Choice { id: staticFormat; Layout.fillWidth: true; model: ["Обычный текст","Базовое форматирование"]; onActivated: editor.dirty=true }
        Label { text: "**жирный**, *курсив*, __подчёркнутый__, # заголовок. При копировании разметка убирается, переносы сохраняются. HTML не выполняется."; visible: staticFormat.currentIndex===1; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.muted; font.pixelSize: Theme.smallSize }
        Check { id: staticCopy; text: "Показывать кнопку копирования"; onToggled: editor.dirty=true }
        Input { id: staticSize; Layout.fillWidth: true; placeholderText: "Размер текста: 10–32"; onTextEdited: editor.dirty=true }
        Choice { id: staticAlignment; Layout.fillWidth: true; model: ["По левому краю","По центру","По правому краю"]; onActivated: editor.dirty=true }
    }
    Section {
        title: "Содержимое"; visible: editor.block && editor.block.type==="text"
        Label { text: "Выделите фрагмент или поставьте курсор, чтобы создать поле."; color: Theme.muted; font.pixelSize: Theme.smallSize; wrapMode: Text.Wrap; Layout.fillWidth: true }
        ScrollView { Layout.fillWidth: true; Layout.preferredHeight: Theme.px(160); contentWidth: availableWidth
            Area { id: sourceArea; objectName: "templateSourceEditor"; persistentSelection: true; placeholderText: "Текст сообщения…"; onTextChanged: if(activeFocus) editor.dirty=true }
        }
        Input { id: newFieldLabel; objectName: "newFieldLabel"; Layout.fillWidth: true; placeholderText: "Название нового поля" }
        ActionButton { objectName: "createTemplateField"; text: "Создать поле ввода"; iconName: "plus"; Layout.fillWidth: true; onClicked: editor.insert(sourceArea) }
        ActionButton { text: "Развернуть редактор"; iconName: "fit"; quiet: true; Layout.fillWidth: true; onClicked: templateDialog.open() }
    }
    Section {
        title: "Поля"; visible: editor.block && editor.block.type==="text"
        Choice { Layout.fillWidth: true; model: editor.fields; textRole: "label"; currentIndex: editor.fields.length ? editor.fieldIndex : -1; onActivated: { editor.fieldIndex=currentIndex;editor.loadField() } }
        ColumnLayout { Layout.fillWidth: true; visible: !!editor.selectedField; spacing: Theme.s8
            Input { id: fieldLabel; Layout.fillWidth: true; placeholderText: "Название поля"; onTextEdited: editor.changeField("label",text) }
            Input { id: fieldHint; Layout.fillWidth: true; placeholderText: "Подсказка"; onTextEdited: editor.changeField("placeholder",text) }
            Input { id: fieldDefault; Layout.fillWidth: true; placeholderText: "Предзаполнение"; onTextEdited: editor.changeField("default",text) }
            Choice { Layout.fillWidth: true; model: ["Текст","Число","Дата ГГГГ-ММ-ДД"]; currentIndex: editor.selectedField ? ["text","number","date"].indexOf(editor.selectedField.type || "text") : 0; onActivated: editor.changeField("type",["text","number","date"][currentIndex]) }
            Check { text: "Обязательное"; checked: !!editor.selectedField && !!editor.selectedField.required; onToggled: editor.changeField("required",checked) }
            Check { text: "Многострочное"; checked: !!editor.selectedField && !!editor.selectedField.multiline; onToggled: editor.changeField("multiline",checked) }
            ActionButton { text: "Преобразовать в обычный текст"; quiet: true; Layout.fillWidth: true; onClicked: { var f=editor.selectedField;sourceArea.text=sourceArea.text.split(f._editor_token || "[["+f.id+"]]").join(f.default || "");var a=editor.fields.slice();a.splice(editor.fieldIndex,1);editor.fields=a;editor.fieldIndex=0;editor.loadField();editor.dirty=true } }
        }
        Label { text: "Поля ещё не добавлены"; visible: editor.fields.length===0; color: Theme.muted; font.pixelSize: Theme.smallSize }
    }
    Section {
        title: "Пресеты"; visible: editor.block && editor.block.type==="text" && !!editor.selectedField
        Label { text: "Фразы выбранного поля · одна на строку"; color: Theme.muted; font.pixelSize: Theme.smallSize; wrapMode: Text.Wrap; Layout.fillWidth: true }
        Area { id: phrases; Layout.fillWidth: true; implicitHeight: Theme.px(88); onTextChanged: if(activeFocus) editor.changeField("phrases",text.split("\n").filter(function(s) { return s.length>0 })) }
        Choice { Layout.fillWidth: true; model: ["Заменять значение","Добавлять через пробел"]; currentIndex: editor.selectedField && editor.selectedField.phrase_mode==="append" ? 1 : 0; onActivated: editor.changeField("phrase_mode",currentIndex===1 ? "append" : "replace") }
    }
    Section {
        title: "Источники данных"; visible: editor.block && editor.block.type==="contacts"
        Input { id: contactsPath; Layout.fillWidth: true; placeholderText: "Путь к XLSX"; onTextEdited: editor.dirty=true }
        ActionButton { text: "Подключить Excel…"; iconName: "file"; Layout.fillWidth: true; onClicked: shell.chooseFile(function(path) { contactsPath.text=path;editor.dirty=true },["Excel (*.xlsx)"]) }
        ActionButton { text: "Создать справочник…"; iconName: "plus"; Layout.fillWidth: true; onClicked: shell.chooseFolder(function(path) { shell.run("create_contacts",{id:editor.block.id,folder:path}) }) }
        ActionButton { text: "Открыть справочник"; iconName: "arrow"; quiet: true; Layout.fillWidth: true; enabled: contactsPath.text.length>0; onClicked: shell.run("open_folder",{path:contactsPath.text}) }
        Label { text: "Теги Excel → системные теги (JSON)"; color: Theme.muted; font.pixelSize: Theme.smallSize }
        Area { id: tagMapping; Layout.fillWidth: true; implicitHeight: Theme.px(88); placeholderText: '{"ДТП":"dtp"}'; onTextChanged: if(activeFocus) editor.dirty=true }
    }
    Section {
        title: "Источники данных"; visible: editor.block && (editor.block.type==="documents" || editor.block.type==="reference")
        Area { id: sources; Layout.fillWidth: true; implicitHeight: Theme.px(128); placeholderText: "Файл или папка · один путь на строку"; onTextChanged: if(activeFocus) editor.dirty=true }
        RowLayout { Layout.fillWidth: true
            ActionButton { text: "Файл"; iconName: "plus"; Layout.fillWidth: true; onClicked: shell.chooseFile(function(path) { sources.text+=(sources.text ? "\n" : "")+path;editor.dirty=true }) }
            ActionButton { text: "Папка"; iconName: "plus"; Layout.fillWidth: true; onClicked: shell.chooseFolder(function(path) { sources.text+=(sources.text ? "\n" : "")+path;editor.dirty=true }) }
        }
        Check { id: recursive; text: "Включая вложенные папки"; onToggled: editor.dirty=true }
        Input { id: extensions; Layout.fillWidth: true; placeholderText: "Расширения: docx, xlsx, pdf"; onTextEdited: editor.dirty=true }
        Input { id: output; visible: editor.block && editor.block.type==="documents"; Layout.fillWidth: true; placeholderText: "Папка копий · пусто: данные приложения"; onTextEdited: editor.dirty=true }
        ActionButton { visible: output.visible; text: "Папка рабочих копий…"; iconName: "reference"; Layout.fillWidth: true; onClicked: shell.chooseFolder(function(path) { output.text=path;editor.dirty=true }) }
    }
    Section { title: "Оформление"; expanded: false
        Input { id: accent; objectName: "blockAccent"; Layout.fillWidth: true; placeholderText: "Цвет метки #RRGGBB · пусто: тема"; onTextEdited: editor.dirty=true }
        ActionButton { text: "Сохранить оформление"; Layout.fillWidth: true; onClicked: editor.save() }
    }
    Label { text: editor.dirty ? "Есть несохранённые изменения" : "Настройки сохранены в черновике"; color: editor.dirty ? Theme.warning : Theme.muted; font.pixelSize: Theme.smallSize }
    ActionButton { text: "Сохранить блок"; iconName: "save"; primary: true; Layout.fillWidth: true; onClicked: editor.save() }
    Dialog {
        id: templateDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width-Theme.s32,Theme.px(960))
        height: Math.min(parent.height-Theme.s32,Theme.px(640))
        title: "Редактор текстового шаблона"
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        property string originalFields
        onOpened: { largeArea.text=sourceArea.text;originalFields=JSON.stringify(editor.fields) }
        onAccepted: { sourceArea.text=largeArea.text;editor.dirty=true }
        onRejected: { editor.fields=JSON.parse(originalFields);editor.loadField() }
        contentItem: ColumnLayout {
            spacing: Theme.s12
            Label { text: "Произвольный текст. Выделите фрагмент и создайте поле; маркеры обозначают редактируемые участки."; color: Theme.muted; font.pixelSize: Theme.fontSize; wrapMode: Text.Wrap; Layout.fillWidth: true }
            ScrollView { Layout.fillWidth: true; Layout.fillHeight: true; contentWidth: availableWidth
                Area { id: largeArea; persistentSelection: true }
            }
            RowLayout { Layout.fillWidth: true
                ActionButton { text: "Создать поле ввода"; iconName: "plus"; onClicked: editor.insert(largeArea) }
                Label { text: editor.fields.length+" полей"; color: Theme.muted; font.pixelSize: Theme.smallSize }
            }
        }
    }
}
