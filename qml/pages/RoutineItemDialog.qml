import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/store.js" as Store

// One stretch in a routine: hold, sets and rest - the web's routine item
// form. An empty hold uses the stretch's own default. The page that opened
// it saves body().
Dialog {
    id: dialog

    property var item: null
    property int stretchId: item ? item.stretch : 0

    function integer(field) {
        var value = parseInt(field.text, 10)
        return isNaN(value) ? null : value
    }

    function body() {
        return {
            stretch: stretchId,
            hold_seconds: integer(holdField),
            sets: integer(setsField) || 1,
            rest_seconds: integer(restField) || 0
        }
    }

    canAccept: integer(setsField) > 0

    Column {
        width: parent.width

        DialogHeader {
            acceptText: qsTr("Save")
            title: Store.stretchName(dialog.stretchId)
        }
        TextField {
            id: holdField
            width: parent.width
            label: qsTr("Hold (seconds)")
            placeholderText: Store.stretches && Store.stretches[dialog.stretchId]
                             ? String(Store.stretches[dialog.stretchId].default_hold_seconds) : label
            inputMethodHints: Qt.ImhDigitsOnly
            validator: IntValidator { bottom: 1; top: 3600 }
            text: dialog.item && Store.present(dialog.item.hold_seconds) ? String(dialog.item.hold_seconds) : ""
            description: qsTr("Leave the hold empty to use the stretch's own default.")
        }
        TextField {
            id: setsField
            width: parent.width
            label: qsTr("Sets")
            placeholderText: label
            inputMethodHints: Qt.ImhDigitsOnly
            validator: IntValidator { bottom: 1; top: 20 }
            text: dialog.item ? String(dialog.item.sets) : "1"
        }
        TextField {
            id: restField
            width: parent.width
            label: qsTr("Rest (seconds)")
            placeholderText: label
            inputMethodHints: Qt.ImhDigitsOnly
            validator: IntValidator { bottom: 0; top: 3600 }
            text: dialog.item ? String(dialog.item.rest_seconds || 0) : "10"
        }
    }
}
