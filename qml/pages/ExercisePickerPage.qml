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

    // The whole library is fetched once and searched here, matching both
    // the name as shown (translated, see Store.contentName) and as stored.
    // The API's own ?search= would match the IronStack profile's language,
    // which isn't necessarily the one this phone shows. The view keeps one
    // ListModel that is refilled in place: swapping the view's model on
    // every keystroke reset the list and took focus from the search field.
    ListModel {
        id: filteredModel
    }

    function applyFilter() {
        var term = searchText.toLowerCase()
        filteredModel.clear()
        for (var i = 0; i < exercises.length; i++) {
            if (!term || exercises[i].name.toLowerCase().indexOf(term) >= 0
                    || exercises[i].storedName.toLowerCase().indexOf(term) >= 0)
                filteredModel.append(exercises[i])
        }
    }

    onSearchTextChanged: applyFilter()

    function load() {
        loading = true
        errorText = ""
        var all = []
        Store.fetchAll(api, "exercises/?page_size=100", function(results) {
            all = all.concat(results.map(function(e) {
                return { id: e.id, name: Store.contentName(e.name), storedName: e.name }
            }))
        }, function(ok, error) {
            loading = false
            if (!ok) {
                errorText = error
                return
            }
            all.sort(function(a, b) { return a.name.localeCompare(b.name) })
            exercises = all
            applyFilter()
        })
    }

    Component.onCompleted: load()

    SilicaListView {
        id: list
        anchors.fill: parent
        model: filteredModel
        currentIndex: -1

        header: Column {
            width: parent.width
            PageHeader {
                title: qsTr("Add exercise")
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
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
                page.selected(model.id)
                pageStack.pop()
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                truncationMode: TruncationMode.Fade
                text: Theme.highlightText(model.name, page.searchText, Theme.highlightColor)
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
