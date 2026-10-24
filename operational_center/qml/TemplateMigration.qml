import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."
Dialog {
    id: dialog
    objectName: "templateMigrationDialog"
    required property var shell
    property var diagnostics: shell.state.templateDiagnostics
    property var candidates: diagnostics ? diagnostics.candidates : []
    property var candidate: candidateChoice.currentIndex>=0 ? candidates[candidateChoice.currentIndex] : null
    property var preview: shell.state.templateMigration
    property var selected: []
    parent: Overlay.overlay; anchors.centerIn: parent
    width: Math.min(parent.width-Theme.s32,Theme.px(1000))
    height: Math.min(parent.height-Theme.s32,Theme.px(760))
    title: "SQLite · проверка и преобразование текстовых шаблонов"
    modal: true; standardButtons: Dialog.Close
    onOpened: { standardButton(Dialog.Close).text="Закрыть";prefixInput.text="";selected=[];confirmed.checked=false;sourceChoice.currentIndex=0;candidateChoice.currentIndex=candidates.length ? 0 : -1 }
    onClosed: shell.run("cancel_template_migration")
    function cancelReview() { selected=[];confirmed.checked=false;shell.run("cancel_template_migration") }
    function toggle(key) { var list=selected.slice(),index=list.indexOf(key);if(index<0)list.push(key);else list.splice(index,1);selected=list;confirmed.checked=false }
    contentItem: ColumnLayout {
        spacing: Theme.s8
        Label { text: "Выявлено признаков проблем: "+(dialog.diagnostics ? dialog.diagnostics.problem_count : 0)+". Проверяются фактические segments, значения и фразы из SQLite, включая старые снимки происшествий. Никакие подписи не угадываются. Исходная база автоматически копируется перед записью."; color: Theme.muted; font.pixelSize: Theme.smallSize; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText }
        Label { visible: !!dialog.diagnostics && dialog.diagnostics.unsupported.length>0; text: dialog.diagnostics ? dialog.diagnostics.unsupported.map(function(r){return r.scope+" / "+r.block+": "+r.reason}).join("\n") : ""; color: Theme.warning; font.pixelSize: Theme.smallSize; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText }
        Choice { id: candidateChoice; objectName: "migrationFieldChoice"; model: dialog.candidates; textRole: "title"; Layout.fillWidth: true; onActivated: {prefixInput.text="";dialog.cancelReview()} }
        ScrollView { Layout.fillWidth: true; Layout.preferredHeight: Theme.px(100); contentWidth: availableWidth; clip: true
            Area { objectName: "templateRawRecords"; readOnly: true; textFormat: TextEdit.PlainText; text: dialog.candidate ? "block_id="+dialog.candidate.block_id+"\nfield_id="+dialog.candidate.field_id+"\n\n"+dialog.candidate.records.map(function(r){return r.scope+"\nkind="+r.kind+"; previous="+JSON.stringify(r.previous_segment)+"\nСвойства="+JSON.stringify(r.properties)+"\nПроблемы="+r.issues.join("; ")+"\nsegments="+JSON.stringify(r.segments)+"\ndefault="+JSON.stringify(r.default)+"\nvalue="+JSON.stringify(r.value)+"; stored="+r.value_present+"\nphrases="+JSON.stringify(r.phrases)+"\nunmatched_value_keys="+JSON.stringify(r.unmatched_value_keys)}).join("\n\n") : "Текстовые поля не найдены" }
        }
        Choice { id: sourceChoice; objectName: "migrationSource"; Layout.fillWidth: true; model: ["default — предзаполнение","value — старое значение","text — старое текстовое свойство","placeholder — подсказка"]; onActivated: dialog.cancelReview() }
        RowLayout { Layout.fillWidth: true
            Input { id: prefixInput; objectName: "migrationPrefix"; Layout.fillWidth: true; placeholderText: "Точный префикс, включая пробел после двоеточия"; onTextEdited: dialog.cancelReview() }
            ActionButton { objectName: "previewTemplateMigration"; text: "Предпросмотр"; enabled: !!dialog.candidate && prefixInput.text.length>0; onClicked: {dialog.selected=[];confirmed.checked=false;dialog.shell.run("preview_template_migration",{block_id:dialog.candidate.block_id,field_id:dialog.candidate.field_id,prefix:prefixInput.text,source_property:["default","value","text","placeholder"][sourceChoice.currentIndex]})} }
        }
        Label { text: "Выносится в постоянный текст: "+JSON.stringify(prefixInput.text); color: Theme.muted; font.pixelSize: Theme.smallSize; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText }
        Label { text: "Отметьте отдельно каждую запись. Значение без префикса сохраняется целиком; добавление подписи может изменить копируемый текст. Такие случаи выделены предупреждением."; color: Theme.warning; font.pixelSize: Theme.smallSize; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText }
        ListView { id: records; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: Theme.s8
            model: dialog.preview ? dialog.preview.rows : []
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                id: row
                required property var modelData
                width: ListView.view.width; height: details.implicitHeight+Theme.s16; color: Theme.panel; border.color: modelData.copy_changes || modelData.phrase_changes || !modelData.eligible ? Theme.warning : Theme.border; radius: Theme.radius
                ColumnLayout { id: details; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Theme.s8; spacing: Theme.s4
                    Check { objectName: "migrationRecord-"+row.modelData.key; text: row.modelData.scope; Layout.fillWidth: true; enabled: row.modelData.eligible; checked: dialog.selected.indexOf(row.modelData.key)>=0; onToggled: dialog.toggle(row.modelData.key) }
                    Label { text: row.modelData.eligible ? row.modelData.source_property+": "+JSON.stringify(row.modelData.source_before)+"\ndefault: "+JSON.stringify(row.modelData.default_before)+" → "+JSON.stringify(row.modelData.default_after)+"\nvalue: "+JSON.stringify(row.modelData.value_before)+" → "+JSON.stringify(row.modelData.value_after)+"\nphrases: "+JSON.stringify(row.modelData.phrases_before)+" → "+JSON.stringify(row.modelData.phrases_after) : row.modelData.reason; color: Theme.text; font.pixelSize: Theme.smallSize; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText }
                    Label { visible: row.modelData.eligible; text: row.modelData.copy_changes || row.modelData.phrase_changes ? "Изменится текст копирования или применение фразы — требуется ваш явный выбор" : "Итоговое сообщение сохранится посимвольно"; color: row.modelData.copy_changes || row.modelData.phrase_changes ? Theme.warning : Theme.success; font.pixelSize: Theme.smallSize; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText }
                    ActionButton { text: "Полное сообщение до / после…"; visible: row.modelData.eligible; quiet: true; onClicked: {beforeText.text=row.modelData.copy_before;afterText.text=row.modelData.copy_after;comparison.open()} }
                }
            }
        }
        Check { id: confirmed; objectName: "confirmTemplateMigration"; text: "Проверены выбранные записи, значения, фразы и сообщения до / после"; enabled: dialog.selected.length>0 && !!dialog.preview }
        ActionButton { objectName: "applyTemplateMigration"; text: "Создать резервную копию и применить ("+dialog.selected.length+")"; primary: true; Layout.fillWidth: true; enabled: confirmed.checked && dialog.selected.length>0 && !!dialog.preview; onClicked: {if(dialog.shell.run("apply_template_migration",{token:dialog.preview.token,selected:dialog.selected,confirmed:true})){dialog.selected=[];confirmed.checked=false}} }
        Label { visible: !!shell.state.templateMigrationResult; text: shell.state.templateMigrationResult ? "Резервная копия: "+shell.state.templateMigrationResult.backup : ""; color: Theme.success; font.pixelSize: Theme.smallSize; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText }
    }
    Dialog { id: comparison; parent: Overlay.overlay; anchors.centerIn: parent; width: Math.min(parent.width-Theme.s32,Theme.px(880)); height: Math.min(parent.height-Theme.s32,Theme.px(540)); title: "Точное сообщение до / после"; modal: true; standardButtons: Dialog.Close
        onOpened: standardButton(Dialog.Close).text="Закрыть"
        contentItem: RowLayout {
            ColumnLayout { Layout.fillWidth: true; Layout.fillHeight: true
                Label { text: "До"; color: Theme.text }
                ScrollView { Layout.fillWidth: true; Layout.fillHeight: true; contentWidth: availableWidth
                    Area { id: beforeText; readOnly: true; textFormat: TextEdit.PlainText }
                }
            }
            ColumnLayout { Layout.fillWidth: true; Layout.fillHeight: true
                Label { text: "После"; color: Theme.text }
                ScrollView { Layout.fillWidth: true; Layout.fillHeight: true; contentWidth: availableWidth
                    Area { id: afterText; readOnly: true; textFormat: TextEdit.PlainText }
                }
            }
        }
    }
}
