import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

// A new program or changes to one (`program` set) - the web's program
// form. The page that opened it sends body() and shows any error.
Dialog {
    id: dialog

    property var program: null

    function body() {
        return {
            name: nameField.text.trim(),
            description: descriptionArea.text,
            is_continuous: continuousSwitch.checked,
            is_template: templateSwitch.checked
        }
    }

    canAccept: nameField.text.trim() !== ""

    SilicaFlickable {
        id: flickable
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            DialogHeader {
                acceptText: qsTr("Save")
                title: dialog.program ? qsTr("Edit program") : qsTr("New program")
            }
            TextField {
                id: nameField
                width: parent.width
                label: qsTr("Name")
                placeholderText: label
                text: dialog.program ? dialog.program.name : ""
            }
            TextArea {
                id: descriptionArea
                width: parent.width
                label: qsTr("Description")
                placeholderText: label
                text: dialog.program ? dialog.program.description || "" : ""
            }
            TextSwitch {
                id: continuousSwitch
                text: qsTr("Continuous - no fixed weekdays")
                checked: dialog.program ? dialog.program.is_continuous : false
            }
            TextSwitch {
                id: templateSwitch
                text: qsTr("Save as a personal template")
                checked: dialog.program ? dialog.program.is_template : false
            }
            KeyboardRoom {
                flickable: flickable
            }
        }

        VerticalScrollDecorator {}
    }
}
