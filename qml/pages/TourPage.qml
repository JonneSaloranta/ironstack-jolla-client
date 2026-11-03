import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"

// One of the web's guided tours, its steps one after another. Opening it
// marks it done, shared with the web.
Page {
    id: page

    property var tour

    Component.onCompleted: {
        if (!tour.completed)
            api.request("POST", "tutorials/" + tour.key + "/complete/", null, function() {})
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                text: qsTr("Mark as unread")
                onClicked: api.request("POST", "tutorials/" + page.tour.key + "/reset/", null, function() {
                    pageStack.pop()
                })
            }
        }

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: page.tour.title
                description: page.tour.section
            }
            Repeater {
                model: page.tour.steps
                delegate: Column {
                    x: Theme.horizontalPageMargin
                    width: page.width - 2 * Theme.horizontalPageMargin
                    Label {
                        width: parent.width
                        wrapMode: Text.Wrap
                        color: Theme.highlightColor
                        text: modelData.title
                    }
                    Label {
                        width: parent.width
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeSmall
                        text: modelData.body
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
