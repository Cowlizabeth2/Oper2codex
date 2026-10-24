import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

Item {
    id: fieldRow
    required property var shell
    required property var block
    required property var definition
    property string value: fieldRow.block.runtime.values[definition.id] !== undefined ? String(fieldRow.block.runtime.values[definition.id]) : (definition.default || "")
    property bool hasPhrases: (definition.phrases || []).length > 0
    implicitWidth: (definition.multiline ? Theme.fieldWide : Math.max(Theme.fieldCompact, Math.min(Theme.fieldWide, metrics.advanceWidth + Theme.s24))) + (hasPhrases ? Theme.control + Theme.s4 : 0)
    implicitHeight: inputLoader.height
    TextMetrics { id: metrics; text: fieldRow.value || fieldRow.definition.placeholder || ""; font: Qt.font({family:fieldRow.shell.font.family,pixelSize:Theme.fontSize}) }
    Connections {
        target: backend
        function onValueChanged(eventId, blockId, fieldId, value) {
            if (fieldRow.shell.state.event && eventId === fieldRow.shell.state.event.id && blockId === fieldRow.block.id && fieldId === fieldRow.definition.id) fieldRow.value = value
        }
    }
    Loader {
        id: inputLoader
        width: Math.max(0,fieldRow.width - (fieldRow.hasPhrases ? Theme.control + Theme.s4 : 0))
        sourceComponent: fieldRow.definition.multiline ? multi : single
    }
    Component {
        id: single
        Input {
            objectName: "inlineField-" + fieldRow.definition.id
            text: fieldRow.value
            placeholderText: fieldRow.definition.placeholder || ""
            onTextEdited: backend.setValue(fieldRow.block.id, fieldRow.definition.id, text)
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
                placeholderText: fieldRow.definition.placeholder || ""
                onTextChanged: if (activeFocus && text !== fieldRow.value) backend.setValue(fieldRow.block.id, fieldRow.definition.id, text)
            }
        }
    }
    ActionButton {
        anchors.right: parent.right
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
                    onTriggered: fieldRow.shell.run("phrase", {id:fieldRow.block.id, field:fieldRow.definition.id, phrase:modelData})
                }
            }
        }
    }
}
