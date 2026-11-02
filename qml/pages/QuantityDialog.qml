import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/store.js" as Store

// An amount of something - a recipe ingredient, a diet plan item. The
// page that opened it reads `quantity`.
Dialog {
    id: dialog

    property string title
    property string unitLabel
    property real initialQuantity: 0
    readonly property real quantity: Store.parseNumber(field.text)

    canAccept: quantity > 0

    Column {
        width: parent.width

        DialogHeader {
            acceptText: qsTr("Save")
            title: dialog.title
        }
        TextField {
            id: field
            width: parent.width
            label: qsTr("Amount (%1)").arg(dialog.unitLabel)
            placeholderText: label
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            validator: RegExpValidator { regExp: /^(\d{1,5}([.,]\d{0,2})?)?$/ }
            text: dialog.initialQuantity > 0 ? String(dialog.initialQuantity) : ""
            EnterKey.enabled: dialog.canAccept
            EnterKey.iconSource: "image://theme/icon-m-enter-accept"
            EnterKey.onClicked: dialog.accept()
        }
    }
}
