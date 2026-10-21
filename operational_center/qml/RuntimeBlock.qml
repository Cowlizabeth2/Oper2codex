import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

Rectangle {
    id: card
    required property var shell
    required property var block
    radius: Theme.radius
    color: Theme.panel
    border.color: Theme.border
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 15
        spacing: 10
        Label { text: card.block.title; color: Theme.text; font.bold: true; font.pixelSize: 18; elide: Text.ElideRight; Layout.fillWidth: true }
        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: card.block.type === "text" ? textBlock : card.block.type === "contacts" ? contactsBlock : card.block.type === "documents" ? documentsBlock : referenceBlock
        }
    }
    Component {
        id: textBlock
        ColumnLayout {
            id: textContent
            spacing: 8
            property string output: card.block.preview
            property string errors: card.block.validation
            Connections {
                target: backend
                function onContentChanged(eventId, blockId, text, validation) {
                    if (card.shell.state.event && eventId === card.shell.state.event.id && blockId === card.block.id) {
                        textContent.output = text
                        textContent.errors = validation
                    }
                }
            }
            ScrollView {
                id: textScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                clip: true
                ColumnLayout {
                    width: textScroll.availableWidth
                    spacing: 10
                    Repeater {
                        model: card.block.fields
                        delegate: ColumnLayout {
                            id: fieldRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 4
                            Label { text: (fieldRow.modelData.label || "Поле") + (fieldRow.modelData.required ? " *" : ""); color: Theme.muted; font.pixelSize: Theme.smallSize }
                            Loader {
                                Layout.fillWidth: true
                                sourceComponent: fieldRow.modelData.multiline ? multilineInput : singleInput
                            }
                            Component {
                                id: singleInput
                                Input {
                                    text: card.block.runtime.values[fieldRow.modelData.id] || ""
                                    placeholderText: fieldRow.modelData.placeholder || ""
                                    onTextEdited: backend.setValue(card.block.id, fieldRow.modelData.id, text)
                                }
                            }
                            Component {
                                id: multilineInput
                                Area {
                                    text: card.block.runtime.values[fieldRow.modelData.id] || ""
                                    placeholderText: fieldRow.modelData.placeholder || ""
                                    implicitHeight: 80
                                    onTextChanged: if (activeFocus) backend.setValue(card.block.id, fieldRow.modelData.id, text)
                                }
                            }
                            ComboBox {
                                visible: fieldRow.modelData.phrases && fieldRow.modelData.phrases.length > 0
                                Layout.fillWidth: true
                                model: ["Готовые фразы…"].concat(fieldRow.modelData.phrases || [])
                                onActivated: if (currentIndex > 0) card.shell.run("phrase", {id:card.block.id, field:fieldRow.modelData.id, phrase:currentText})
                            }
                        }
                    }
                    Label { text: "ИТОГОВОЕ СООБЩЕНИЕ"; color: Theme.muted; font.pixelSize: Theme.smallSize; Layout.topMargin: 4 }
                    Area { text: textContent.output; readOnly: true; Layout.fillWidth: true; implicitHeight: Math.max(95, contentHeight + 24) }
                    Label { text: textContent.errors; visible: text.length > 0; color: Theme.warning; wrapMode: Text.Wrap; Layout.fillWidth: true }
                }
            }
            ActionButton { text: "Копировать весь текст"; primary: true; Layout.fillWidth: true; onClicked: card.shell.run("copy_text", {id:card.block.id}) }
        }
    }
    Component {
        id: contactsBlock
        ColumnLayout {
            spacing: 8
            Input { id: contactSearch; Layout.fillWidth: true; placeholderText: "Найти по ФИО, телефону, должности" }
            Label { text: card.block.warning || ""; visible: text.length > 0; color: Theme.warning; wrapMode: Text.Wrap; Layout.fillWidth: true }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 10
                model: card.block.contacts.filter(function(c) { return (c.name + " " + c.phone + " " + c.role).toLowerCase().indexOf(contactSearch.text.toLowerCase()) !== -1 })
                ScrollBar.vertical: ScrollBar {}
                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width - 12
                    height: contactColumn.implicitHeight + 20
                    radius: Theme.radius
                    color: Theme.card
                    ColumnLayout {
                        id: contactColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 5
                        Label { text: modelData.name; color: Theme.text; font.bold: true; wrapMode: Text.Wrap; Layout.fillWidth: true }
                        Label { text: modelData.role; visible: text.length > 0; color: Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
                        RowLayout {
                            Label { text: modelData.phone; color: Theme.accent; Layout.fillWidth: true }
                            ActionButton { text: "Копировать"; onClicked: card.shell.run("copy_phone", {phone:modelData.phone}) }
                        }
                        Label { text: modelData.actions.join(" · "); visible: text.length > 0; color: Theme.success; wrapMode: Text.Wrap; Layout.fillWidth: true }
                        Label { text: modelData.comment; visible: text.length > 0; color: Theme.text; wrapMode: Text.Wrap; Layout.fillWidth: true }
                        Label { text: [modelData.priority, modelData.deadline].filter(function(t) { return t }).join(" · "); visible: text.length > 0; color: Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    }
                }
                Label { anchors.centerIn: parent; visible: parent.count === 0; text: "Контакты по тегу не найдены"; color: Theme.muted }
            }
            ActionButton { text: "Обновить из Excel"; Layout.fillWidth: true; onClicked: card.shell.run("refresh_contacts", {id:card.block.id}) }
        }
    }
    Component {
        id: documentsBlock
        ColumnLayout {
            spacing: 8
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 8
                model: card.block.files
                ScrollBar.vertical: ScrollBar {}
                delegate: ColumnLayout {
                    required property var modelData
                    width: ListView.view.width - 12
                    spacing: 5
                    Label { text: modelData.name; color: Theme.text; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Label { text: modelData.status === "ready" ? "Рабочая копия сохранена" : modelData.error || "Копирование прервано"; color: modelData.status === "ready" ? Theme.success : Theme.warning; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    ActionButton { text: "Открыть рабочую копию"; enabled: modelData.status === "ready"; onClicked: card.shell.run("open_document", {id:card.block.id, path:modelData.path}) }
                    ActionButton {
                        text: "Восстановить из оригинала…"
                        visible: modelData.status !== "ready" && !!modelData.source
                        onClicked: card.shell.confirm("Восстановить эту копию из оригинала? Отсутствующий изменённый документ восстановится только из вашей отдельной резервной копии. Существующий файл не будет перезаписан.", function() { card.shell.run("repair_document", {id:card.block.id, path:modelData.path}) })
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; Layout.topMargin: 4 }
                }
                Label { anchors.centerIn: parent; visible: parent.count === 0; text: "Нет настроенных файлов"; color: Theme.muted }
            }
            ActionButton { text: "Открыть папку рабочих файлов"; enabled: !!card.block.runtime.folder; Layout.fillWidth: true; onClicked: card.shell.run("open_folder", {path:card.block.runtime.folder}) }
        }
    }
    Component {
        id: referenceBlock
        ColumnLayout {
            id: references
            spacing: 8
            property var selection: card.block.runtime.selected || []
            property int anchorIndex: -1
            property var filtered: card.block.files.filter(function(f) { return f.name.toLowerCase().indexOf(fileSearch.text.toLowerCase()) !== -1 })
            Input { id: fileSearch; Layout.fillWidth: true; placeholderText: "Найти файл" }
            Label { text: card.block.warning || ""; visible: text.length > 0; color: Theme.warning; wrapMode: Text.Wrap; Layout.fillWidth: true }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 5
                model: references.filtered
                ScrollBar.vertical: ScrollBar {}
                delegate: Rectangle {
                    id: referenceRow
                    required property var modelData
                    required property int index
                    width: ListView.view.width - 12
                    height: 55
                    radius: Theme.radius
                    color: references.selection.indexOf(modelData.source) >= 0 ? Theme.card : Theme.panel
                    border.color: references.selection.indexOf(modelData.source) >= 0 ? Theme.accent : Theme.border
                    Label { anchors.fill: parent; anchors.margins: 10; text: referenceRow.modelData.name; verticalAlignment: Text.AlignVCenter; elide: Text.ElideMiddle; color: Theme.text }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: function(mouse) {
                            var selected = references.selection.slice()
                            if ((mouse.modifiers & Qt.ShiftModifier) && references.anchorIndex >= 0) {
                                selected = []
                                for (var n = Math.min(references.anchorIndex, referenceRow.index); n <= Math.max(references.anchorIndex, referenceRow.index); ++n) selected.push(references.filtered[n].source)
                            } else if (mouse.modifiers & Qt.ControlModifier) {
                                var at = selected.indexOf(referenceRow.modelData.source)
                                if (at >= 0) selected.splice(at, 1); else selected.push(referenceRow.modelData.source)
                                references.anchorIndex = referenceRow.index
                            } else {
                                selected = [referenceRow.modelData.source]
                                references.anchorIndex = referenceRow.index
                            }
                            references.selection = selected
                            backend.selectFiles(card.block.id, JSON.stringify(selected))
                        }
                        onDoubleClicked: card.shell.run("preview", {id:card.block.id, path:referenceRow.modelData.source})
                    }
                }
            }
            Label { text: "Выбрано: " + references.selection.length + " · Ctrl / Shift"; color: Theme.muted; font.pixelSize: Theme.smallSize }
            RowLayout {
                Layout.fillWidth: true
                ActionButton { text: "Просмотреть"; Layout.fillWidth: true; enabled: references.selection.length > 0; onClicked: card.shell.run("preview", {id:card.block.id, path:references.selection[0]}) }
                ActionButton { text: "Папка"; enabled: references.selection.length > 0; onClicked: card.shell.run("open_parent", {path:references.selection[0]}) }
            }
            ActionButton { text: "Копировать файлы"; primary: true; Layout.fillWidth: true; enabled: references.selection.length > 0; onClicked: card.shell.run("copy_files", {id:card.block.id}) }
        }
    }
}
