import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/store.js" as Store

// Countdown for the running rest period (settings.restEndsAt), with
// "+30 s" and "Skip". Hidden when no rest is running.
Item {
    id: root

    property real remaining: 0
    readonly property bool running: settings.restEndsAt > 0

    function update() {
        remaining = Math.max(0, (settings.restEndsAt - Date.now()) / 1000)
    }

    width: parent ? parent.width : 0
    height: running ? Theme.itemSizeMedium : 0
    visible: running
    clip: true

    Behavior on height { NumberAnimation { duration: 150 } }

    Timer {
        interval: 250
        repeat: true
        triggeredOnStart: true
        running: root.running && Qt.application.active
        onTriggered: root.update()
    }

    Label {
        id: countdown
        anchors.verticalCenter: parent.verticalCenter
        x: Theme.horizontalPageMargin
        font.pixelSize: Theme.fontSizeExtraLarge
        color: Theme.highlightColor
        text: Store.formatDuration(Math.ceil(root.remaining))
    }

    Label {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: countdown.right
        anchors.leftMargin: Theme.paddingMedium
        color: Theme.secondaryHighlightColor
        text: qsTr("rest")
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: Theme.horizontalPageMargin
        spacing: Theme.paddingMedium

        Button {
            preferredWidth: Theme.buttonWidthExtraSmall
            text: qsTr("+30 s")
            onClicked: settings.restEndsAt = settings.restEndsAt + 30000
        }
        Button {
            preferredWidth: Theme.buttonWidthExtraSmall
            text: qsTr("Skip")
            onClicked: settings.restEndsAt = 0
        }
    }
}
