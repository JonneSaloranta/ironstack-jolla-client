import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/store.js" as Store

// The smart weight suggestion for an exercise's first set, as the web's
// training panel shows it: "Suggested: 52.5 kg x 5 - High confidence" and
// the reason underneath (already in the user's language from the server).
// Hidden when there's no suggested weight or a set has been logged.
Column {
    id: root

    property var suggestion: null
    property var pe: null
    property int alignment: Text.AlignHCenter

    function confidenceText(confidence) {
        if (confidence === "low")
            return qsTr("Low confidence")
        if (confidence === "medium")
            return qsTr("Medium confidence")
        if (confidence === "high")
            return qsTr("High confidence")
        return ""
    }

    readonly property string headline: Store.suggestionText(suggestion, settings.unitSystem, qsTr("Suggested: %1"))

    visible: headline !== "" && pe !== null && Store.workingSetCount(pe) === 0
    x: Theme.horizontalPageMargin
    width: (parent ? parent.width : 0) - 2 * Theme.horizontalPageMargin

    Label {
        width: parent.width
        horizontalAlignment: root.alignment
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.highlightColor
        text: {
            var confidence = root.suggestion ? root.confidenceText(root.suggestion.confidence) : ""
            return root.headline + (confidence ? " - " + confidence : "")
        }
    }
    Label {
        visible: text !== ""
        width: parent.width
        horizontalAlignment: root.alignment
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSizeExtraSmall
        color: Theme.secondaryHighlightColor
        text: root.suggestion && root.suggestion.reason ? root.suggestion.reason : ""
    }
}
