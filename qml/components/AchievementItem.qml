import QtQuick 2.0
import Sailfish.Silica 1.0

// One analytics/achievements/ highlight: "🔥 Longest streak  12 days" and
// who it belongs to. Label and value come from the server as text.
Item {
    property var achievement

    // Same icons as the web's achievements carousel.
    function iconText(icon) {
        if (icon === "streak")
            return "🔥"
        if (icon === "workouts")
            return "💪"
        if (icon === "pr")
            return "🏆"
        if (icon === "volume")
            return "⚡"
        return ""
    }

    width: parent ? parent.width : 0
    height: Math.max(Theme.itemSizeMedium, textColumn.height + 2 * Theme.paddingMedium)

    Label {
        id: iconLabel
        anchors.verticalCenter: parent.verticalCenter
        x: Theme.horizontalPageMargin
        width: Theme.iconSizeMedium
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Theme.fontSizeLarge
        text: achievement ? iconText(achievement.icon) : ""
    }

    Column {
        id: textColumn
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: iconLabel.right
        anchors.leftMargin: Theme.paddingMedium
        anchors.right: parent.right
        anchors.rightMargin: Theme.horizontalPageMargin
        Row {
            width: parent.width
            Label {
                width: parent.width - valueLabel.width
                truncationMode: TruncationMode.Fade
                text: achievement ? achievement.label : ""
            }
            Label {
                id: valueLabel
                color: Theme.highlightColor
                text: achievement ? achievement.value : ""
            }
        }
        // One line, so the row keeps its height as the achievements rotate.
        Label {
            width: parent.width
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
            text: achievement ? achievement.display_name : ""
        }
    }
}
