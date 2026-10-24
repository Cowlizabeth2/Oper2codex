import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

ColumnLayout {
    id: message
    required property var shell
    required property var block
    property string validation: block.validation || ""
    // Presentation only: preserve the original segments, UUIDs and copy output.
    property var lines: documentLines(block.tokens || [])
    spacing: Theme.s8
    function documentLines(tokens) {
        var rows=[],current=[]
        function append() {
            var fields=current.filter(function(t) {return t.token==="field"}),prefix="",seen=false,suffix=""
            for(var i=0;i<current.length;++i) {
                if(current[i].token==="field") seen=true
                else if(!seen) prefix+=current[i].text
                else suffix+=current[i].text
            }
            rows.push({tokens:current,simple:fields.length===1 && suffix.trim().length===0,prefix:prefix,field:fields.length===1 ? fields[0] : null})
            current=[]
        }
        for(var i=0;i<tokens.length;++i) { if(tokens[i].token==="break") append();else current.push(tokens[i]) }
        append();return rows
    }
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
            id: document
            width: scroll.availableWidth
            spacing: Theme.s8
            property real labelWidth: { var effectiveFont=metrics.font;return Math.min(width*0.42,Theme.s8+Math.max.apply(null,message.lines.map(function(line) {return line.simple ? metrics.advanceWidth(line.prefix) : 0}))) }
            FontMetrics { id: metrics; font: Qt.font({family:message.shell.font.family,pixelSize:Theme.fontSize}) }
            Repeater {
                model: message.lines
                delegate: Loader {
                    id: line
                    required property var modelData
                    width: document.width
                    sourceComponent: modelData.simple ? labeledLine : mixedLine
                    Component {
                        id: labeledLine
                        RowLayout {
                            width: line.width
                            spacing: line.modelData.prefix.length ? Theme.s8 : 0
                            Text {
                                objectName: "protectedLiteral"
                                text: line.modelData.prefix
                                textFormat: Text.PlainText
                                visible: line.modelData.prefix.length>0
                                Layout.preferredWidth: document.labelWidth
                                Layout.minimumWidth: 0
                                Layout.alignment: Qt.AlignTop
                                Layout.preferredHeight: Math.max(Theme.control,implicitHeight)
                                verticalAlignment: Text.AlignVCenter
                                wrapMode: Text.Wrap
                                color: Theme.text
                                font.pixelSize: Theme.fontSize
                            }
                            InlineField {
                                shell: message.shell; block: message.block; definition: line.modelData.field
                                Layout.preferredWidth: Math.min(implicitWidth,Math.max(0,line.width-(line.modelData.prefix.length ? document.labelWidth+Theme.s8 : 0)))
                                Layout.minimumWidth: 0
                                Layout.alignment: Qt.AlignTop
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }
                    Component {
                        id: mixedLine
                        Flow {
                            id: flow
                            objectName: "inlineMessageFlow"
                            width: line.width
                            spacing: 0
                            // Empty source paragraphs retain their own line.
                            height: Math.max(Theme.control,implicitHeight-Theme.s8)
                            Repeater {
                                model: line.modelData.tokens
                                delegate: Item {
                                    id: entry
                                    required property var modelData
                                    width: tokenLoader.width
                                    height: tokenLoader.height+Theme.s8
                                    Loader { id: tokenLoader; sourceComponent: entry.modelData.token==="field" ? inlineValue : literal }
                                    Component {
                                        id: literal
                                        Text {
                                            objectName: "protectedLiteral"
                                            text: entry.modelData.text
                                            textFormat: Text.PlainText
                                            color: Theme.text; font.pixelSize: Theme.fontSize
                                            width: Math.min(implicitWidth,flow.width)
                                            height: Math.max(Theme.control,implicitHeight)
                                            verticalAlignment: Text.AlignVCenter
                                            wrapMode: Text.Wrap
                                        }
                                    }
                                    Component {
                                        id: inlineValue
                                        InlineField {
                                            shell: message.shell; block: message.block; definition: entry.modelData
                                            width: Math.min(implicitWidth,flow.width)
                                            height: implicitHeight
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Text { width: parent.width; visible: message.validation.length>0; text: message.validation; color: Theme.warning; font.pixelSize: Theme.smallSize; wrapMode: Text.Wrap }
        }
    }
    ActionButton { objectName: "copyInlineMessage"; text: "Копировать весь текст"; iconName: "copy"; primary: true; Layout.fillWidth: true; onClicked: message.shell.run("copy_text",{id:message.block.id}) }
}
