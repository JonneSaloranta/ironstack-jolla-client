import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"

// The web's guided tours as a guide to read: every tour by section, in
// the IronStack profile's language. A tour opens with its steps and is
// marked done - completion is shared with the web, so a tour read here
// doesn't start there.
Page {
    id: page

    property var tours: []

    // A ListModel, for the section headings.
    ListModel {
        id: rows
    }
    property bool loading: false
    property string errorText: ""

    function load(keepError) {
        loading = true
        api.request("GET", "tutorials/", null, function(ok, status, data, error) {
            loading = false
            errorText = ok ? (keepError || "") : error
            if (!ok)
                return
            tours = data || []
            rows.clear()
            tours.forEach(function(t, index) {
                rows.append({ index_: index, section: t.section, title: t.title, completed: t.completed === true })
            })
        })
    }

    Component.onCompleted: load()
    onStatusChanged: {
        if (status === PageStatus.Active && tours.length)
            load()
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: rows
        section.property: "section"
        section.delegate: SectionHeader { text: section }

        PullDownMenu {
            busy: page.loading
            MenuItem {
                text: qsTr("Mark all as unread")
                onClicked: api.request("POST", "tutorials/reset/", null, function(ok, status, data, error) {
                    page.load(ok ? "" : error)
                })
            }
        }

        header: Column {
            width: list.width
            PageHeader {
                title: qsTr("Guide")
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }
        }

        delegate: ListItem {
            contentHeight: Theme.itemSizeSmall
            onClicked: pageStack.push(Qt.resolvedUrl("TourPage.qml"), { tour: page.tours[model.index_] })
            Label {
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin - doneIcon.width
                truncationMode: TruncationMode.Fade
                color: model.completed ? Theme.secondaryColor : Theme.primaryColor
                text: model.title
            }
            Icon {
                id: doneIcon
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                visible: model.completed
                source: "image://theme/icon-s-accept"
            }
        }

        VerticalScrollDecorator {}
    }
}
