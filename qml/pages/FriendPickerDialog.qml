import QtQuick 2.0
import Sailfish.Silica 1.0

// Pick one person from a list ({ id, username }) - a friend to invite, a
// member to hand a group over to. The page that opened it reads `picked`.
Dialog {
    id: dialog

    property string title
    property var friends: []
    property var picked: null

    canAccept: picked !== null

    SilicaListView {
        anchors.fill: parent
        model: dialog.friends
        header: DialogHeader {
            acceptText: qsTr("Choose")
            title: dialog.title
        }
        delegate: ListItem {
            contentHeight: Theme.itemSizeSmall
            highlighted: down || (dialog.picked !== null && dialog.picked.id === modelData.id)
            onClicked: dialog.picked = modelData
            Label {
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                truncationMode: TruncationMode.Fade
                text: modelData.username
            }
        }
        ViewPlaceholder {
            enabled: dialog.friends.length === 0
            text: qsTr("Nobody to choose")
        }
    }
}
