import QtQuick 2.6
import Sailfish.Silica 1.0

// Which of your clients a plan is shared with; tap to switch one on or
// off. The page that opened it reads `chosen` (user ids).
Dialog {
    id: dialog

    property var clients: []
    property var chosen: []

    function toggle(id) {
        var list = chosen.slice()
        var at = list.indexOf(id)
        if (at >= 0)
            list.splice(at, 1)
        else
            list.push(id)
        chosen = list
    }

    SilicaListView {
        anchors.fill: parent
        model: dialog.clients
        header: Column {
            width: parent ? parent.width : 0
            DialogHeader {
                acceptText: qsTr("Save")
                title: qsTr("Share with clients")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("A client sees it under Coaching and can import a copy; later changes reach that copy when "
                           + "they update it.")
            }
        }
        delegate: TextSwitch {
            text: modelData.display_name || modelData.username
            checked: dialog.chosen.indexOf(modelData.id) >= 0
            automaticCheck: false
            onClicked: dialog.toggle(modelData.id)
        }
        ViewPlaceholder {
            enabled: dialog.clients.length === 0
            text: qsTr("No clients")
        }
    }
}
