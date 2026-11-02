import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

Page {
    id: page

    property string nextUrl: "sessions/"
    property bool loading: false
    property string errorText: ""

    ListModel {
        id: sessionsModel
    }

    function reload() {
        sessionsModel.clear()
        nextUrl = "sessions/"
        loadMore()
    }

    function loadMore() {
        if (loading || !nextUrl)
            return
        loading = true
        api.request("GET", nextUrl, null, function(ok, status, data, error) {
            loading = false
            if (!ok) {
                page.errorText = error
                return
            }
            page.errorText = ""
            page.nextUrl = data.next || ""
            var results = data.results || []
            Store.ensureWorkouts(api, results.map(function(s) { return s.workout }), function() {
                page.append(results)
            })
        })
    }

    function append(results) {
        for (var i = 0; i < results.length; i++) {
            var s = results[i]
            var setCount = 0
            var volume = 0
            s.performed_exercises.forEach(function(pe) {
                pe.sets.forEach(function(set) {
                    if (set.is_warmup)
                        return
                    setCount++
                    volume += parseFloat(set.weight) * set.reps
                })
            })
            sessionsModel.append({
                sessionId: s.id,
                title: s.workout ? (Store.contentName(Store.workoutNames[s.workout]) || qsTr("Workout"))
                                  : qsTr("Freeform workout"),
                status: s.status,
                startedAt: s.started_at,
                endedAt: s.ended_at || "",
                exercises: s.performed_exercises.map(function(pe) { return Store.contentName(pe.exercise_name) }).join(", "),
                setCount: setCount,
                volume: volume
            })
        }
    }

    function statusText(status) {
        if (status === "in_progress")
            return qsTr("In progress")
        if (status === "abandoned")
            return qsTr("Abandoned")
        return ""
    }

    Component.onCompleted: reload()

    SilicaListView {
        id: list
        anchors.fill: parent
        model: sessionsModel

        header: Column {
            width: parent.width
            PageHeader {
                title: qsTr("History")
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.reload()
            }
        }

        PullDownMenu {
            busy: page.loading
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.reload()
            }
        }

        onAtYEndChanged: if (atYEnd && count > 0) page.loadMore()

        delegate: ListItem {
            id: item
            contentHeight: rowColumn.height + 2 * Theme.paddingMedium
            onClicked: pageStack.push(Qt.resolvedUrl("SessionPage.qml"), { sessionId: model.sessionId })

            // Deleting a workout also corrects the records it made, like
            // the web's delete (IronStack rebuilds them). One in progress
            // is ended from the workout itself instead.
            function remove() {
                var id = model.sessionId
                var row = index
                remorseDelete(function() {
                    api.request("DELETE", "sessions/" + id + "/", null, function(ok, status, data, error) {
                        if (!ok) {
                            page.errorText = error
                            return
                        }
                        if (sessionsModel.get(row) && sessionsModel.get(row).sessionId === id)
                            sessionsModel.remove(row)
                        else
                            page.reload()
                    })
                })
            }

            menu: model.status === "in_progress" ? null : deleteMenu
            Component {
                id: deleteMenu
                ContextMenu {
                    MenuItem {
                        text: qsTr("Delete")
                        onClicked: item.remove()
                    }
                }
            }

            Column {
                id: rowColumn
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                Row {
                    width: parent.width
                    spacing: Theme.paddingMedium
                    Label {
                        width: parent.width - statusLabel.width - parent.spacing
                        truncationMode: TruncationMode.Fade
                        text: model.title
                    }
                    Label {
                        id: statusLabel
                        anchors.baseline: parent.children[0].baseline
                        color: Theme.highlightColor
                        font.pixelSize: Theme.fontSizeSmall
                        text: page.statusText(model.status)
                    }
                }
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryHighlightColor
                    text: {
                        var parts = [Format.formatDate(new Date(model.startedAt), Formatter.DateMedium)
                                     + " " + Format.formatDate(new Date(model.startedAt), Formatter.TimeValue)]
                        if (model.endedAt)
                            parts.push(Store.formatDuration((new Date(model.endedAt) - new Date(model.startedAt)) / 1000))
                        parts.push(qsTr("%n set(s)", "", model.setCount))
                        if (model.volume > 0)
                            parts.push(Math.round(Store.kgToDisplay(model.volume, settings.unitSystem))
                                       + " " + Store.weightUnit(settings.unitSystem))
                        return parts.join(" - ")
                    }
                }
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    text: model.exercises || qsTr("No exercises")
                }
            }
        }

        ViewPlaceholder {
            enabled: !page.loading && sessionsModel.count === 0 && page.errorText === ""
            text: qsTr("No workouts yet")
        }

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: page.loading && sessionsModel.count === 0
        }

        VerticalScrollDecorator {}
    }
}
