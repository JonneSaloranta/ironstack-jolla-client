import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

// The exercise library. Two uses: browsing (the default - a tap opens the
// exercise), or picking one for a session or a program (`picking: true` -
// a tap emits selected() and closes the page).
Page {
    id: page

    property bool picking: false
    signal selected(int exerciseId)

    property var exercises: []
    property bool loading: true
    property string errorText: ""

    property string searchText: ""
    // A primary muscle group id, or 0 for all - the web's filter.
    property int muscleGroup: 0

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
            var e = exercises[i]
            if (muscleGroup && e.primary.indexOf(muscleGroup) < 0)
                continue
            if (!term || e.name.toLowerCase().indexOf(term) >= 0
                    || e.storedName.toLowerCase().indexOf(term) >= 0)
                filteredModel.append({ id: e.id, name: e.name, custom: e.custom,
                                       muscles: e.muscles })
        }
    }

    onSearchTextChanged: applyFilter()
    onMuscleGroupChanged: applyFilter()

    function load() {
        loading = true
        errorText = ""
        Store.ensureLookups(api, function() {
            var all = []
            Store.fetchAll(api, "exercises/?page_size=100", function(results) {
                all = all.concat(results.map(function(e) {
                    return { id: e.id, name: Store.contentName(e.name), storedName: e.name,
                             custom: e.is_custom, primary: e.primary_muscle_groups || [],
                             muscles: (e.primary_muscle_groups || []).map(Store.muscleGroupName).join(", ") }
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
        })
    }

    Component.onCompleted: load()

    // Back from creating or editing one.
    onStatusChanged: {
        if (status === PageStatus.Active && Store.exercisesChanged) {
            Store.exercisesChanged = false
            load()
        }
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: filteredModel
        currentIndex: -1

        PullDownMenu {
            busy: page.loading
            MenuItem {
                text: qsTr("New exercise")
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("ExerciseEditDialog.qml"))
                    dialog.accepted.connect(function() {
                        api.request("POST", "exercises/", dialog.body(), function(ok, status, data, error) {
                            if (!ok) {
                                page.errorText = error
                                return
                            }
                            page.load()
                        })
                    })
                }
            }
        }

        header: Column {
            width: parent.width
            PageHeader {
                title: page.picking ? qsTr("Add exercise") : qsTr("Exercises")
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }
            ComboBox {
                label: qsTr("Muscle group")
                menu: ContextMenu {
                    MenuItem {
                        text: qsTr("All muscle groups")
                        onClicked: page.muscleGroup = 0
                    }
                    Repeater {
                        model: Store.lookupList("muscleGroups", page.loading)
                        MenuItem {
                            text: modelData.name
                            onClicked: page.muscleGroup = modelData.id
                        }
                    }
                }
            }
            SearchField {
                width: parent.width
                placeholderText: qsTr("Search")
                onTextChanged: page.searchText = text
            }
        }

        delegate: ListItem {
            contentHeight: Math.max(Theme.itemSizeSmall, textColumn.height + 2 * Theme.paddingSmall)
            onClicked: {
                if (page.picking) {
                    page.selected(model.id)
                    pageStack.pop()
                } else {
                    pageStack.push(Qt.resolvedUrl("ExercisePage.qml"), { exerciseId: model.id })
                }
            }
            Column {
                id: textColumn
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    text: Theme.highlightText(model.name, page.searchText, Theme.highlightColor)
                    textFormat: Text.StyledText
                }
                Label {
                    visible: text !== ""
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    text: [model.muscles, model.custom ? qsTr("Custom") : ""]
                          .filter(function(part) { return part }).join(" · ")
                }
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
