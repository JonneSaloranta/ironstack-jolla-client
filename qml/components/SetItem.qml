import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/store.js" as Store

// One logged set: number (W for a warm-up), weight x reps and extras. A set
// still waiting in the sync queue is dimmed with a sync icon.
ListItem {
    id: item

    property var set

    contentHeight: Theme.itemSizeSmall

    Label {
        id: numberLabel
        anchors.verticalCenter: parent.verticalCenter
        x: Theme.horizontalPageMargin
        width: Theme.itemSizeExtraSmall
        color: Theme.secondaryColor
        text: item.set ? (item.set.is_warmup ? "W" : item.set.set_number) : ""
    }

    Label {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: numberLabel.right
        anchors.right: pendingIcon.visible ? pendingIcon.left : parent.right
        anchors.rightMargin: Theme.horizontalPageMargin
        truncationMode: TruncationMode.Fade
        opacity: item.set && item.set.pending ? Theme.opacityHigh : 1.0
        color: item.set && item.set.is_warmup ? Theme.secondaryColor : Theme.primaryColor
        text: {
            var s = item.set
            if (!s)
                return ""
            return Store.formatWeight(s.weight, settings.unitSystem) + " x " + s.reps
                    + (s.rpe ? "  RPE " + parseFloat(s.rpe) : "")
                    + (s.rir !== null && s.rir !== undefined ? "  RIR " + s.rir : "")
                    + (s.is_failure ? "  " + qsTr("failure") : "")
        }
    }

    Icon {
        id: pendingIcon
        visible: item.set && item.set.pending === true
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: Theme.horizontalPageMargin
        source: "image://theme/icon-s-sync"
    }
}
