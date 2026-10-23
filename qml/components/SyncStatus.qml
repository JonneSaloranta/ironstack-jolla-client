import QtQuick 2.0
import Sailfish.Silica 1.0

// "2 changes saved on this phone" while the sync queue has items. Tap to
// send now instead of waiting for the next automatic try.
BackgroundItem {
    width: parent ? parent.width : 0
    height: visible ? Math.max(Theme.itemSizeSmall, column.height + 2 * Theme.paddingSmall) : 0
    visible: syncQueue.count > 0
    onClicked: syncQueue.flush()

    Icon {
        id: icon
        anchors.verticalCenter: parent.verticalCenter
        x: Theme.horizontalPageMargin
        source: "image://theme/icon-s-sync"
        color: Theme.highlightColor
    }

    Column {
        id: column
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: icon.right
        anchors.leftMargin: Theme.paddingMedium
        anchors.right: parent.right
        anchors.rightMargin: Theme.horizontalPageMargin

        Label {
            width: parent.width
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.highlightColor
            text: syncQueue.syncing ? qsTr("Sending...")
                                    : qsTr("%n change(s) saved on this phone", "", syncQueue.count)
        }
        Label {
            width: parent.width
            visible: !syncQueue.syncing && syncQueue.lastError.length > 0
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryHighlightColor
            text: qsTr("Sent when the server can be reached. Tap to try now.")
        }
    }
}
