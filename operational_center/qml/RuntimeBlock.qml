import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."
Rectangle {
    id: card
    required property var shell
    required property var block
    objectName: "runtimeBlock-"+block.id
    radius: Theme.radius; color: Theme.panel; border.color: Theme.border
    ColumnLayout {
        anchors.fill: parent; anchors.margins: Theme.s12; spacing: Theme.s8
        RowLayout { Layout.fillWidth: true
            Icon { name: card.block.type; tint: card.block.accent || Theme.accent }
            Label { text: card.block.title; color: Theme.text; font.bold: true; font.pixelSize: Theme.fontSize; Layout.fillWidth: true; elide: Text.ElideRight }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
        Loader { Layout.fillWidth: true; Layout.fillHeight: true; sourceComponent: card.block.type==="static_text" ? staticBlock : card.block.type==="text" ? textBlock : card.block.type==="contacts" ? contactsBlock : card.block.type==="documents" ? documentsBlock : referenceBlock }
    }
    Component { id: staticBlock
        ColumnLayout {
            ScrollView { Layout.fillWidth: true; Layout.fillHeight: true; contentWidth: availableWidth; clip: true
                Label { objectName: "staticDisplay-"+card.block.id; width: parent.width; text: card.block.config.format==="markdown" ? card.block.static.html : card.block.config.text; textFormat: card.block.config.format==="markdown" ? Text.RichText : Text.PlainText; wrapMode: Text.Wrap; color: Theme.text; font.pixelSize: Theme.px(card.block.config.font_size || 13); horizontalAlignment: card.block.config.alignment==="center" ? Text.AlignHCenter : card.block.config.alignment==="right" ? Text.AlignRight : Text.AlignLeft }
            }
            ActionButton { objectName: "copyStatic-"+card.block.id; text: "Копировать текст"; iconName: "copy"; visible: card.block.config.copy_enabled!==false; Layout.fillWidth: true; onClicked: card.shell.run("copy_static",{id:card.block.id}) }
        }
    }
    Component { id: textBlock; InlineMessage { shell: card.shell; block: card.block } }
    Component {
        id: contactsBlock
        ColumnLayout {
            spacing: Theme.s8
            RowLayout { Layout.fillWidth: true
                Input { id: contactSearch; Layout.fillWidth: true; placeholderText: "ФИО, телефон, должность" }
                ActionButton { iconName: "redo"; quiet: true; tip: "Обновить из Excel"; onClicked: card.shell.run("refresh_contacts",{id:card.block.id}) }
            }
            Label { text: card.block.warning || ""; visible: text.length>0; color: Theme.warning; font.pixelSize: Theme.smallSize; Layout.fillWidth: true; wrapMode: Text.Wrap }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                model: card.block.contacts.filter(function(c) { return (c.name+" "+c.phone+" "+c.role).toLowerCase().indexOf(contactSearch.text.toLowerCase())>=0 })
                ScrollBar.vertical: ScrollBar {}
                delegate: Rectangle {
                    id: contact
                    required property var modelData
                    width: ListView.view.width; height: Math.max(Theme.row,info.implicitHeight+Theme.s12)
                    color: hover.hovered ? Theme.card : "transparent"
                    HoverHandler { id: hover }
                    ColumnLayout { id: info; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.topMargin: Theme.s4; spacing: Theme.s4
                        RowLayout { Layout.fillWidth: true; spacing: Theme.s8
                            Label { text: contact.modelData.name; color: Theme.text; font.bold: true; font.pixelSize: Theme.fontSize; Layout.fillWidth: true; elide: Text.ElideRight }
                            Label { text: contact.modelData.phone; color: Theme.accent; font.pixelSize: Theme.fontSize }
                            ActionButton { iconName: "copy"; quiet: true; tip: "Копировать номер"; onClicked: card.shell.run("copy_phone",{phone:contact.modelData.phone}) }
                        }
                        Label { visible: text.length>0; text: [contact.modelData.role,contact.modelData.actions.join(" · ")].filter(function(s) { return s }).join("  /  "); color: Theme.muted; font.pixelSize: Theme.smallSize; Layout.fillWidth: true; wrapMode: Text.Wrap }
                        Label { visible: text.length>0; text: [contact.modelData.comment,contact.modelData.priority,contact.modelData.deadline].filter(function(s) { return s }).join(" · "); color: Theme.muted; font.pixelSize: Theme.smallSize; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border }
                }
                Label { anchors.centerIn: parent; visible: parent.count===0; text: "Контакты не найдены"; color: Theme.muted; font.pixelSize: Theme.fontSize }
            }
        }
    }
    Component {
        id: documentsBlock
        ColumnLayout {
            spacing: Theme.s8
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                model: card.block.files
                ScrollBar.vertical: ScrollBar {}
                delegate: ColumnLayout {
                    id: doc
                    required property var modelData
                    width: ListView.view.width; spacing: Theme.s4
                    RowLayout { Layout.fillWidth: true; spacing: Theme.s8
                        Icon { name: "documents"; tint: doc.modelData.status==="ready" ? Theme.muted : Theme.warning }
                        ColumnLayout { Layout.fillWidth: true; spacing: Theme.s4
                            Label { text: doc.modelData.name; color: Theme.text; font.pixelSize: Theme.fontSize; Layout.fillWidth: true; elide: Text.ElideMiddle }
                            Label { text: doc.modelData.status==="ready" ? "Рабочая копия" : doc.modelData.error || "Копирование прервано"; color: doc.modelData.status==="ready" ? Theme.muted : Theme.warning; font.pixelSize: Theme.smallSize; Layout.fillWidth: true; wrapMode: Text.Wrap }
                        }
                        ActionButton { iconName: "arrow"; quiet: true; tip: "Открыть рабочую копию"; enabled: doc.modelData.status==="ready"; onClicked: card.shell.run("open_document",{id:card.block.id,path:doc.modelData.path}) }
                    }
                    ActionButton { text: "Восстановить из оригинала…"; quiet: true; visible: doc.modelData.status!=="ready" && !!doc.modelData.source; onClicked: card.shell.confirm("Создать отсутствующую копию из оригинала? Прежние правки не восстановятся; существующие файлы не перезаписываются.",function() { card.shell.run("repair_document",{id:card.block.id,path:doc.modelData.path}) }) }
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; Layout.topMargin: Theme.s4; Layout.bottomMargin: Theme.s4 }
                }
                Label { anchors.centerIn: parent; visible: parent.count===0; text: "Нет настроенных документов"; color: Theme.muted; font.pixelSize: Theme.fontSize }
            }
            ActionButton { text: "Рабочая папка"; iconName: "reference"; Layout.fillWidth: true; enabled: !!card.block.runtime.folder; onClicked: card.shell.run("open_folder",{path:card.block.runtime.folder}) }
        }
    }
    Component {
        id: referenceBlock
        ColumnLayout {
            id: references
            spacing: Theme.s8
            property var selection: card.block.runtime.selected || []
            property int anchorIndex: -1
            property var filtered: card.block.files.filter(function(f) { return f.name.toLowerCase().indexOf(search.text.toLowerCase())>=0 })
            function choose(index,mods) {
                var selected=selection.slice(),path=filtered[index].source
                if((mods&Qt.ShiftModifier) && anchorIndex>=0) { selected=[];for(var n=Math.min(anchorIndex,index);n<=Math.max(anchorIndex,index);++n) selected.push(filtered[n].source) }
                else if(mods&Qt.ControlModifier) { var at=selected.indexOf(path);if(at>=0) selected.splice(at,1);else selected.push(path);anchorIndex=index }
                else { selected=[path];anchorIndex=index }
                selection=selected;backend.selectFiles(card.block.id,JSON.stringify(selected))
            }
            Input { id: search; Layout.fillWidth: true; placeholderText: "Найти файл"; onTextEdited: references.anchorIndex=-1 }
            Label { text: card.block.warning || ""; visible: text.length>0; color: Theme.warning; font.pixelSize: Theme.smallSize; Layout.fillWidth: true; wrapMode: Text.Wrap }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                model: references.filtered
                ScrollBar.vertical: ScrollBar {}
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: ListView.view.width; height: Theme.row
                    radius: Theme.s4; color: references.selection.indexOf(modelData.source)>=0 ? Theme.card : "transparent"
                    MouseArea { anchors.fill: parent; onClicked: function(mouse) { references.choose(row.index,mouse.modifiers) } onDoubleClicked: card.shell.run("preview",{id:card.block.id,path:row.modelData.source}) }
                    RowLayout { anchors.fill: parent; spacing: Theme.s8
                        Icon { name: row.modelData.name.toLowerCase().endsWith(".xlsx") ? "contacts" : row.modelData.name.toLowerCase().endsWith(".docx") ? "documents" : row.modelData.name.toLowerCase().endsWith(".txt") ? "text" : "file" }
                        Label { text: row.modelData.name; color: Theme.text; font.pixelSize: Theme.fontSize; Layout.fillWidth: true; elide: Text.ElideMiddle }
                        ActionButton { iconName: "arrow"; quiet: true; tip: "Открыть безопасную копию"; onClicked: card.shell.run("preview",{id:card.block.id,path:row.modelData.source}) }
                        ActionButton { iconName: "reference"; quiet: true; tip: "Расположение файла"; onClicked: card.shell.run("open_parent",{path:row.modelData.source}) }
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border }
                }
            }
            RowLayout { Layout.fillWidth: true
                Label { text: references.selection.length+" выбрано · Ctrl / Shift"; color: Theme.muted; font.pixelSize: Theme.smallSize; Layout.fillWidth: true }
                ActionButton { text: "Копировать файлы"; iconName: "copy"; primary: true; enabled: references.selection.length>0; onClicked: card.shell.run("copy_files",{id:card.block.id}) }
            }
        }
    }
}
