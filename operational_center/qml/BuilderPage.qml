import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."
ColumnLayout {
    id: view
    required property var shell
    property bool linkMode: false
    property bool snapping: true
    property bool showPalette: true
    property bool showInspector: true
    property var selectedIds: shell.state.selectedBlock ? [shell.state.selectedBlock.id] : []
    property var dragOrigins: ({})
    property real guideX: -1
    property real guideY: -1
    property bool connecting: false
    property var blocks: shell.state.master ? shell.state.master.blocks : []
    function fitContents() { viewport.fit() }
    spacing: Theme.s8
    function selected(id) { return selectedIds.indexOf(id)>=0 }
    function summary(block) {
        if(block.type==="text") return block.config.segments.filter(function(s) { return s.kind==="field" }).length+" полей"
        if(block.type==="contacts") return block.config.path ? block.config.path.split("\\").join("/").split("/").pop() : "Файл не подключён"
        return block.config.sources.length ? block.config.sources.length+" источников" : "Нет источников"
    }
    function select(id,mods) {
        if(mods&Qt.ControlModifier) { var ids=selectedIds.slice(),i=ids.indexOf(id);if(i>=0) ids.splice(i,1);else ids.push(id);selectedIds=ids }
        else if(!selected(id)) selectedIds=[id]
    }
    function synchronizeSelection(id) { if(id && shell.state.selectedBlock && shell.state.selectedBlock.id===id) return; shell.run("select_block",{id:id || ""}) }
    function tileFor(id) { for(var i=0;i<tiles.count;++i) { var t=tiles.itemAt(i);if(t && t.modelData.id===id) return t };return null }
    function beginDrag(id,mods) {
        select(id,mods)
        var origins={}
        for(var i=0;i<selectedIds.length;++i) { var t=tileFor(selectedIds[i]);if(t) origins[selectedIds[i]]={x:t.x,y:t.y,width:t.width,height:t.height} }
        dragOrigins=origins
    }
    function moveSelection(id,dx,dy) {
        if(!dragOrigins[id]) return
        var leader=dragOrigins[id],nx=Math.max(0,leader.x+dx),ny=Math.max(0,leader.y+dy)
        if(snapping) { nx=Math.round(nx/Theme.grid)*Theme.grid;ny=Math.round(ny/Theme.grid)*Theme.grid }
        guideX=-1;guideY=-1
        for(var i=0;i<tiles.count;++i) {
            var t=tiles.itemAt(i);if(!t || selected(t.modelData.id)) continue
            var xs=[t.x,t.x+t.width/2,t.x+t.width],ys=[t.y,t.y+t.height/2,t.y+t.height]
            for(var j=0;j<3;++j) {
                if(Math.abs(nx-xs[j])<Theme.guideTolerance) { nx=xs[j];guideX=nx }
                if(Math.abs(ny-ys[j])<Theme.guideTolerance) { ny=ys[j];guideY=ny }
                if(Math.abs(nx+leader.width-xs[j])<Theme.guideTolerance) { nx=xs[j]-leader.width;guideX=xs[j] }
                if(Math.abs(ny+leader.height-ys[j])<Theme.guideTolerance) { ny=ys[j]-leader.height;guideY=ys[j] }
                if(Math.abs(nx+leader.width/2-xs[j])<Theme.guideTolerance) { nx=xs[j]-leader.width/2;guideX=xs[j] }
                if(Math.abs(ny+leader.height/2-ys[j])<Theme.guideTolerance) { ny=ys[j]-leader.height/2;guideY=ys[j] }
            }
        }
        dx=nx-leader.x;dy=ny-leader.y
        for(var key in dragOrigins) { var o=dragOrigins[key];dx=Math.max(dx,-o.x);dy=Math.max(dy,-o.y) }
        for(var key2 in dragOrigins) { var tile=tileFor(key2),origin=dragOrigins[key2];if(tile) { tile.x=origin.x+dx;tile.y=origin.y+dy } }
        updateEdges()
    }
    function saveGeometry(id) {
        var items=[]
        for(var i=0;i<selectedIds.length;++i) { var t=tileFor(selectedIds[i]);if(t) items.push({id:t.modelData.id,x:Math.max(0,t.x),y:Math.max(0,t.y),width:Math.max(320,t.width),height:Math.max(260,t.height)}) }
        guideX=-1;guideY=-1
        if(items.length) shell.run("geometry_batch",{items:items})
        else synchronizeSelection(id)
        updateEdges()
    }
    function updateEdges() {
        if(!viewport || !shell.state.master) return
        var edges=[],routeY=24
        for(var n=0;n<tiles.count;++n) { var other=tiles.itemAt(n);if(other) routeY=Math.min(routeY,Math.max(0,other.y-16)) }
        for(var i=0;i<tiles.count;++i) {
            var t=tiles.itemAt(i)
            if(t && shell.state.master.links.indexOf(t.modelData.id)>=0) {
                var sx=24+Theme.masterWidth,sy=40+Theme.masterHeight/2,ex=t.x,ey=t.y+Theme.nodeHeight/2
                edges.push({id:t.modelData.id,sx:sx,sy:sy,ex:ex,ey:ey,points:[{x:sx,y:sy},{x:sx+12,y:sy},{x:sx+12,y:routeY},{x:ex-12,y:routeY},{x:ex-12,y:ey},{x:ex,y:ey}]})
            }
        }
        viewport.edges=edges
    }
    function duplicateSelection() { if(selectedIds.length) shell.run("duplicate_blocks",{ids:selectedIds}) }
    function removeSelection() { if(selectedIds.length) { var ids=selectedIds.slice();shell.confirm("Удалить выбранные блоки и их связи из черновика?",function() { shell.run("delete_blocks",{ids:ids});view.selectedIds=[] }) } }
    Connections { target: backend; function onStateChanged() {
        view.selectedIds=view.selectedIds.filter(function(id) { return view.blocks.some(function(b) { return b.id===id }) })
        var chosen=shell.state.selectedBlock
        if(chosen && view.selectedIds.indexOf(chosen.id)<0) view.selectedIds=[chosen.id]
        Qt.callLater(view.updateEdges)
    } }
    Shortcut { sequence: "Ctrl+D"; enabled: shell.page==="builder" && !shell.editingText; onActivated: view.duplicateSelection() }
    Shortcut { sequences: [StandardKey.Copy]; enabled: shell.page==="builder" && !shell.editingText; onActivated: shell.run("copy_blocks",{ids:view.selectedIds}) }
    Shortcut { sequences: [StandardKey.Paste]; enabled: shell.page==="builder" && !shell.editingText; onActivated: shell.run("paste_blocks") }
    Shortcut { sequence: "Delete"; enabled: shell.page==="builder" && !shell.editingText; onActivated: view.removeSelection() }
    RowLayout {
        Layout.fillWidth: true; spacing: Theme.s8
        Choice { id: masterChoice; Layout.preferredWidth: Theme.px(180); model: shell.state.draft.masters; textRole: "name"; currentIndex: shell.state.master ? shell.state.draft.masters.findIndex(function(m) { return m.id===shell.state.master.id }) : -1; onActivated: { view.selectedIds=[];shell.run("select_master",{id:model[currentIndex].id}) } }
        ActionButton { iconName: "plus"; tip: "Новый мастер"; onClicked: shell.run("new_master") }
        ActionButton { iconName: "undo"; quiet: true; enabled: shell.state.canUndo; tip: "Отменить · Ctrl Z"; onClicked: shell.run("undo") }
        ActionButton { iconName: "redo"; quiet: true; enabled: shell.state.canRedo; tip: "Повторить · Ctrl Y"; onClicked: shell.run("redo") }
        Rectangle { width: 1; height: Theme.s16; color: Theme.border }
        ActionButton { iconName: "grid"; quiet: !view.snapping; tip: view.snapping ? "Отключить привязку к сетке" : "Включить сетку"; onClicked: view.snapping=!view.snapping }
        ActionButton { iconName: "link"; primary: view.linkMode; tip: "Редактор связей"; onClicked: { view.linkMode=!view.linkMode;view.updateEdges() } }
        ActionButton { iconName: "fit"; quiet: true; tip: "Вписать содержимое"; onClicked: viewport.fit() }
        Choice { model: ["50%","75%","100%","125%","150%","200%"]; Layout.preferredWidth: Theme.px(88); currentIndex: [50,75,100,125,150,200].indexOf(Math.round(viewport.zoom*100)); displayText: Math.round(viewport.zoom*100)+"%"; onActivated: viewport.zoomAt([.5,.75,1,1.25,1.5,2][currentIndex],viewport.width/2,viewport.height/2) }
        Item { Layout.fillWidth: true }
        ActionButton { iconName: "settings"; quiet: !view.showInspector; tip: "Инспектор свойств"; onClicked: view.showInspector=!view.showInspector }
        ActionButton { text: "Опубликовать"; primary: true; onClicked: shell.confirm("Применить черновик к новым происшествиям? Уже открытые карточки сохранят свои настройки.",function() { shell.run("publish") }) }
    }
    RowLayout {
        Layout.fillWidth: true; Layout.fillHeight: true; spacing: Theme.s8
        Rectangle {
            visible: view.showPalette
            Layout.preferredWidth: Theme.paletteWidth; Layout.fillHeight: true; color: Theme.panel; radius: Theme.radius; border.color: Theme.border
            ColumnLayout { anchors.fill: parent; anchors.margins: Theme.s8; spacing: Theme.s4
                Label { text: "КОМПОНЕНТЫ"; color: Theme.muted; font.pixelSize: Theme.smallSize; Layout.margins: Theme.s4 }
                Repeater {
                    model: [{type:"text",name:"Шаблон"},{type:"contacts",name:"Контакты"},{type:"documents",name:"Документы"},{type:"reference",name:"Файлы"}]
                    ActionButton { required property var modelData; Layout.fillWidth: true; text: modelData.name; iconName: modelData.type; quiet: true; enabled: !!shell.state.master; onClicked: shell.run("add_block",{type:modelData.type}) }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; Layout.topMargin: Theme.s8; Layout.bottomMargin: Theme.s8 }
                Label { text: "ВЫДЕЛЕНИЕ"; color: Theme.muted; font.pixelSize: Theme.smallSize; Layout.margins: Theme.s4 }
                ActionButton { text: "Дублировать"; iconName: "copy"; quiet: true; Layout.fillWidth: true; enabled: view.selectedIds.length>0; onClicked: view.duplicateSelection() }
                ActionButton { text: "Удалить"; iconName: "trash"; danger: true; quiet: true; Layout.fillWidth: true; enabled: view.selectedIds.length>0; onClicked: view.removeSelection() }
                Item { Layout.fillHeight: true }
                Label { text: "Ctrl · несколько\nРамка · выделение\nПробел / средняя кнопка · холст\nCtrl + колесо · масштаб"; color: Theme.muted; font.pixelSize: Theme.smallSize; wrapMode: Text.Wrap; Layout.fillWidth: true; Layout.margins: Theme.s4 }
            }
        }
        WorkspaceCanvas {
            id: viewport
            objectName: "builderViewport"
            Layout.fillWidth: true; Layout.fillHeight: true
            showGrid: view.snapping
            showLinks: view.linkMode
            bounds: ({left:0,top:0,right:view.blocks.reduce(function(a,b) { return Math.max(a,b.x+b.width) },800),bottom:view.blocks.reduce(function(a,b) { return Math.max(a,b.y+b.height) },500)})
            zoom: shell.state.scale
            extraSpace: Theme.canvasExtra
            MouseArea {
                anchors.fill: parent
                property point start
                property bool boxing: false
                onPressed: function(mouse) { viewport.forceActiveFocus();start=Qt.point(mouse.x,mouse.y);boxing=false;rubber.x=mouse.x;rubber.y=mouse.y;rubber.width=0;rubber.height=0 }
                onPositionChanged: function(mouse) { if(pressed && Math.hypot(mouse.x-start.x,mouse.y-start.y)>4) { boxing=true;rubber.visible=true;rubber.x=Math.min(start.x,mouse.x);rubber.y=Math.min(start.y,mouse.y);rubber.width=Math.abs(mouse.x-start.x);rubber.height=Math.abs(mouse.y-start.y) } }
                onReleased: function(mouse) {
                    if(boxing) { var ids=[];for(var i=0;i<tiles.count;++i) { var t=tiles.itemAt(i);if(t && t.x<rubber.x+rubber.width && t.x+t.width>rubber.x && t.y<rubber.y+rubber.height && t.y+t.height>rubber.y) ids.push(t.modelData.id) };view.selectedIds=ids }
                    else { var edge=view.linkMode ? viewport.edgeAt(mouse.x,mouse.y) : "";if(edge) shell.confirm("Удалить эту связь? Сам блок останется в черновике.",function() { shell.run("toggle_link",{id:edge}) });else { view.selectedIds=[];view.synchronizeSelection("") } }
                    rubber.visible=false
                }
            }
            Rectangle {
                x: 24; y: 40; width: Theme.masterWidth; height: Theme.masterHeight
                radius: Theme.radius; color: Theme.card; border.color: view.connecting ? Theme.warning : Theme.accent; visible: !!shell.state.master
                Column { anchors.fill: parent; anchors.margins: Theme.s12; spacing: Theme.s8
                    Label { text: "МАСТЕР"; color: Theme.accent; font.pixelSize: Theme.smallSize }
                    Label { text: shell.state.master ? shell.state.master.name : ""; color: Theme.text; font.bold: true; font.pixelSize: Theme.fontSize; width: parent.width; elide: Text.ElideRight }
                }
                MouseArea { anchors.fill: parent; onClicked: { view.selectedIds=[];view.synchronizeSelection("") } }
                ActionButton { visible: view.linkMode; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.rightMargin: -Theme.control/2; iconName: "plus"; tip: "Создать связь: затем нажмите порт блока"; primary: view.connecting; onClicked: view.connecting=!view.connecting }
            }
            Repeater {
                id: tiles
                model: view.blocks
                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    objectName: "builderTile-"+modelData.id
                    property bool chosen: view.selected(modelData.id)
                    x: modelData.x; y: modelData.y; width: modelData.width; height: modelData.height
                    radius: Theme.radius; color: "transparent"
                    border.color: chosen ? Theme.accent : Theme.border; border.width: chosen ? 2 : 1
                    onXChanged: view.updateEdges()
                    onYChanged: view.updateEdges()
                    Rectangle {
                        width: parent.width; height: Theme.nodeHeight; radius: Theme.radius; color: Theme.panel
                        ColumnLayout { anchors.fill: parent; anchors.margins: Theme.s12; spacing: Theme.s8
                            RowLayout { Layout.fillWidth: true
                                Icon { name: tile.modelData.type; tint: tile.modelData.accent || Theme.accent }
                                Label { text: tile.modelData.title; color: Theme.text; font.pixelSize: Theme.fontSize; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                                Label { text: "⠿"; color: Theme.muted; font.pixelSize: Theme.fontSize }
                            }
                            Label { text: ({text:"Шаблон",contacts:"Excel",documents:"Документы",reference:"Файлы"})[tile.modelData.type]+" · "+view.summary(tile.modelData); color: Theme.muted; font.pixelSize: Theme.smallSize; Layout.fillWidth: true; elide: Text.ElideRight }
                        }
                        MouseArea {
                            objectName: "dragHandle-"+tile.modelData.id
                            anchors.fill: parent; preventStealing: true; cursorShape: Qt.SizeAllCursor
                            property point start
                            onPressed: function(mouse) { viewport.forceActiveFocus();view.beginDrag(tile.modelData.id,mouse.modifiers);start=mapToItem(viewport.stage,mouse.x,mouse.y) }
                            onPositionChanged: function(mouse) { if(pressed) { var p=mapToItem(viewport.stage,mouse.x,mouse.y);view.moveSelection(tile.modelData.id,p.x-start.x,p.y-start.y) } }
                            onReleased: view.saveGeometry(tile.modelData.id)
                        }
                    }
                    RowLayout { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.topMargin: Theme.nodeHeight+Theme.s12; anchors.leftMargin: Theme.s12; anchors.rightMargin: Theme.s12
                        Label { text: shell.state.master && shell.state.master.links.indexOf(tile.modelData.id)>=0 ? "● Подключён" : "○ Без связи"; color: shell.state.master && shell.state.master.links.indexOf(tile.modelData.id)>=0 ? Theme.success : Theme.muted; font.pixelSize: Theme.smallSize; Layout.fillWidth: true }
                        ActionButton { iconName: "settings"; quiet: true; tip: "Настройки блока"; onClicked: { view.selectedIds=[tile.modelData.id];view.synchronizeSelection(tile.modelData.id) } }
                    }
                    Label { anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: Theme.s12; text: Math.round(tile.width)+" × "+Math.round(tile.height); color: Theme.muted; font.pixelSize: Theme.smallSize }
                    ActionButton { visible: view.linkMode; anchors.left: parent.left; anchors.top: parent.top; anchors.topMargin: Theme.nodeHeight/2-height/2; anchors.leftMargin: -width/2; iconName: "link"; primary: view.connecting; tip: "Связать / отвязать от мастера"; onClicked: { if(!view.connecting || shell.state.master.links.indexOf(tile.modelData.id)<0) shell.run("toggle_link",{id:tile.modelData.id});view.connecting=false } }
                    Repeater {
                        model: ["n","s","w","e","nw","ne","sw","se"]
                        delegate: MouseArea {
                            id: resize
                            required property string modelData
                            objectName: modelData==="se" ? "resizeHandle-"+tile.modelData.id : "resize-"+modelData+"-"+tile.modelData.id
                            property bool west: modelData.indexOf("w")>=0
                            property bool east: modelData.indexOf("e")>=0
                            property bool north: modelData.indexOf("n")>=0
                            property bool south: modelData.indexOf("s")>=0
                            property real hit: Theme.resizeHit/viewport.zoom
                            x: west ? 0 : east ? tile.width-hit : hit/2
                            y: north ? 0 : south ? tile.height-hit : hit/2
                            width: west || east ? hit : tile.width-hit
                            height: north || south ? hit : tile.height-hit
                            preventStealing: true
                            cursorShape: (west||east)&&(north||south) ? (west===north ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor) : west||east ? Qt.SizeHorCursor : Qt.SizeVerCursor
                            property point start
                            property var original
                            onPressed: function(mouse) { view.selectedIds=[tile.modelData.id];start=mapToItem(viewport.stage,mouse.x,mouse.y);original={x:tile.x,y:tile.y,width:tile.width,height:tile.height} }
                            onPositionChanged: function(mouse) {
                                if(!pressed) return
                                var p=mapToItem(viewport.stage,mouse.x,mouse.y),dx=p.x-start.x,dy=p.y-start.y
                                var w=original.width+(east ? dx : west ? -dx : 0),h=original.height+(south ? dy : north ? -dy : 0)
                                if(view.snapping) { w=Math.round(w/Theme.grid)*Theme.grid;h=Math.round(h/Theme.grid)*Theme.grid }
                                w=Math.max(320,w);h=Math.max(260,h)
                                if(west) { w=Math.min(w,original.width+original.x);tile.x=original.x+original.width-w }
                                if(north) { h=Math.min(h,original.height+original.y);tile.y=original.y+original.height-h }
                                tile.width=w;tile.height=h
                            }
                            onReleased: view.saveGeometry(tile.modelData.id)
                            Rectangle { visible: tile.chosen && resize.modelData.length===2; anchors.centerIn: parent; width: Theme.resizeMark/viewport.zoom; height: width; radius: 1; color: Theme.accent }
                        }
                    }
                }
            }
            Rectangle { x: view.guideX; width: 1; height: viewport.stage.height; visible: view.guideX>=0; color: Theme.accent }
            Rectangle { y: view.guideY; width: viewport.stage.width; height: 1; visible: view.guideY>=0; color: Theme.accent }
            Rectangle { id: rubber; visible: false; color: "transparent"; border.color: Theme.accent; border.width: 1; z: 10 }
        }
        Rectangle {
            visible: view.showInspector
            Layout.preferredWidth: Theme.inspector; Layout.fillHeight: true; color: Theme.panel; border.color: Theme.border; radius: Theme.radius
            ScrollView { id: properties; anchors.fill: parent; anchors.margins: Theme.s12; contentWidth: availableWidth; clip: true
                Loader { width: properties.availableWidth; sourceComponent: shell.state.selectedBlock ? blockProperties : masterProperties }
            }
        }
    }
    RowLayout { Layout.fillWidth: true
        Label { text: view.linkMode ? (view.connecting ? "Выберите порт блока для новой связи" : "Связи · Нажмите стрелку, чтобы удалить связь. Все блоки запускаются одновременно.") : view.selectedIds.length+" выделено · Координаты сохраняются в черновике"; color: view.linkMode ? Theme.accent : Theme.muted; font.pixelSize: Theme.smallSize; Layout.fillWidth: true; elide: Text.ElideRight }
        Label { text: Math.round(viewport.zoom*100)+"%"; color: Theme.muted; font.pixelSize: Theme.smallSize }
    }
    Component { id: blockProperties; BlockEditor { shell: view.shell } }
    Component {
        id: masterProperties
        ColumnLayout { spacing: Theme.s12; visible: !!shell.state.master
            Label { text: "Мастер-блок"; color: Theme.text; font.pixelSize: Theme.headingSize; font.bold: true }
            Section { title: "Общее"
                Input { id: masterName; Layout.fillWidth: true; placeholderText: "Название"; text: shell.state.master ? shell.state.master.name : "" }
                Input { id: masterTag; Layout.fillWidth: true; placeholderText: "Системный тег"; text: shell.state.master ? shell.state.master.tag : "" }
                Label { text: "Тег связывает сценарий с Excel-контактами и не зависит от названия."; color: Theme.muted; font.pixelSize: Theme.smallSize; wrapMode: Text.Wrap; Layout.fillWidth: true }
            }
            Section { title: "Оформление"
                Input { id: masterIcon; Layout.fillWidth: true; placeholderText: "Значок"; text: shell.state.master ? shell.state.master.icon : "!" }
                Input { id: masterColor; Layout.fillWidth: true; placeholderText: "Цвет #RRGGBB"; text: shell.state.master ? shell.state.master.color : "" }
            }
            ActionButton { text: "Сохранить мастер"; iconName: "save"; primary: true; Layout.fillWidth: true; onClicked: shell.run("save_master",{name:masterName.text,tag:masterTag.text,icon:masterIcon.text,color:masterColor.text}) }
            ActionButton { text: "Дублировать сценарий"; iconName: "copy"; quiet: true; Layout.fillWidth: true; onClicked: shell.run("duplicate_master") }
            ActionButton { text: "Удалить мастер"; iconName: "trash"; danger: true; quiet: true; Layout.fillWidth: true; onClicked: shell.confirm("Удалить мастер и его блоки из черновика? Существующие происшествия сохранятся.",function() { shell.run("delete_master") }) }
            Label { text: shell.state.master ? "UUID · "+shell.state.master.id : ""; color: Theme.muted; font.pixelSize: Theme.smallSize; wrapMode: Text.Wrap; Layout.fillWidth: true }
        }
    }
}
