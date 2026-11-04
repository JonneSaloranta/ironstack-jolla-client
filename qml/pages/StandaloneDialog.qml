import QtQuick 2.0
import Sailfish.Silica 1.0

// What using the app without a server means, before it's switched on
// (docs/STANDALONE.md).
Dialog {
    id: dialog

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            DialogHeader {
                acceptText: qsTr("Start")
                title: qsTr("Use without a server")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.highlightColor
                text: qsTr("Everything you log is kept on this phone only. Back it up now and then: there's no "
                           + "copy anywhere else.")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Training works as with a server: IronStack's exercises and program templates, your "
                           + "own programs, training mode with weight suggestions, history, records and progress. "
                           + "Body tracking and nutrition come to this mode in later versions.")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Friends and groups, coaching, the AI assistant and food search need an IronStack "
                           + "server. They're shown dimmed so you know they're there; Settings can hide them.")
            }
        }
    }
}
