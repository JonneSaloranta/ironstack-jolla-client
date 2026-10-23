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
                    status: s.status,
                    startedAt: s.started_at,
                    endedAt: s.ended_at || "",
                    exercises: s.performed_exercises.map(function(pe) { return pe.exercise_name }).join(", "),
                    setCount: setCount,
                    volume: volume
                })
            }
        })
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
            contentHeight: Theme.itemSizeLarge
            onClicked: pageStack.push(Qt.resolvedUrl("SessionPage.qml"), { sessionId: model.sessionId })

            Column {
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                Row {
                    width: parent.width
                    Label {
                        width: parent.width - statusLabel.width
                        truncationMode: TruncationMode.Fade
                        text: (Format.formatDate(new Date(model.startedAt), Formatter.DateMedium) + " " + Format.formatDate(new Date(model.startedAt), Formatter.TimeValue))
                    }
                    Label {
                        id: statusLabel
                        color: Theme.highlightColor
                        font.pixelSize: Theme.fontSizeSmall
                        text: page.statusText(model.status)
                    }
                }
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    text: model.exercises || qsTr("No exercises")
                }
                Label {
                    width: parent.width
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    text: qsTr("%n set(s)", "", model.setCount)
                          + " - " + Math.round(Store.kgToDisplay(model.volume, settings.unitSystem))
                          + " " + Store.weightUnit(settings.unitSystem)
                          + (model.endedAt ? " - " + Store.formatDuration(
                                 (new Date(model.endedAt) - new Date(model.startedAt)) / 1000) : "")
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
