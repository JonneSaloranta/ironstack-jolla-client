import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/store.js" as Store

ListItem {
    property var record

    // Every record type's value is kg except rep_pr, a plain rep count
    // (apps.records.services.display_value on the server).
    function valueText() {
        return record ? Store.recordValueText(record, settings.unitSystem, "%1 " + qsTr("reps")) : ""
    }

    // Grows with the text size setting instead of clipping it.
    contentHeight: Math.max(Theme.itemSizeMedium, textColumn.height + 2 * Theme.paddingMedium)
    width: parent ? parent.width : 0

    Column {
        id: textColumn
        anchors.verticalCenter: parent.verticalCenter
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        Row {
            width: parent.width
            Label {
                width: parent.width - valueLabel.width
                truncationMode: TruncationMode.Fade
                text: record ? Store.shown(record, "exercise_name") : ""
            }
            Label {
                id: valueLabel
                color: Theme.highlightColor
                text: valueText()
            }
        }
        // Wraps rather than fades: the date comes last and is what a fade
        // would cut off (long in Finnish, "1. marraskuuta 2026").
        Label {
            width: parent.width
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
            //: Rep-max, e.g. "5RM" = best weight for 5 reps
            text: record ? Store.recordLabel(record, qsTr("%1RM"))
                           + (record.weight ? " - " + Store.formatWeight(record.weight, settings.unitSystem)
                                              + " x " + record.reps : "")
                           + " - " + Format.formatDate(new Date(record.achieved_at), Formatter.DateMedium)
                         : ""
        }
    }
}
