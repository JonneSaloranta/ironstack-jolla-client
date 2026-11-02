import QtQuick 2.0
import Sailfish.Silica 1.0

// A measurement type of your own - the web's "New measurement type": a
// name and what kind of value it is. The page that opened it saves body().
Dialog {
    id: dialog

    readonly property var kinds: ["weight", "length", "percentage"]

    function body() {
        return { name: nameField.text.trim(), unit_kind: kinds[kindBox.currentIndex] }
    }

    canAccept: nameField.text.trim() !== ""

    Column {
        width: parent.width

        DialogHeader {
            acceptText: qsTr("Save")
            title: qsTr("New measurement type")
        }
        TextField {
            id: nameField
            width: parent.width
            label: qsTr("Name")
            placeholderText: label
            focus: true
        }
        ComboBox {
            id: kindBox
            label: qsTr("Unit kind")
            menu: ContextMenu {
                MenuItem { text: qsTr("Weight") }
                MenuItem { text: qsTr("Length/circumference") }
                MenuItem { text: qsTr("Percentage") }
            }
        }
    }
}
