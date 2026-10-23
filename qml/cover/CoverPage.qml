import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/store.js" as Store

CoverBackground {
    id: cover

    property bool hasSession: settings.activeSessionId >= 0
    property real elapsed: 0

    function tick() {
        elapsed = Store.elapsedSince(settings.activeSessionStarted)
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
            text: settings.activeSessionName || qsTr("Workout")
        }

        Label {
            visible: cover.hasSession
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Theme.fontSizeExtraLarge
            text: Store.formatDuration(cover.elapsed)
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
}
