import QtQuick
import "."
Item {
    property string name: "file"
    property color tint: Theme.muted
    width: Theme.icon
    height: width
    implicitWidth: Theme.icon
    implicitHeight: Theme.icon
    property var paths: ({
        car: '<path d="m4 8 2-5h8l2 5M3 8h14v7H3Zm0 4h14M5 15v3m10-3v3M5 10h2m6 0h2"/>',
        flame: '<path d="M11 2c1 5-4 5-2 8 2 1 3-2 3-3 5 5 5 10-2 11-7-1-8-8-3-11 0 3 1 3 1 3-2-4 1-5 3-8Z"/>',
        building: '<path d="m2 7 8-5 8 5ZM3 17h14M5 8v7m5-7v7m5-7v7"/>',
        home: '<path d="m3 9 7-6 7 6v8h-5v-5H8v5H3Z"/>',
        events: '<path d="m10 2 8 15H2Z"/><path d="M10 7v4m0 2v1"/>',
        history: '<circle cx="10" cy="10" r="7"/><path d="M10 6v5l3 2"/>',
        builder: '<rect x="2" y="3" width="6" height="5" rx="1"/><rect x="12" y="12" width="6" height="5" rx="1"/><path d="M5 8v6h7m-2-2 2 2-2 2"/>',
        settings: '<path d="M3 5h14M3 10h14M3 15h14"/><circle cx="7" cy="5" r="2"/><circle cx="13" cy="10" r="2"/><circle cx="8" cy="15" r="2"/>',
        logs: '<path d="M5 2h8l3 3v13H5Z"/><path d="M8 8h5m-5 3h5m-5 3h3"/>',
        text: '<path d="M3 4h14M10 4v13m-3 0h6"/>',
        static_text: '<path d="M3 4h14M3 8h10M3 12h14M3 16h8"/>',
        contacts: '<circle cx="8" cy="6" r="3"/><path d="M2 17v-2a5 5 0 0 1 10 0v2m2-9h4m-4 4h4"/>',
        documents: '<path d="M6 2h7l4 4v12H6Zm7 0v4h4M3 5v12"/>',
        reference: '<path d="M2 6h6l2 2h8v9H2Zm0 0V3h6l2 2h6v3"/>',
        file: '<path d="M4 2h8l4 4v12H4Zm8 0v4h4M7 10h6m-6 3h4"/>',
        plus: '<path d="M10 3v14M3 10h14"/>',
        search: '<circle cx="8" cy="8" r="5"/><path d="m12 12 5 5"/>',
        chevron: '<path d="m5 8 5 5 5-5"/>',
        collapse: '<path d="m12 5-5 5 5 5"/>',
        close: '<path d="m5 5 10 10M15 5 5 15"/>',
        check: '<path d="m4 10 4 4 8-8"/>',
        copy: '<rect x="7" y="7" width="10" height="11" rx="1"/><path d="M13 7V2H2v11h5"/>',
        more: '<circle cx="4" cy="10" r=".7"/><circle cx="10" cy="10" r=".7"/><circle cx="16" cy="10" r=".7"/>',
        sun: '<circle cx="10" cy="10" r="3"/><path d="M10 1v2m0 14v2M1 10h2m14 0h2M4 4l1 1m10 10 1 1M4 16l1-1M15 5l1-1"/>',
        moon: '<path d="M16 12A7 7 0 0 1 8 3a7 7 0 1 0 8 9Z"/>',
        fit: '<path d="M7 3H3v4m10-4h4v4M3 13v4h4m10-4v4h-4"/><rect x="7" y="7" width="6" height="6"/>',
        undo: '<path d="m7 4-4 4 4 4M3 8h8a5 5 0 0 1 0 10"/>',
        redo: '<path d="m13 4 4 4-4 4m4-4H9a5 5 0 0 0 0 10"/>',
        link: '<path d="m8 6 2-2a4 4 0 0 1 6 6l-2 2m-2 2-2 2a4 4 0 0 1-6-6l2-2m1 5 6-6"/>',
        grid: '<path d="M3 3h14v14H3ZM3 8h14M3 13h14M8 3v14m5-14v14"/>',
        move: '<path d="M10 2v16M2 10h16M7 5l3-3 3 3M7 15l3 3 3-3M5 7l-3 3 3 3m10-6 3 3-3 3"/>',
        arrow: '<path d="M3 10h14m-5-5 5 5-5 5"/>',
        trash: '<path d="M3 5h14M7 5V2h6v3M5 5l1 13h8l1-13M8 8v7m4-7v7"/>',
        save: '<path d="M3 2h12l2 2v14H3Zm3 0v5h8V2M6 18v-7h8v7"/>'
    })
    Image { anchors.fill: parent; sourceSize.width: Theme.icon*2; sourceSize.height: Theme.icon*2
    source: "data:image/svg+xml;base64," + Qt.btoa('<svg width="20" height="20" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="none" stroke="' + tint + '" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">' + (paths[name] || paths.file) + '</svg>')
    }
}
