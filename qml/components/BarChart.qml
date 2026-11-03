import QtQuick 2.0
import Sailfish.Silica 1.0

// Vertical bars for a value per period (weekly volume, daily calories),
// like the web's core/_bar_chart.html. `bars` is [{ value, label }] in
// order; a null value is a gap ("no data", not zero). `reference` draws a
// dashed line (a target). The highest value is labelled on the left, the
// first and last label below.
Item {
    id: chart

    property var bars: []
    property string unit: ""
    property real reference: NaN
    property color barColor: Theme.highlightColor

    readonly property real maxValue: {
        var values = (bars || []).map(function(b) { return b.value }).filter(function(v) { return v !== null && !isNaN(v) })
        if (!isNaN(reference))
            values.push(reference)
        return values.length ? Math.max.apply(null, values) : 0
    }

    function label(value) {
        return Math.round(value) + (unit ? " " + unit : "")
    }

    width: parent ? parent.width : 0
    height: Theme.itemSizeHuge * 1.5

    onBarsChanged: canvas.requestPaint()
    onReferenceChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()

    Label {
        id: maxLabel
        x: Theme.horizontalPageMargin
        font.pixelSize: Theme.fontSizeTiny
        color: Theme.secondaryColor
        text: chart.maxValue > 0 ? chart.label(chart.maxValue) : ""
    }

    Canvas {
        id: canvas
        anchors.top: maxLabel.bottom
        anchors.bottom: labels.top
        anchors.bottomMargin: Theme.paddingSmall
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var bars = chart.bars || []
            if (bars.length === 0 || chart.maxValue <= 0)
                return
            // A few bars stay bar-shaped instead of filling the width.
            var slot = width / bars.length
            var barWidth = Math.max(1, Math.min(slot - Math.min(slot * 0.25, Theme.paddingSmall), Theme.itemSizeSmall))
            ctx.fillStyle = chart.barColor
            for (var i = 0; i < bars.length; i++) {
                var v = bars[i].value
                if (v === null || isNaN(v) || v <= 0)
                    continue
                var h = Math.max(1, v / chart.maxValue * height)
                ctx.fillRect(i * slot + (slot - barWidth) / 2, height - h, barWidth, h)
            }

            ctx.strokeStyle = Theme.rgba(Theme.secondaryColor, 0.3)
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.moveTo(0, height - 0.5)
            ctx.lineTo(width, height - 0.5)
            ctx.stroke()

            if (!isNaN(chart.reference) && chart.reference > 0) {
                var y = Math.round(height - chart.reference / chart.maxValue * height) + 0.5
                ctx.strokeStyle = Theme.secondaryHighlightColor
                ctx.lineWidth = Math.max(1, Math.round(Theme.pixelRatio))
                var dash = Theme.paddingSmall
                for (var x = 0; x < width; x += 2 * dash) {
                    ctx.beginPath()
                    ctx.moveTo(x, y)
                    ctx.lineTo(Math.min(width, x + dash), y)
                    ctx.stroke()
                }
            }
        }
    }

    Item {
        id: labels
        anchors.bottom: parent.bottom
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        height: firstLabel.height
        Label {
            id: firstLabel
            font.pixelSize: Theme.fontSizeTiny
            color: Theme.secondaryColor
            text: chart.bars.length ? chart.bars[0].label : ""
        }
        Label {
            anchors.right: parent.right
            visible: chart.bars.length > 1
            font.pixelSize: Theme.fontSizeTiny
            color: Theme.secondaryColor
            text: visible ? chart.bars[chart.bars.length - 1].label : ""
        }
    }
}
