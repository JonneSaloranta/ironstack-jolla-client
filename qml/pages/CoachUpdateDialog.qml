import QtQuick 2.6
import Sailfish.Silica 1.0

// What the coach's newer version changes in your copy, as the server's
// diff (like the web's update page): removed lines dimmed, added lines
// highlighted. Accepting replaces the copy's workouts and exercises; its
// name and description are kept (apps.coaching.services).
Dialog {
    id: dialog

    property string diff: ""

    // The server's JSON writes ä as \u00e4; shown as the letter.
    readonly property var lines: diff.replace(/\\u([0-9a-fA-F]{4})/g, function(all, hex) {
        return String.fromCharCode(parseInt(hex, 16))
    }).split("\n").filter(function(line) {
        return line !== "" && line.indexOf("---") !== 0 && line.indexOf("+++") !== 0
    })

    SilicaListView {
        anchors.fill: parent
        model: dialog.lines
        header: Column {
            width: parent ? parent.width : 0
            DialogHeader {
                acceptText: qsTr("Update")
                title: qsTr("Update from coach")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("The workouts and their exercises are replaced with your coach's latest version, also "
                           + "anything you changed in them; your name and description stay. Lines starting with - go, "
                           + "lines starting with + come in.")
            }
        }
        delegate: Label {
            readonly property string sign: modelData.charAt(0)
            x: Theme.horizontalPageMargin
            width: ListView.view.width - 2 * Theme.horizontalPageMargin
            wrapMode: Text.WrapAnywhere
            font.family: "monospace"
            font.pixelSize: Theme.fontSizeTiny
            color: sign === "+" ? Theme.highlightColor : sign === "-" ? Theme.secondaryColor
                                : sign === "@" ? Theme.secondaryHighlightColor : Theme.primaryColor
            font.strikeout: sign === "-"
            text: modelData
        }
        VerticalScrollDecorator {}
    }
}
