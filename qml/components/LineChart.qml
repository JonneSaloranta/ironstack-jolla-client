import QtQuick 2.0
import Sailfish.Silica 1.0

// A small line chart for a value over time (body measurements, an
// exercise's progress). `points` is [{ x: <ms since epoch>, y: <number> }]
// in any order; the y range is padded so a flat line isn't glued to an edge.
// Highest and lowest value are labelled on the left, first and last date
// below.
Item {
    id: chart

    property var points: []
    property string unit: ""
    property color lineColor: Theme.highlightColor

    readonly property var sorted: (points || []).filter(function(p) { return !isNaN(p.y) })
                                                .sort(function(a, b) { return a.x - b.x })
    readonly property real minY: sorted.length ? Math.min.apply(null, sorted.map(function(p) { return p.y })) : 0
    readonly property real maxY: sorted.length ? Math.max.apply(null, sorted.map(function(p) { return p.y })) : 0

    function label(value) {
        return (Math.round(value * 10) / 10) + (unit ? " " + unit : "")
    }

    width: parent ? parent.width : 0
    height: Theme.itemSizeHuge * 1.5

    onSortedChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()

    Label {
        id: maxLabel
        x: Theme.horizontalPageMargin
        font.pixelSize: Theme.fontSizeTiny
        color: Theme.secondaryColor
        text: chart.sorted.length ? chart.label(chart.maxY) : ""
    }
    Label {
        anchors.bottom: canvas.bottom
        x: Theme.horizontalPageMargin
        font.pixelSize: Theme.fontSizeTiny
        color: Theme.secondaryColor
        text: chart.sorted.length > 1 && chart.maxY !== chart.minY ? chart.label(chart.minY) : ""
    }

    Canvas {
        id: canvas
        anchors.top: maxLabel.bottom
        anchors.bottom: dates.top
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var pts = chart.sorted
            if (pts.length === 0)
                return
            var minX = pts[0].x
            var maxX = pts[pts.length - 1].x
            var span = chart.maxY - chart.minY
            var pad = span > 0 ? span * 0.1 : Math.max(1, Math.abs(chart.maxY) * 0.05)
            var low = chart.minY - pad
            var high = chart.maxY + pad
            var dot = Math.max(3, Theme.paddingSmall)
            function px(p) {
                return maxX > minX ? dot + (p.x - minX) / (maxX - minX) * (width - 2 * dot) : width / 2
            }
            function py(p) {
                return dot + (high - p.y) / (high - low) * (height - 2 * dot)
            }

            ctx.strokeStyle = Theme.rgba(Theme.secondaryColor, 0.3)
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.moveTo(0, height - 0.5)
            ctx.lineTo(width, height - 0.5)
            ctx.stroke()

            ctx.strokeStyle = chart.lineColor
            ctx.lineWidth = Math.max(2, Math.round(Theme.pixelRatio * 2))
            ctx.beginPath()
            for (var i = 0; i < pts.length; i++) {
                if (i === 0)
                    ctx.moveTo(px(pts[i]), py(pts[i]))
                else
                    ctx.lineTo(px(pts[i]), py(pts[i]))
            }
            ctx.stroke()

            ctx.fillStyle = chart.lineColor
            for (var j = 0; j < pts.length; j++) {
                ctx.beginPath()
                ctx.arc(px(pts[j]), py(pts[j]), dot, 0, 2 * Math.PI)
                ctx.fill()
            }
        }
    }

    Item {
        id: dates
        anchors.bottom: parent.bottom
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        height: firstDate.height
        Label {
            id: firstDate
            font.pixelSize: Theme.fontSizeTiny
            color: Theme.secondaryColor
            text: chart.sorted.length ? Format.formatDate(new Date(chart.sorted[0].x), Formatter.DateMedium) : ""
        }
        Label {
            anchors.right: parent.right
            visible: chart.sorted.length > 1
            font.pixelSize: Theme.fontSizeTiny
            color: Theme.secondaryColor
            text: visible ? Format.formatDate(new Date(chart.sorted[chart.sorted.length - 1].x), Formatter.DateMedium) : ""
        }
    }
}
