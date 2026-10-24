import QtQuick
import QtQuick.Controls.Basic
import "."
ScrollView {
    id: surface
    default property alias sceneData: stage.data
    property alias stage: stage
    property var bounds: ({left:0,top:0,right:1200,bottom:800})
    property real zoom: 1
    property real originX: 0
    property real originY: 0
    property real extraSpace: 0
    property bool showGrid: false
    property bool showLinks: false
    property bool spacePan: false
    property var edges: []
    signal edgeClicked(string identity)
    clip: true
    implicitWidth: 0
    implicitHeight: 0
    focus: true
    onActiveFocusChanged: if(!activeFocus) spacePan=false
    contentWidth: Math.max(width - Theme.s16, (stage.width-originX) * zoom)
    contentHeight: Math.max(height - Theme.s16, (stage.height-originY) * zoom)
    function focusContent() {
        originX=Math.max(0,bounds.left-Theme.canvasMargin/zoom)
        originY=Math.max(0,bounds.top-Theme.canvasMargin/zoom)
        Qt.callLater(function() { surface.contentItem.contentX=0;surface.contentItem.contentY=0 })
    }
    function fit() {
        var margin = Theme.canvasMargin
        zoom = Math.max(.1,Math.min(1.5,(width-margin*2)/Math.max(1,bounds.right-bounds.left),(height-margin*2)/Math.max(1,bounds.bottom-bounds.top)))
        originX=Math.max(0,bounds.left-margin/zoom);originY=Math.max(0,bounds.top-margin/zoom)
        Qt.callLater(function() { surface.contentItem.contentX=0;surface.contentItem.contentY=0 })
    }
    function zoomAt(value, x, y) {
        var logicalX = (contentItem.contentX+x)/zoom+originX, logicalY = (contentItem.contentY+y)/zoom+originY
        zoom = Math.max(.1,Math.min(3,value))
        Qt.callLater(function() { surface.contentItem.contentX = Math.max(0,(logicalX-surface.originX)*surface.zoom-x); surface.contentItem.contentY = Math.max(0,(logicalY-surface.originY)*surface.zoom-y) })
    }
    function paint() { grid.requestPaint(); wires.requestPaint() }
    function edgeAt(x,y) {
        for(var i=0;i<edges.length;++i) {
            var points=edges[i].points || []
            for(var j=1;j<points.length;++j) {
                var a=points[j-1],b=points[j],dx=b.x-a.x,dy=b.y-a.y,length=dx*dx+dy*dy
                var t=length ? Math.max(0,Math.min(1,((x-a.x)*dx+(y-a.y)*dy)/length)) : 0
                if(Math.hypot(x-a.x-t*dx,y-a.y-t*dy)<8/zoom) return edges[i].id
            }
        }
        return ""
    }
    onZoomChanged: paint()
    onEdgesChanged: paint()
    onShowLinksChanged: paint()
    onShowGridChanged: paint()
    Keys.onPressed: function(event) { if (event.key === Qt.Key_Space) { spacePan=true; event.accepted=true } }
    Keys.onReleased: function(event) { if (event.key === Qt.Key_Space) { spacePan=false; event.accepted=true } }
    background: Rectangle {
        color: Theme.background; border.color: Theme.border; radius: Theme.radius
        Canvas {
            id: grid
            anchors.fill: parent
            visible: surface.showGrid
            onPaint: {
                var ctx=getContext("2d");ctx.clearRect(0,0,width,height)
                if (!surface.contentItem) return
                var step=Theme.grid*surface.zoom
                if (step<6) return
                ctx.fillStyle=Theme.border
                var ox=-surface.contentItem.contentX%step,oy=-surface.contentItem.contentY%step
                for(var x=ox;x<width;x+=step) for(var y=oy;y<height;y+=step) ctx.fillRect(x,y,1,1)
            }
        }
        Canvas {
            id: wires
            anchors.fill: parent
            visible: surface.showLinks
            onPaint: {
                var ctx=getContext("2d");ctx.clearRect(0,0,width,height)
                if (!surface.contentItem) return
                ctx.strokeStyle=Theme.accent;ctx.fillStyle=Theme.accent;ctx.lineWidth=1.5
                for(var i=0;i<surface.edges.length;++i) {
                    var e=surface.edges[i],z=surface.zoom,ox=surface.contentItem.contentX,oy=surface.contentItem.contentY
                    var sx=(e.sx-surface.originX)*z-ox,sy=(e.sy-surface.originY)*z-oy,ex=(e.ex-surface.originX)*z-ox,ey=(e.ey-surface.originY)*z-oy
                    ctx.lineJoin="round"
                    ctx.beginPath();ctx.moveTo(sx,sy)
                    var points=e.points || []
                    for(var j=1;j<points.length;++j) ctx.lineTo((points[j].x-surface.originX)*z-ox,(points[j].y-surface.originY)*z-oy)
                    ctx.stroke()
                    ctx.beginPath();ctx.moveTo(ex,ey);ctx.lineTo(ex-8,ey-4);ctx.lineTo(ex-8,ey+4);ctx.closePath();ctx.fill()
                }
            }
        }
    }
    Item {
        id: stage
        x: -surface.originX*surface.zoom; y: -surface.originY*surface.zoom
        width: Math.max(1,surface.bounds.right+Theme.canvasMargin+surface.extraSpace)
        height: Math.max(1,surface.bounds.bottom+Theme.canvasMargin+surface.extraSpace)
        scale: surface.zoom; transformOrigin: Item.TopLeft
    }
    Connections { target: surface.contentItem; function onContentXChanged() { surface.paint() } function onContentYChanged() { surface.paint() } }
    Connections { target: Theme; function onTokensChanged() { surface.paint() } }
    MouseArea {
        parent: surface
        anchors.fill: parent
        z: 100
        acceptedButtons: Qt.MiddleButton | (surface.spacePan ? Qt.LeftButton : Qt.NoButton)
        cursorShape: pressed ? Qt.ClosedHandCursor : surface.spacePan ? Qt.OpenHandCursor : Qt.ArrowCursor
        property point start
        property point offset
        onPressed: function(mouse) { start=Qt.point(mouse.x,mouse.y);offset=Qt.point(surface.contentItem.contentX,surface.contentItem.contentY) }
        onPositionChanged: function(mouse) { if(pressed) { surface.contentItem.contentX=Math.max(0,offset.x+start.x-mouse.x);surface.contentItem.contentY=Math.max(0,offset.y+start.y-mouse.y) } }
        onWheel: function(wheel) { if(wheel.modifiers&Qt.ControlModifier) { surface.zoomAt(surface.zoom*(wheel.angleDelta.y>0 ? 1.1 : 1/1.1),wheel.x,wheel.y);wheel.accepted=true } else wheel.accepted=false }
    }
}
