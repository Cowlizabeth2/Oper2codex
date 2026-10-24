import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."
ColumnLayout {
    id: view
    required property var shell
    property string eventId: shell.state.event ? shell.state.event.id : ""
    property var blocks: shell.state.event ? shell.state.event.snapshot.blocks : []
    function fitContents() { canvas.fit() }
    function focusContents() { canvas.focusContent() }
    spacing: Theme.s8
    onEventIdChanged: Qt.callLater(function() { canvas.focusContent() })
    Component.onCompleted: Qt.callLater(function() { canvas.focusContent() })
    RowLayout {
        visible: !!shell.state.event
        Layout.fillWidth: true
        Label { text: shell.state.event ? blocks.length+" блоков · "+Qt.formatDateTime(new Date(shell.state.event.created),"dd.MM.yyyy HH:mm")+" · v"+shell.state.event.config_version : ""; color: Theme.muted; font.pixelSize: Theme.smallSize; Layout.fillWidth: true; elide: Text.ElideRight }
        ActionButton { iconName: "fit"; text: "Вписать"; quiet: true; tip: "Вписать содержимое без изменения компоновки"; onClicked: canvas.fit() }
        ActionButton { iconName: "history"; quiet: true; tip: "Действия в карточке"; onClicked: actions.open() }
        Choice { Layout.preferredWidth: Theme.px(88); model: ["50%","75%","100%","125%","150%","200%"]; currentIndex: [50,75,100,125,150,200].indexOf(Math.round(canvas.zoom*100)); displayText: Math.round(canvas.zoom*100)+"%"; onActivated: canvas.zoomAt([.5,.75,1,1.25,1.5,2][currentIndex],canvas.width/2,canvas.height/2) }
        ActionButton { iconName: "check"; text: "Завершить"; onClicked: shell.confirm("Завершить происшествие? Оно останется в истории.",function() { shell.run("archive_event",{id:shell.state.event.id}) }) }
    }
    Label { visible: !shell.state.event; text: "Выберите сценарий на главной или откройте карточку из истории."; color: Theme.muted; font.pixelSize: Theme.fontSize; Layout.fillWidth: true; wrapMode: Text.Wrap }
    Label { visible: !!shell.state.event && blocks.length===0; text: "В этой версии сценария нет связанных блоков. Настройте и опубликуйте сценарий, затем создайте новое происшествие."; color: Theme.warning; font.pixelSize: Theme.fontSize; Layout.fillWidth: true; wrapMode: Text.Wrap }
    WorkspaceCanvas {
        id: canvas
        objectName: "eventCanvas"
        zoom: shell.state.scale
        visible: !!shell.state.event && blocks.length>0
        Layout.fillWidth: true; Layout.fillHeight: true
        bounds: ({left:view.blocks.reduce(function(a,b) { return Math.min(a,b.x) },view.blocks.length ? view.blocks[0].x : 0),top:view.blocks.reduce(function(a,b) { return Math.min(a,b.y) },view.blocks.length ? view.blocks[0].y : 0),right:view.blocks.reduce(function(a,b) { return Math.max(a,b.x+b.width) },1),bottom:view.blocks.reduce(function(a,b) { return Math.max(a,b.y+b.height) },1)})
        Repeater {
            model: view.blocks
            RuntimeBlock { required property var modelData; shell: view.shell; block: modelData; x: modelData.x; y: modelData.y; width: modelData.width; height: modelData.height }
        }
    }
    Item { visible: !canvas.visible; Layout.fillHeight: true }
    Dialog {
        id: actions
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width-Theme.s32,Theme.px(560))
        height: Math.min(parent.height-Theme.s32,Theme.px(400))
        title: "Действия в карточке"
        modal: true
        standardButtons: Dialog.Close
        onOpened: actionList.model=backend.eventHistory(view.eventId)
        contentItem: ListView {
            id: actionList
            clip: true; spacing: Theme.s8
            ScrollBar.vertical: ScrollBar {}
            delegate: Column {
                required property var modelData
                width: ListView.view.width; spacing: Theme.s4
                Text { text: Qt.formatDateTime(new Date(modelData.created),"dd.MM.yyyy HH:mm:ss"); color: Theme.muted; font.pixelSize: Theme.smallSize }
                Text { text: modelData.message; color: Theme.text; font.pixelSize: Theme.fontSize; width: parent.width; wrapMode: Text.Wrap }
            }
            Label { anchors.centerIn: parent; text: "Действия появятся при работе с карточкой"; color: Theme.muted; visible: parent.count===0 }
        }
    }
}
