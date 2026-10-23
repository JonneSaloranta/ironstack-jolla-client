import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

Page {
    id: page

    signal selected(int exerciseId)

    property var exercises: []
    property bool loading: true
    property string errorText: ""

    property string searchText: ""

    // The API has no search parameter yet (IronStack issue #18), so the
    // whole library is fetched and filtered here.
    function filtered() {
        var term = searchText.toLowerCase()
        if (!term)
            return exercises
        return exercises.filter(function(e) { return e.name.toLowerCase().indexOf(term) >= 0 })
    }

    Component.onCompleted: {
        var all = []
        Store.fetchAll(api, "exercises/", function(results) {
            all = all.concat(results.map(function(e) { return { id: e.id, name: e.name } }))
        }, function(ok, error) {
            loading = false
            if (!ok) {
                errorText = error
                return
            }
            Store.rememberExercises(all)
            exercises = all
        })
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: page.filtered()
        currentIndex: -1

        header: Column {
            width: parent.width
            PageHeader {
                title: qsTr("Add exercise")
            }
            ErrorBanner {
                text: page.errorText
            }
            SearchField {
                id: searchField
                width: parent.width
                placeholderText: qsTr("Search")
                onTextChanged: page.searchText = text
            }
        }

        delegate: BackgroundItem {
            width: list.width
            onClicked: {
                page.selected(modelData.id)
                pageStack.pop()
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                truncationMode: TruncationMode.Fade
                text: Theme.highlightText(modelData.name, page.searchText, Theme.highlightColor)
                textFormat: Text.StyledText
            }
        }

        ViewPlaceholder {
            enabled: !page.loading && list.count === 0 && page.errorText === ""
            text: qsTr("No matching exercises")
        }

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: page.loading
        }

        VerticalScrollDecorator {}
    }
}
