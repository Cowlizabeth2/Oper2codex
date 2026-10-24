import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "."
Dialog {
    id: dialog
    objectName: "catalogManagerDialog"
    required property var shell
    property string selectedId: ""
    property var members: []
    property var catalogs: shell.state.draft.catalogs || []
    property var selected: catalogs.find(function(c){return c.id===dialog.selectedId}) || null
    parent: Overlay.overlay; anchors.centerIn: parent
    width: Math.min(parent.width-Theme.s32,Theme.px(920)); height: Math.min(parent.height-Theme.s32,Theme.px(680))
    title: "Каталоги мастер-сценариев · черновик"; modal: true; standardButtons: Dialog.Close
    function loadSelected() {
        if(!selected) return
        nameInput.text=selected.name;iconInput.text=selected.icon;colorInput.text=selected.color;opening.currentIndex=selected.opening==="wide" ? 1 : 0;members=selected.members.slice()
    }
    function toggle(id) { var a=members.slice(),at=a.indexOf(id);if(at<0)a.push(id);else a.splice(at,1);members=a }
    onSelectedIdChanged: loadSelected()
    onOpened: { standardButton(Dialog.Close).text="Закрыть";selectedId=catalogs.length ? catalogs[0].id : "";loadSelected();memberQuery.text="" }
    contentItem: ColumnLayout {
        RowLayout { Layout.fillWidth: true
            Choice { id: catalogChoice; Layout.fillWidth: true; model: dialog.catalogs; textRole: "name"; currentIndex: dialog.catalogs.findIndex(function(c){return c.id===dialog.selectedId}); onActivated: { dialog.selectedId=model[currentIndex].id;dialog.loadSelected() } }
            ActionButton { text: "Новый каталог"; iconName: "plus"; objectName: "newCatalog"; onClicked: { if(dialog.shell.run("new_catalog")) {dialog.selectedId=dialog.catalogs[dialog.catalogs.length-1].id;dialog.loadSelected()} } }
        }
        ColumnLayout { Layout.fillWidth: true; Layout.fillHeight: true; enabled: !!dialog.selected
            RowLayout { Layout.fillWidth: true
                Input { id: nameInput; objectName: "catalogName"; Layout.fillWidth: true; placeholderText: "Название каталога" }
                Input { id: iconInput; Layout.preferredWidth: Theme.px(80); placeholderText: "Значок" }
                Input { id: colorInput; Layout.preferredWidth: Theme.px(110); placeholderText: "#RRGGBB" }
            }
            Choice { id: opening; Layout.fillWidth: true; model: ["Компактное окно поиска","Широкое окно поиска"] }
            Input { id: memberQuery; Layout.fillWidth: true; placeholderText: "Найти мастер для добавления · название или системный код" }
            RowLayout { Layout.fillWidth: true
                Label { text: dialog.members.length+" сценариев в каталоге"; color: Theme.muted; font.pixelSize: Theme.smallSize; Layout.fillWidth: true }
                ActionButton { text: "Добавить найденные"; quiet: true; onClicked: { var a=dialog.members.slice();for(var i=0;i<memberList.model.length;++i) if(a.indexOf(memberList.model[i].id)<0)a.push(memberList.model[i].id);dialog.members=a } }
                ActionButton { text: "Убрать все"; quiet: true; onClicked: dialog.members=[] }
            }
            ListView { id: memberList; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: Theme.s4
                model: dialog.shell.state.draft.masters.filter(function(m){return (m.name+" "+m.tag).toLowerCase().indexOf(memberQuery.text.toLowerCase())>=0})
                ScrollBar.vertical: ScrollBar {}
                delegate: Check { required property var modelData; width: ListView.view.width; text: modelData.name+" · "+modelData.tag; checked: dialog.members.indexOf(modelData.id)>=0; onToggled: dialog.toggle(modelData.id) }
            }
            Label { text: "Удаление из каталога сохраняет исходный мастер и его блоки. Один мастер может входить в несколько каталогов. Поисковые реквизиты задаются в свойствах мастера."; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.muted; font.pixelSize: Theme.smallSize }
            RowLayout { Layout.fillWidth: true
                ActionButton { text: "Удалить каталог"; danger: true; onClicked: { var id=dialog.selectedId;dialog.shell.confirm("Удалить каталог? Мастера и происшествия сохранятся.",function(){if(dialog.shell.run("delete_catalog",{id:id})){dialog.selectedId=dialog.catalogs.length?dialog.catalogs[0].id:"";dialog.loadSelected()}}) } }
                Item { Layout.fillWidth: true }
                ActionButton { text: "Сохранить каталог"; objectName: "saveCatalog"; primary: true; onClicked: dialog.shell.run("save_catalog",{id:dialog.selectedId,name:nameInput.text,icon:iconInput.text,color:colorInput.text,opening:["compact","wide"][opening.currentIndex],members:dialog.members}) }
            }
        }
        Label { text: "После настройки опубликуйте черновик в конструкторе."; color: Theme.muted; font.pixelSize: Theme.smallSize }
    }
}
