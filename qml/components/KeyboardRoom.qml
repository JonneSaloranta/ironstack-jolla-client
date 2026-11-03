import QtQuick 2.0

// Room for the keyboard at the end of a dialog's form, kept after the
// keyboard closes until the form is next dragged.
//
// Why: tapping Save (or Cancel) with the keyboard open first closes the
// keyboard, which gives the page its full height back. If the form was
// scrolled to show a field above the keyboard, the content then no longer
// reaches that far and slides back under the finger - the flickable takes
// that for a drag and the tap never reaches the button, so the first tap
// on Save did nothing. With this room the content stays where it is.
//
// Put it last in the flickable's column and set `flickable`.
Item {
    id: room

    property Flickable flickable

    function keyboardHeight() {
        var r = Qt.inputMethod.keyboardRectangle
        // The rectangle is in screen coordinates; in landscape the
        // keyboard's height is its width there.
        return Math.min(r.width, r.height)
    }
    function grow() {
        if (Qt.inputMethod.visible)
            height = Math.max(height, keyboardHeight())
    }

    width: 1
    height: 0

    Connections {
        target: Qt.inputMethod
        onVisibleChanged: room.grow()
        onKeyboardRectangleChanged: room.grow()
    }
    Connections {
        target: room.flickable
        onMovementStarted: {
            if (!Qt.inputMethod.visible)
                room.height = 0
        }
    }
}
