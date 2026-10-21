import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."

ColumnLayout {
    id: view
    required property var shell
    property bool linkMode: false
    property bool snapping: true
    spacing: 10
    RowLayout {
        Layout.fillWidth: true
        ComboBox {
            id: masterChoice
            Layout.preferredWidth: 200
            model: shell.state.draft.masters
            textRole: "name"
            currentIndex: shell.state.master ? shell.state.draft.masters.findIndex(function(m) { return m.id === shell.state.master.id }) : -1
            onActivated: shell.run("select_master", {id:model[currentIndex].id})
        }
        ActionButton { text: "+ Мастер"; onClicked: shell.run("new_master") }
        ActionButton { text: "Копия мастера"; enabled: !!shell.state.master; onClicked: shell.run("duplicate_master") }
        Item { Layout.fillWidth: true }
        ActionButton { text: "↶"; enabled: shell.state.canUndo; onClicked: shell.run("undo"); ToolTip.visible: hovered; ToolTip.text: "Отменить" }
        ActionButton { text: "↷"; enabled: shell.state.canRedo; onClicked: shell.run("redo"); ToolTip.visible: hovered; ToolTip.text: "Повторить" }
        ActionButton { text: "Опубликовать"; primary: true; onClicked: shell.confirm("Опубликовать черновик? Новые происшествия получат новые настройки. Уже созданные сохранят прежние.", function() { shell.run("publish") }) }
    }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: [{type:"text", name:"+ Шаблон"}, {type:"contacts", name:"+ Контакты"}, {type:"documents", name:"+ Документы"}, {type:"reference", name:"+ Файлы"}]
            ActionButton { required property var modelData; text: modelData.name; enabled: !!shell.state.master; onClicked: shell.run("add_block", {type:modelData.type}) }
        }
        ActionButton { text: view.linkMode ? "Стрелки: включены" : "Редактор связей"; primary: view.linkMode; onClicked: { view.linkMode = !view.linkMode; arrows.requestPaint() } }
        ActionButton { text: view.snapping ? "Сетка: 20" : "Без привязки"; onClicked: view.snapping = !view.snapping }
        ComboBox { model: ["100%", "110%", "125%", "150%"]; currentIndex: [1,1.1,1.25,1.5].indexOf(shell.state.scale); onActivated: shell.run("scale", {value:[1,1.1,1.25,1.5][currentIndex]}) }
    }
    Label { text: view.linkMode ? "Нажмите «Связать / Отвязать» на нужном узле. Стрелки означают одновременную активацию, а не порядок выполнения." : "Перемещайте блоки за шапку, меняйте размер за нижний правый угол. Черновик сохраняется автоматически; рабочая конфигурация меняется после публикации."; color: Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true; font.pixelSize: Theme.smallSize }
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 12
        ScrollView {
            id: viewport
            objectName: "builderViewport"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: stage.width * shell.state.scale
            contentHeight: stage.height * shell.state.scale
            background: Rectangle { color: Theme.background; radius: Theme.radius; border.color: Theme.border }
            Item {
                id: stage
                width: shell.state.master ? shell.state.master.blocks.reduce(function(acc,b) { return Math.max(acc,b.x+b.width+300) }, 1800) : 1800
                height: shell.state.master ? shell.state.master.blocks.reduce(function(acc,b) { return Math.max(acc,b.y+b.height+300) }, 1200) : 1200
                scale: shell.state.scale
                transformOrigin: Item.TopLeft
                Canvas {
                    id: grid
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0,0,width,height)
                        ctx.fillStyle = Theme.border
                        for (var x = 20; x < width; x += 20) for (var y = 20; y < height; y += 20) ctx.fillRect(x,y,1,1)
                    }
                    Connections { target: Theme; function onTokensChanged() { grid.requestPaint(); arrows.requestPaint() } }
                }
                Canvas {
                    id: arrows
                    anchors.fill: parent
                    visible: view.linkMode
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0,0,width,height)
                        if (!shell.state.master) return
                        ctx.strokeStyle = Theme.accent
                        ctx.fillStyle = Theme.accent
                        ctx.lineWidth = 2
                        for (var i = 0; i < tiles.count; ++i) {
                            var tile = tiles.itemAt(i)
                            if (!tile || shell.state.master.links.indexOf(tile.modelData.id) < 0) continue
                            var sx = 210, sy = 110, ex = tile.x, ey = tile.y + 24
                            ctx.beginPath(); ctx.moveTo(sx,sy); ctx.bezierCurveTo(sx+65,sy,ex-65,ey,ex,ey); ctx.stroke()
                            ctx.beginPath(); ctx.moveTo(ex,ey); ctx.lineTo(ex-12,ey-6); ctx.lineTo(ex-12,ey+6); ctx.closePath(); ctx.fill()
                        }
                    }
                    Connections { target: backend; function onStateChanged() { arrows.requestPaint() } }
                }
                Rectangle {
                    x: 24; y: 60; width: 186; height: 100
                    visible: !!shell.state.master
                    radius: Theme.radius
                    color: Theme.card
                    border.color: Theme.accent
                    Column {
                        anchors.fill: parent; anchors.margins: 12; spacing: 8
                        Label { text: "МАСТЕР"; color: Theme.accent; font.pixelSize: Theme.smallSize }
                        Label { text: shell.state.master ? shell.state.master.name : ""; width: parent.width; elide: Text.ElideRight; color: Theme.text; font.bold: true }
                        Label { text: "Все связи → одновременно"; color: Theme.muted; font.pixelSize: 10 }
                    }
                    MouseArea { anchors.fill: parent; onClicked: shell.run("select_block", {id:""}) }
                }
                Repeater {
                    id: tiles
                    model: shell.state.master ? shell.state.master.blocks : []
                    delegate: Rectangle {
                        id: tile
                        required property var modelData
                        objectName: "builderTile-" + modelData.id
                        x: modelData.x; y: modelData.y; width: modelData.width; height: modelData.height
                        radius: Theme.radius
                        color: Theme.panel
                        border.width: shell.state.selectedBlock && shell.state.selectedBlock.id === modelData.id ? 2 : 1
                        border.color: shell.state.selectedBlock && shell.state.selectedBlock.id === modelData.id ? Theme.accent : Theme.border
                        onXChanged: arrows.requestPaint()
                        onYChanged: arrows.requestPaint()
                        function saveGeometry() {
                            if (view.snapping) { x = Math.round(x/20)*20; y = Math.round(y/20)*20; width = Math.round(width/20)*20; height = Math.round(height/20)*20 }
                            shell.run("geometry", {id:modelData.id, x:x, y:y, width:width, height:height})
                        }
                        Rectangle {
                            width: parent.width; height: 48; radius: Theme.radius; color: Theme.card
                            Label { anchors.fill: parent; anchors.margins: 14; text: tile.modelData.title + "  ⠿"; color: Theme.text; elide: Text.ElideRight; font.bold: true }
                            MouseArea {
                                objectName: "dragHandle-" + tile.modelData.id
                                preventStealing: true
                                anchors.fill: parent
                                cursorShape: Qt.SizeAllCursor
                                drag.target: tile
                                drag.minimumX: 230
                                drag.minimumY: 0
                                onReleased: tile.saveGeometry()
                            }
                        }
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 16; anchors.topMargin: 66; spacing: 10
                            Label { text: ({text:"Текстовое сообщение", contacts:"Контакты Excel", documents:"Рабочие копии документов", reference:"Справочные файлы"})[tile.modelData.type]; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
                            Label { text: shell.state.master && shell.state.master.links.indexOf(tile.modelData.id) >= 0 ? "● Активируется мастер-кнопкой" : "○ Не связан"; color: shell.state.master && shell.state.master.links.indexOf(tile.modelData.id) >= 0 ? Theme.success : Theme.warning; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            Label { text: "Положение и размер сохраняются в логических координатах. Настройте содержимое в панели справа."; color: Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            Item { Layout.fillHeight: true }
                            ActionButton { text: "Настроить блок"; onClicked: shell.run("select_block", {id:tile.modelData.id}) }
                            ActionButton { visible: view.linkMode; text: shell.state.master && shell.state.master.links.indexOf(tile.modelData.id) >= 0 ? "Отвязать ←" : "Связать →"; onClicked: shell.run("toggle_link", {id:tile.modelData.id}) }
                        }
                        Rectangle {
                            anchors.right: parent.right; anchors.bottom: parent.bottom; width: 24; height: 24; radius: 4; color: Theme.border
                            Label { anchors.centerIn: parent; text: "◢"; color: Theme.accent }
                            MouseArea {
                                objectName: "resizeHandle-" + tile.modelData.id
                                preventStealing: true
                                anchors.fill: parent
                                cursorShape: Qt.SizeFDiagCursor
                                property point start
                                property real initialWidth
                                property real initialHeight
                                onPressed: function(mouse) { start = mapToItem(stage, mouse.x, mouse.y); initialWidth = tile.width; initialHeight = tile.height }
                                onPositionChanged: function(mouse) { if (pressed) { var p = mapToItem(stage,mouse.x,mouse.y); tile.width = Math.max(320,initialWidth+p.x-start.x); tile.height = Math.max(260,initialHeight+p.y-start.y) } }
                                onReleased: tile.saveGeometry()
                            }
                        }
                    }
                }
            }
        }
        ScrollView {
            id: properties
            Layout.preferredWidth: 370
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true
            Loader {
                width: properties.availableWidth
                sourceComponent: shell.state.selectedBlock ? blockProperties : masterProperties
            }
        }
    }
    Component { id: blockProperties; BlockEditor { shell: view.shell } }
    Component {
        id: masterProperties
        ColumnLayout {
            spacing: 12
            visible: !!shell.state.master
            Label { text: "Мастер-блок"; color: Theme.text; font.pixelSize: 20; font.bold: true }
            Label { text: "Название"; color: Theme.muted }
            Input { id: masterName; Layout.fillWidth: true; text: shell.state.master ? shell.state.master.name : "" }
            Label { text: "Системный тег (не зависит от названия)"; color: Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
            Input { id: masterTag; Layout.fillWidth: true; text: shell.state.master ? shell.state.master.tag : "" }
            Label { text: "Значок"; color: Theme.muted }
            Input { id: masterIcon; Layout.fillWidth: true; text: shell.state.master ? shell.state.master.icon : "!" }
            Label { text: "Цвет (#RRGGBB)"; color: Theme.muted }
            Input { id: masterColor; Layout.fillWidth: true; text: shell.state.master ? shell.state.master.color : "" }
            ActionButton { text: "Сохранить мастер"; primary: true; Layout.fillWidth: true; onClicked: shell.run("save_master", {name:masterName.text, tag:masterTag.text, icon:masterIcon.text, color:masterColor.text}) }
            Label { text: shell.state.master ? "UUID: " + shell.state.master.id : ""; color: Theme.muted; font.pixelSize: Theme.smallSize; wrapMode: Text.Wrap; Layout.fillWidth: true }
            ActionButton { text: "Удалить мастер…"; danger: true; Layout.fillWidth: true; onClicked: shell.confirm("Удалить мастер-блок и его блоки из черновика? Существующие происшествия сохранятся.", function() { shell.run("delete_master") }) }
        }
    }
}
