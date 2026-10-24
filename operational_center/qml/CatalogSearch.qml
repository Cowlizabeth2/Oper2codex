import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."
Dialog {
    id: dialog
    objectName: "catalogSearchDialog"
    required property var shell
    property var catalog: ({id:"",name:"Все сценарии",opening:"compact",members:[]})
    property var results: []
    property var categories: [""]
    parent: Overlay.overlay
    x: catalog.opening==="panel" ? parent.width-width-Theme.s16 : (parent.width-width)/2
    y: catalog.opening==="panel" ? Theme.s16 : (parent.height-height)/2
    width: Math.min(parent.width-Theme.s32,Theme.px(catalog.opening==="wide" ? 960 : catalog.opening==="panel" ? 440 : 680))
    height: catalog.opening==="panel" ? parent.height-Theme.s32 : Math.min(parent.height-Theme.s32,Theme.px(600))
    modal: catalog.opening!=="panel"
    title: catalog.name
    standardButtons: Dialog.Close
    closePolicy: Popup.CloseOnEscape
    function showCatalog(item) { catalog=item;open() }
    function refresh() {
        results=backend.searchCatalog(catalog.id,query.text,categoryChoice.currentIndex>0 ? categories[categoryChoice.currentIndex] : "",["all","favorites","recent"][modeChoice.currentIndex])
        resultList.currentIndex=results.length ? 0 : -1
    }
    function move(delta) { if(results.length) resultList.currentIndex=Math.max(0,Math.min(results.length-1,resultList.currentIndex+delta));resultList.positionViewAtIndex(resultList.currentIndex,ListView.Contain) }
    function launch(index) {
        if(index>=0 && index<results.length && shell.run("launch_catalog",{id:results[index].id,catalog:catalog.id})) { close();shell.page="events" }
    }
    onOpened: {
        standardButton(Dialog.Close).text="Закрыть"
        var cats=[],masters=shell.state.published.masters
        for(var i=0;i<masters.length;++i) if((!catalog.id || catalog.members.indexOf(masters[i].id)>=0) && masters[i].category && cats.indexOf(masters[i].category)<0) cats.push(masters[i].category)
        categories=[""].concat(cats.sort());categoryChoice.currentIndex=0;modeChoice.currentIndex=0;query.text="";refresh();query.forceActiveFocus()
    }
    Connections { target: backend; function onStateChanged() { if(dialog.visible) dialog.refresh() } }
    contentItem: ColumnLayout {
        spacing: Theme.s8
        Input {
            id: query; objectName: "catalogQuery"; Layout.fillWidth: true; placeholderText: "Станция, КМ, системный код, алиас или тег"
            onTextEdited: dialog.refresh()
            Keys.onDownPressed: dialog.move(1)
            Keys.onUpPressed: dialog.move(-1)
            Keys.onReturnPressed: dialog.launch(resultList.currentIndex)
            Keys.onEnterPressed: dialog.launch(resultList.currentIndex)
            Keys.onEscapePressed: dialog.close()
        }
        RowLayout { Layout.fillWidth: true
            Choice { id: categoryChoice; Layout.fillWidth: true; model: dialog.categories.map(function(s) {return s || "Все категории"}); onActivated: dialog.refresh() }
            Choice { id: modeChoice; Layout.fillWidth: true; model: ["Все сценарии","Избранные","Недавние"]; onActivated: dialog.refresh() }
        }
        Label { text: dialog.results.length+" найдено · ↑ ↓ выбор · Enter запуск · Esc закрыть"; color: Theme.muted; font.pixelSize: Theme.smallSize }
        ListView {
            id: resultList; objectName: "catalogResults"; Layout.fillWidth: true; Layout.fillHeight: true; clip: true
            model: dialog.results; spacing: Theme.s4; keyNavigationEnabled: true
            ScrollBar.vertical: ScrollBar {}
            Keys.onReturnPressed: dialog.launch(currentIndex)
            Keys.onEnterPressed: dialog.launch(currentIndex)
            Keys.onEscapePressed: dialog.close()
            delegate: Rectangle {
                id: result
                required property var modelData
                required property int index
                objectName: "catalogResult-"+modelData.id
                width: ListView.view.width; height: Theme.px(64); radius: Theme.radius
                color: resultList.currentIndex===index ? Theme.card : Theme.panel
                border.color: resultList.currentIndex===index ? Theme.accent : Theme.border
                MouseArea { anchors.fill: parent; onClicked: {resultList.currentIndex=result.index;dialog.launch(result.index)} }
                RowLayout { anchors.fill: parent; anchors.margins: Theme.s8
                    ColumnLayout { Layout.fillWidth: true; spacing: Theme.s4
                        Label { text: result.modelData.name; color: Theme.text; font.bold: true; font.pixelSize: Theme.fontSize; Layout.fillWidth: true; elide: Text.ElideRight }
                        Label { text: [result.modelData.km_code,result.modelData.tag,result.modelData.category].filter(function(s){return s}).join(" · "); color: Theme.muted; font.pixelSize: Theme.smallSize; Layout.fillWidth: true; elide: Text.ElideRight }
                    }
                    ActionButton { text: result.modelData.favorite ? "★" : "☆"; objectName: "catalogFavorite-"+result.modelData.id; quiet: true; tip: "Избранное"; onClicked: dialog.shell.run("catalog_favorite",{id:result.modelData.id}) }
                }
            }
            Label { anchors.centerIn: parent; visible: dialog.results.length===0; text: "Сценарии не найдены"; color: Theme.muted; font.pixelSize: Theme.fontSize }
        }
    }
}
