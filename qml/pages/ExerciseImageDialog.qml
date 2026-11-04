import QtQuick 2.6
import Sailfish.Silica 1.0

// A picked image for one of your own exercises, with an optional caption,
// before it's uploaded (exercises/<id>/images/, IronStack #48). The page
// that opened it reads `caption`.
Dialog {
    id: dialog

    property url source
    readonly property string caption: captionField.text.trim()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium

            DialogHeader {
                acceptText: qsTr("Upload")
                title: qsTr("Add image")
            }
            Image {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: Math.min(implicitHeight * width / Math.max(implicitWidth, 1), dialog.height / 2)
                fillMode: Image.PreserveAspectFit
                autoTransform: true
                asynchronous: true
                // Only as big as it's shown, not the camera's full size.
                sourceSize.width: width
                source: dialog.source
            }
            TextField {
                id: captionField
                width: parent.width
                label: qsTr("Caption (optional)")
                placeholderText: label
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: dialog.accept()
            }
        }
    }
}
