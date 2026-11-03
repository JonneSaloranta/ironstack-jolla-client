import QtQuick 2.0
import Sailfish.Silica 1.0

// A single name - a new activity type, a meal slot, a group's invite code. The page
// that opened it reads `name`.
Dialog {
    id: dialog

    property string title
    property string initialName: ""
    property string label: qsTr("Name")
    readonly property string name: nameField.text.trim()

    canAccept: name !== ""

    Column {
        width: parent.width

        DialogHeader {
            acceptText: qsTr("Save")
            title: dialog.title
        }
        TextField {
            id: nameField
            width: parent.width
            label: dialog.label
            placeholderText: label
            text: dialog.initialName
            EnterKey.enabled: dialog.canAccept
            EnterKey.iconSource: "image://theme/icon-m-enter-accept"
            EnterKey.onClicked: dialog.accept()
        }
    }
}
