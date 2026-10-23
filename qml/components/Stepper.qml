import QtQuick 2.0
import Sailfish.Silica 1.0

// [ - ]  value field  [ + ] with big touch targets - one-handed, between sets.
// The field is the child item.
Item {
    id: stepper

    default property alias content: middle.data
    property Item field

    signal decrease()
    signal increase()

    height: Math.max(Theme.itemSizeLarge, middle.childrenRect.height)

    IconButton {
        id: minus
        anchors.left: parent.left
        anchors.leftMargin: Theme.paddingSmall
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.itemSizeLarge
        height: Theme.itemSizeLarge
        icon.source: "image://theme/icon-m-remove"
        onClicked: stepper.decrease()
    }

    Item {
        id: middle
        anchors.left: minus.right
        anchors.right: plus.left
        anchors.verticalCenter: parent.verticalCenter
        height: childrenRect.height
    }

    IconButton {
        id: plus
        anchors.right: parent.right
        anchors.rightMargin: Theme.paddingSmall
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.itemSizeLarge
        height: Theme.itemSizeLarge
        icon.source: "image://theme/icon-m-add"
        onClicked: stepper.increase()
    }
}
