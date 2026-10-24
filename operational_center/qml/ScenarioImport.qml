import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."
Dialog {
    id: dialog
    objectName: "scenarioImportDialog"
    required property var shell
    property var preview: shell.state.importPreview
    property var catalogs: [{id:"",name:"Без добавления в каталог"}].concat(shell.state.draft.catalogs || [])
    parent: Overlay.overlay; anchors.centerIn: parent
    width: Math.min(parent.width-Theme.s32,Theme.px(980)); height: Math.min(parent.height-Theme.s32,Theme.px(680))
    title: "Импорт сценариев из Excel · предварительная проверка"; modal: true; standardButtons: Dialog.Close
    onOpened: { standardButton(Dialog.Close).text="Закрыть";confirmed.checked=false;targetCatalog.currentIndex=0 }
    onClosed: shell.run("cancel_scenario_import")
    contentItem: ColumnLayout {
        spacing: Theme.s8
        Label { text: "XLSX: название, системный код, теги, алиасы, категория, папка документов, шаблон (системный код или UUID), код КМ. Списки разделяются точкой с запятой."; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.muted; font.pixelSize: Theme.smallSize }
        RowLayout { Layout.fillWidth: true
            Input { id: pathInput; objectName: "scenarioImportPath"; Layout.fillWidth: true; placeholderText: "Путь к XLSX"; onTextEdited: {confirmed.checked=false;dialog.shell.run("cancel_scenario_import")} }
            ActionButton { text: "Выбрать…"; onClicked: dialog.shell.chooseFile(function(path){pathInput.text=path;confirmed.checked=false;dialog.shell.run("cancel_scenario_import")},["Excel (*.xlsx)"]) }
            ActionButton { text: "Проверить"; objectName: "previewScenarios"; primary: true; enabled: pathInput.text.length>0; onClicked: {confirmed.checked=false;dialog.shell.run("preview_scenarios",{path:pathInput.text})} }
        }
        ActionButton { text: "Сохранить образец XLSX…"; quiet: true; onClicked: dialog.shell.chooseFile(function(path){dialog.shell.run("import_sample",{path:path})},["Excel (*.xlsx)"],true) }
        Label { text: dialog.preview ? "Корректных: "+dialog.preview.valid+" · С ошибками: "+dialog.preview.invalid+". Ошибочные строки будут пропущены." : "Выполните проверку таблицы. Черновик пока не изменяется."; Layout.fillWidth: true; wrapMode: Text.Wrap; color: dialog.preview && dialog.preview.invalid ? Theme.warning : Theme.muted; font.pixelSize: Theme.fontSize }
        ListView { Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: Theme.s4
            model: dialog.preview ? dialog.preview.rows : []
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                id: row
                required property var modelData
                width: ListView.view.width; height: details.implicitHeight+Theme.s16; radius: Theme.radius; color: Theme.panel; border.color: modelData.valid ? Theme.border : Theme.warning
                ColumnLayout { id: details; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Theme.s8; spacing: Theme.s4
                    Label { text: "Строка "+row.modelData.row+" · "+row.modelData.name+" · "+row.modelData.code; color: Theme.text; font.pixelSize: Theme.fontSize; Layout.fillWidth: true; elide: Text.ElideRight }
                    Label { text: [row.modelData.km_code,row.modelData.category,row.modelData.aliases,row.modelData.tags].filter(function(s){return s}).join(" · "); visible: text.length>0; color: Theme.muted; font.pixelSize: Theme.smallSize; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    Label { text: row.modelData.valid ? "Готово · "+row.modelData.template+" · "+(row.modelData.documents || "Источники шаблона") : row.modelData.errors.join("; "); color: row.modelData.valid ? Theme.muted : Theme.warning; font.pixelSize: Theme.smallSize; Layout.fillWidth: true; wrapMode: Text.Wrap }
                }
            }
        }
        Choice { id: targetCatalog; Layout.fillWidth: true; model: dialog.catalogs; textRole: "name" }
        Check { id: confirmed; objectName: "confirmScenarioImport"; enabled: !!dialog.preview && dialog.preview.valid>0; text: "Подтверждаю добавление только корректных строк в черновик" }
        ActionButton { text: "Добавить сценарии"; objectName: "commitScenarios"; primary: true; enabled: !!dialog.preview && dialog.preview.valid>0 && confirmed.checked; Layout.fillWidth: true; onClicked: {if(dialog.shell.run("commit_scenarios",{token:dialog.preview.token,confirmed:true,catalog:dialog.catalogs[targetCatalog.currentIndex].id})){confirmed.checked=false;dialog.close()}} }
    }
}
