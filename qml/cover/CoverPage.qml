import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/store.js" as Store

CoverBackground {
    id: cover

    property bool hasSession: settings.activeSessionId >= 0
    property bool resting: settings.restEndsAt > 0
    property real elapsed: 0
    property real restRemaining: 0

    function tick() {
        elapsed = Store.elapsedSince(settings.activeSessionStarted)
        restRemaining = Math.max(0, (settings.restEndsAt - Date.now()) / 1000)
    }

    Timer {
        interval: 1000
        repeat: true
        running: cover.hasSession && cover.status === Cover.Active
        triggeredOnStart: true
        onTriggered: cover.tick()
    }

    Column {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.paddingLarge
        spacing: Theme.paddingSmall

        Label {
            visible: !cover.hasSession
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "IronStack"
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeLarge
        }

        Label {
            visible: cover.hasSession
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeSmall
            text: settings.activeSessionName || qsTr("Workout")
        }

        Label {
            visible: cover.hasSession
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: cover.resting ? Theme.fontSizeMedium : Theme.fontSizeExtraLarge
            color: cover.resting ? Theme.secondaryColor : Theme.primaryColor
            text: Store.formatDuration(cover.elapsed)
        }

        Label {
            visible: cover.resting
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Theme.fontSizeExtraLarge
            color: Theme.highlightColor
            text: Store.formatDuration(Math.ceil(cover.restRemaining))
        }

        Label {
            visible: cover.resting
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryHighlightColor
            text: qsTr("rest")
        }

        Label {
            visible: !cover.hasSession
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Theme.secondaryColor
            text: qsTr("No workout in progress")
        }
    }

    CoverActionList {
        enabled: cover.resting
        CoverAction {
            // +30 s
            iconSource: "image://theme/icon-cover-new"
            onTriggered: settings.restEndsAt = settings.restEndsAt + 30000
        }
        CoverAction {
            // skip
            iconSource: "image://theme/icon-cover-next"
            onTriggered: settings.restEndsAt = 0
        }
    }
}
