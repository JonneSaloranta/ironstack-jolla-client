import QtQuick 2.0
import Sailfish.Silica 1.0

Column {
    property alias value: valueLabel.text
    property alias label: captionLabel.text

    Label {
        id: valueLabel
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Theme.fontSizeLarge
        color: Theme.highlightColor
    }
    Label {
        id: captionLabel
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Theme.fontSizeExtraSmall
        color: Theme.secondaryColor
        wrapMode: Text.Wrap
    }
}
