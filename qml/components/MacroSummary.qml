import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/nutrition.js" as Nutrition

// Calories and macros eaten against the daily target, like the web's
// "Today so far" card: kcal with the share of the target as a bar, then
// protein, carbohydrates and fat. `totals` from Nutrition.total(),
// `target` a nutrition-targets/ row or null.
Column {
    id: summary

    property var totals: Nutrition.zero()
    property var target: null

    readonly property int percent: target ? Nutrition.percentOf(totals.calories, target.daily_calories) : 0

    x: Theme.horizontalPageMargin
    width: (parent ? parent.width : 0) - 2 * Theme.horizontalPageMargin
    spacing: Theme.paddingSmall

    Row {
        width: parent.width
        Label {
            width: parent.width - percentLabel.width
            font.pixelSize: Theme.fontSizeLarge
            color: Theme.highlightColor
            text: Math.round(summary.totals.calories) + (summary.target ? " / " + summary.target.daily_calories : "")
                  + " kcal"
        }
        Label {
            id: percentLabel
            anchors.baseline: parent.children[0].baseline
            visible: summary.target !== null
            color: Theme.secondaryHighlightColor
            text: summary.percent + " %"
        }
    }

    // The share of the daily calories as a bar.
    Rectangle {
        visible: summary.target !== null
        width: parent.width
        height: Theme.paddingSmall
        radius: height / 2
        color: Theme.rgba(Theme.secondaryColor, 0.2)
        Rectangle {
            width: parent.width * Math.min(1, summary.percent / 100)
            height: parent.height
            radius: parent.radius
            color: summary.percent > 100 ? Theme.errorColor : Theme.highlightColor
        }
    }

    Row {
        width: parent.width
        Repeater {
            model: [
                { label: qsTr("Protein"), value: summary.totals.protein_grams,
                  target: summary.target ? summary.target.protein_grams : null },
                { label: qsTr("Carbohydrates"), value: summary.totals.carbohydrate_grams,
                  target: summary.target ? summary.target.carbohydrate_grams : null },
                { label: qsTr("Fat"), value: summary.totals.fat_grams,
                  target: summary.target ? summary.target.fat_grams : null }
            ]
            delegate: Column {
                width: summary.width / 3
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Theme.highlightColor
                    text: Math.round(modelData.value)
                          + (modelData.target ? " / " + Math.round(parseFloat(modelData.target)) : "") + " g"
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    text: modelData.label
                }
            }
        }
    }
}
