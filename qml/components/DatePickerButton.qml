import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/store.js" as Store

// A form row showing a date; tapping it opens Silica's date picker.
// `date` is a JS Date (local midnight); `isoDate` the API's "YYYY-MM-DD".
ValueButton {
    id: button

    property date date: new Date()
    readonly property string isoDate: Store.isoDate(date)

    // Picked a different day.
    signal picked()

    value: Format.formatDate(date, Formatter.DateLong)
    onClicked: {
        var dialog = pageStack.push("Sailfish.Silica.DatePickerDialog", { date: button.date })
        dialog.accepted.connect(function() {
            button.date = dialog.date
            button.picked()
        })
    }
}
