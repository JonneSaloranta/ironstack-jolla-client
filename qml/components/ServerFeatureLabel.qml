import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/features.js" as Features

// The line under something dimmed in standalone mode: what it needs.
Label {
    property string feature

    font.pixelSize: Theme.fontSizeExtraSmall
    color: Theme.secondaryColor
    truncationMode: TruncationMode.Fade
    text: Features.comingLater(feature) ? qsTr("Not without a server yet")
                                        : qsTr("Needs an IronStack server")
}
