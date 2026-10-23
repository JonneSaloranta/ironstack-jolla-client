import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: page

    property var program

    function weekdayName(index) {
        // Django weekday: 0 = Monday. Qt.locale().dayName: 0 = Sunday.
        return Qt.locale().dayName((index + 1) % 7, Locale.ShortFormat)
    }

    SilicaListView {
        anchors.fill: parent
        model: page.program ? page.program.workouts : []

        header: Column {
            width: parent.width
            PageHeader {
                title: page.program ? page.program.name : ""
                description: page.program && page.program.is_continuous ? qsTr("Continuous program") : ""
            }
            Label {
                visible: text.length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: page.program ? (page.program.description || "") : ""
            }
        }

        delegate: ListItem {
            // Grows with the text size setting instead of clipping it.
            contentHeight: Math.max(Theme.itemSizeMedium, textColumn.height + 2 * Theme.paddingMedium)
            onClicked: pageStack.push(Qt.resolvedUrl("WorkoutPage.qml"), { workout: modelData })

            Column {
                id: textColumn
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    text: modelData.name
                }
                Label {
                    width: parent.width
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    text: qsTr("%n exercise(s)", "", modelData.prescriptions.length)
                          + (modelData.scheduled_weekday !== null && modelData.scheduled_weekday !== undefined
                             ? " - " + page.weekdayName(modelData.scheduled_weekday) : "")
                }
            }
        }

        ViewPlaceholder {
            enabled: page.program && page.program.workouts.length === 0
            text: qsTr("No workouts in this program")
        }

        VerticalScrollDecorator {}
    }
}
