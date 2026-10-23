import QtQuick 2.6
import Sailfish.Silica 1.0

// An error in plain words, and - where repeating the request makes sense -
// a "Try again" button. Empty text hides it.
Column {
    id: banner

    property alias text: label.text
    property bool showRetry: false

    signal retry()

    x: Theme.horizontalPageMargin
    width: parent.width - 2 * Theme.horizontalPageMargin
    visible: label.text.length > 0
    spacing: Theme.paddingSmall
    bottomPadding: Theme.paddingMedium

    Label {
        id: label
        width: parent.width
        wrapMode: Text.Wrap
        color: Theme.errorColor
        font.pixelSize: Theme.fontSizeSmall
    }

    Button {
        visible: banner.showRetry
        text: qsTr("Try again")
        onClicked: banner.retry()
    }
}
