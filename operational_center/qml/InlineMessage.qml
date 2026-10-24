import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

ColumnLayout {
    id: message
    required property var shell
    required property var block
    property string validation: block.validation || ""
    spacing: Theme.s8
    Connections {
        target: backend
        function onContentChanged(eventId, blockId, text, errors) {
            if (message.shell.state.event && eventId === message.shell.state.event.id && blockId === message.block.id) message.validation = errors
        }
    }
    ScrollView {
        id: scroll
        objectName: "inlineMessageScroll"
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: availableWidth
        clip: true
        Column {
            width: scroll.availableWidth
            spacing: Theme.s8
            Flow {
                id: flow
                objectName: "inlineMessageFlow"
                width: parent.width
                spacing: 0
                Repeater {
                    model: message.block.tokens || []
                    delegate: Loader {
                        id: entry
                        required property var modelData
                        sourceComponent: modelData.token === "static" ? literal : modelData.token === "break" ? lineBreak : fieldInput
                        Component {
                            id: literal
                            Text {
                                objectName: "protectedLiteral"
                                text: entry.modelData.text
                                textFormat: Text.PlainText
                                font.pixelSize: Theme.fontSize
                                color: Theme.text
                                width: Math.min(implicitWidth, flow.width)
                                height: Math.max(Theme.control, implicitHeight)
                                wrapMode: Text.WrapAnywhere
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                        Component {
                            id: lineBreak
                            Item { width: flow.width; height: entry.modelData.blank ? Theme.control : 1 }
                        }
                        Component {
                            id: fieldInput
                            Row {
                                id: fieldRow
                                property var definition: entry.modelData
                                property string value: message.block.runtime.values[definition.id] !== undefined ? String(message.block.runtime.values[definition.id]) : (definition.default || "")
                                property bool hasPhrases: (definition.phrases || []).length > 0
                                spacing: Theme.s4
                                width: Math.min(flow.width, definition.multiline ? Theme.fieldWide : Math.max(Theme.fieldWidth, Math.min(Theme.fieldWide, metrics.advanceWidth(value || definition.placeholder || definition.label || "") + Theme.s32 + (hasPhrases ? Theme.control : 0))))
                                height: inputLoader.height
                                FontMetrics { id: metrics; font.pixelSize: Theme.fontSize }
                                Connections {
                                    target: backend
                                    function onValueChanged(eventId, blockId, fieldId, value) {
                                        if (message.shell.state.event && eventId === message.shell.state.event.id && blockId === message.block.id && fieldId === fieldRow.definition.id) fieldRow.value = value
                                    }
                                }
                                Loader {
                                    id: inputLoader
                                    width: fieldRow.width - (fieldRow.hasPhrases ? Theme.control + Theme.s4 : 0)
                                    sourceComponent: fieldRow.definition.multiline ? multi : single
                                }
                                Component {
                                    id: single
                                    Input {
                                        objectName: "inlineField-" + fieldRow.definition.id
                                        text: fieldRow.value
                                        placeholderText: fieldRow.definition.placeholder || fieldRow.definition.label || ""
                                        onTextEdited: backend.setValue(message.block.id, fieldRow.definition.id, text)
                                        ToolTip.visible: hovered
                                        ToolTip.text: (fieldRow.definition.label || "") + (fieldRow.definition.required ? " · Обязательное" : "")
                                    }
                                }
                                Component {
                                    id: multi
                                    ScrollView {
                                        implicitHeight: Math.min(Theme.fieldMaxHeight, Math.max(Theme.control, multiArea.contentHeight + Theme.s16))
                                        contentWidth: availableWidth
                                        clip: true
                                        Area {
                                            id: multiArea
                                            objectName: "inlineField-" + fieldRow.definition.id
                                            text: fieldRow.value
                                            placeholderText: fieldRow.definition.placeholder || fieldRow.definition.label || ""
                                            onTextChanged: if (activeFocus && text !== fieldRow.value) backend.setValue(message.block.id, fieldRow.definition.id, text)
                                        }
                                    }
                                }
                                ActionButton {
                                    objectName: "presetButton-" + fieldRow.definition.id
                                    visible: fieldRow.hasPhrases
                                    width: Theme.control
                                    height: Theme.control
                                    iconName: "chevron"
                                    tip: "Готовые фразы"
                                    onClicked: phrases.open()
                                    Menu {
                                        id: phrases
                                        popupType: Popup.Item
                                        width: Theme.fieldWidth + Theme.s32
                                        padding: Theme.s4
                                        y: parent.height + Theme.s4
                                        background: Rectangle { color: Theme.panel; border.color: Theme.border; radius: Theme.radius }
                                        Repeater {
                                            model: fieldRow.definition.phrases || []
                                            MenuItem {
                                                id: phraseOption
                                                required property string modelData
                                                required property int index
                                                objectName: "presetChoice-"+fieldRow.definition.id+"-"+index
                                                width: phrases.width-Theme.s8
                                                implicitHeight: Theme.control
                                                text: modelData
                                                font.pixelSize: Theme.fontSize
                                                palette.text: Theme.text
                                                contentItem: Text { text: phraseOption.text; color: Theme.text; font.pixelSize: Theme.fontSize; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                                background: Rectangle { radius: Theme.s4; color: phraseOption.highlighted || phraseOption.hovered ? Theme.card : "transparent" }
                                                onTriggered: message.shell.run("phrase", {id:message.block.id, field:fieldRow.definition.id, phrase:modelData})
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Text { width: parent.width; visible: message.validation.length > 0; text: message.validation; color: Theme.warning; font.pixelSize: Theme.smallSize; wrapMode: Text.Wrap }
        }
    }
    ActionButton { text: "Копировать весь текст"; iconName: "copy"; primary: true; Layout.fillWidth: true; onClicked: message.shell.run("copy_text", {id:message.block.id}) }
}
