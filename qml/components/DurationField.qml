import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/store.js" as Store

// Hours and minutes (and seconds when `withSeconds`) for a duration the API
// takes as "HH:MM:SS". `seconds` reads and writes the total.
Row {
    id: field

    property string label: ""
    property bool withSeconds: false
    property int seconds: 0
    readonly property bool acceptable: hours.acceptableInput && minutes.acceptableInput
                                       && (!withSeconds || secs.acceptableInput)

    function value(input) {
        return parseInt(input.text, 10) || 0
    }
    function recompute() {
        seconds = value(hours) * 3600 + value(minutes) * 60 + (withSeconds ? value(secs) : 0)
    }
    function show() {
        hours.text = Math.floor(seconds / 3600) || ""
        minutes.text = Math.floor((seconds % 3600) / 60) || ""
        secs.text = seconds % 60 || ""
    }

    Component.onCompleted: show()
    // An outside change (loading an entry to edit) refreshes the fields.
    onSecondsChanged: {
        if (!hours.activeFocus && !minutes.activeFocus && !secs.activeFocus)
            show()
    }

    width: parent ? parent.width : 0

    TextField {
        id: hours
        width: field.width / (field.withSeconds ? 3 : 2)
        label: field.label ? field.label + " (" + qsTr("h") + ")" : qsTr("h")
        placeholderText: "0"
        inputMethodHints: Qt.ImhDigitsOnly
        validator: IntValidator { bottom: 0; top: 999 }
        onTextChanged: if (activeFocus) field.recompute()
    }
    TextField {
        id: minutes
        width: hours.width
        label: qsTr("min")
        placeholderText: "0"
        inputMethodHints: Qt.ImhDigitsOnly
        validator: IntValidator { bottom: 0; top: 59 }
        onTextChanged: if (activeFocus) field.recompute()
    }
    TextField {
        id: secs
        visible: field.withSeconds
        width: hours.width
        label: qsTr("s")
        placeholderText: "0"
        inputMethodHints: Qt.ImhDigitsOnly
        validator: IntValidator { bottom: 0; top: 59 }
        onTextChanged: if (activeFocus) field.recompute()
    }
}
