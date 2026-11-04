import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Share 1.0

// The app's own log (appLog, src/logger.cpp): the newest lines here, all
// of it with a few lines about the app and the phone when copied or
// shared - for sending to whoever looks into a problem.
Page {
    id: page

    // Lines shown: a long log as one Label gets slow to lay out.
    readonly property int shownLines: 400

    property string shown: ""
    property int totalLines: 0
    // Kept at the newest line while the text is laid out, until the user
    // scrolls.
    property bool followEnd: true

    function load() {
        var lines = appLog.text().split("\n")
        if (lines.length && lines[lines.length - 1] === "")
            lines.pop()
        totalLines = lines.length
        shown = lines.slice(-shownLines).join("\n")
        followEnd = true
        toEnd()
    }

    function toEnd() {
        flickable.contentY = Math.max(0, flickable.contentHeight - flickable.height)
    }

    function fileName() {
        return "ironstack-log-" + Qt.formatDateTime(new Date(), "yyyyMMdd-HHmm") + ".txt"
    }

    function copy() {
        Clipboard.text = appLog.report()
        copiedNotice.show()
    }

    function share() {
        shareAction.resources = [{ "data": appLog.report(), "name": fileName(), "type": "text/plain" }]
        shareAction.trigger()
    }

    Component.onCompleted: load()

    ShareAction {
        id: shareAction
        mimeType: "text/plain"
        title: qsTr("Share app log")
    }

    SilicaFlickable {
        id: flickable
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge
        onContentHeightChanged: if (page.followEnd) page.toEnd()
        onHeightChanged: if (page.followEnd) page.toEnd()
        onMovementStarted: page.followEnd = false

        PullDownMenu {
            MenuItem {
                text: qsTr("Clear log")
                enabled: page.totalLines > 0
                onClicked: remorse.execute(qsTr("Clearing the log"), function() {
                    appLog.clear()
                    page.load()
                })
            }
            MenuItem {
                text: qsTr("Share")
                onClicked: page.share()
            }
            MenuItem {
                text: qsTr("Copy to clipboard")
                onClicked: page.copy()
            }
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.load()
            }
        }

        // The page opens at the newest line, far from the pull-down menu.
        PushUpMenu {
            MenuItem {
                text: qsTr("Copy to clipboard")
                onClicked: page.copy()
            }
            MenuItem {
                text: qsTr("Share")
                onClicked: page.share()
            }
        }

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: qsTr("App log")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: (page.totalLines > page.shownLines
                       ? qsTr("The newest %1 of %2 lines. Copy and Share take all of them, with the app "
                              + "and system versions.").arg(page.shownLines).arg(page.totalLines)
                       : qsTr("Copy and Share add the app and system versions."))
                      + " " + qsTr("It lists the requests made to your server and how they went, never "
                                   + "your API key or anything you've logged.")
            }

            Label {
                visible: page.totalLines > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                font.family: "monospace"
                font.pixelSize: Theme.fontSizeTiny
                color: Theme.highlightColor
                textFormat: Text.PlainText
                text: page.shown
            }
        }

        ViewPlaceholder {
            enabled: page.totalLines === 0
            text: qsTr("The log is empty")
            hintText: qsTr("To see more here, choose Info or Debug under Settings > App log.")
        }

        VerticalScrollDecorator {}
    }

    // Silica's own "Copied" notice.
    Notice {
        id: copiedNotice
        text: qsTr("Copied")
        duration: Notice.Short
    }

    RemorsePopup {
        id: remorse
    }
}
