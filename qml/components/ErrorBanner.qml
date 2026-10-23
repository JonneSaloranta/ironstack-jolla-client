import QtQuick 2.0
import Sailfish.Silica 1.0

// Inline error text with a retry hint; empty text hides it.
Label {
    x: Theme.horizontalPageMargin
    width: parent.width - 2 * Theme.horizontalPageMargin
    visible: text.length > 0
    wrapMode: Text.Wrap
    color: Theme.errorColor
    font.pixelSize: Theme.fontSizeSmall
}
