import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

Page {
    id: page
    objectName: "dashboard"

    property var summary: null
    property var recentRecords: []
    property bool recordsLoaded: false
    property string errorText: ""
    property bool offline: false
    property bool loading: false

    // The session in progress, as far as the app knows - remembered across
    // restarts, so it can be continued without a connection.
    readonly property bool hasActiveSession: settings.activeSessionId >= 0

    function failed(status, error) {
        // One calm line for "no connection" instead of an error per request.
        if (Store.isOffline(status))
            offline = true
        else
            errorText = error
    }

    function refresh() {
        errorText = ""
        offline = false
        loading = true
        var pending = 4
        function settle() {
            pending--
            if (pending === 0)
                loading = false
        }

        api.request("GET", "profile/", null, function(ok, status, data, error) {
            if (ok)
                settings.unitSystem = data.unit_system || "metric"
            else
                page.failed(status, error)
            settle()
        })

        api.request("GET", "analytics/summary/?range=7d", null, function(ok, status, data, error) {
            if (ok)
                page.summary = data
            else
                page.failed(status, error)
            settle()
        })

        // Newest first; an in-progress session is always among the most
        // recent ones (see IronStack issue #17 for a status filter).
        api.request("GET", "sessions/", null, function(ok, status, data, error) {
            if (ok) {
                var results = data.results || []
                var active = null
                for (var i = 0; i < results.length; i++) {
                    // Finishing it may be waiting in the sync queue.
                    if (results[i].is_in_progress && Store.pendingSessionEnd(syncQueue.items, results[i].id) === "") {
                        active = results[i]
                        break
                    }
                }
                updateActiveSession(active)
            } else {
                page.failed(status, error)
            }
            settle()
        })

        api.request("GET", "records/", null, function(ok, status, data, error) {
            if (ok) {
                var results = (data.results || []).slice(0, 5)
                Store.ensureExercises(api, results.map(function(r) { return r.exercise }), function() {
                    page.recentRecords = results
                    page.recordsLoaded = true
                    settle()
                })
            } else {
                page.failed(status, error)
                settle()
            }
        })
    }

    function updateActiveSession(session) {
        if (!session) {
            settings.clearActiveSession()
            return
        }
        settings.activeSessionId = session.id
        settings.activeSessionStarted = session.started_at
        if (session.workout) {
            api.request("GET", "workouts/" + session.workout + "/", null, function(ok, status, data) {
                settings.activeSessionName = ok ? data.name : qsTr("Workout")
            })
        } else {
            settings.activeSessionName = qsTr("Freeform workout")
        }
    }

    function openSession(id) {
        pageStack.push(Qt.resolvedUrl("TrainingPage.qml"), { sessionId: id })
    }

    function startFreeform() {
        api.request("POST", "sessions/", {}, function(ok, status, data, error) {
            if (!ok) {
                page.errorText = error
                return
            }
            openSession(data.id)
        })
    }

    onStatusChanged: {
        if (status === PageStatus.Active)
            refresh()
    }

    // Sets and finished workouts synced in the background change the stats.
    Connections {
        target: syncQueue
        onItemsChanged: {
            if (syncQueue.count === 0 && page.status === PageStatus.Active)
                page.refresh()
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            busy: page.loading
            MenuItem {
                text: qsTr("Settings")
                onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"))
            }
            MenuItem {
                text: qsTr("Personal records")
                onClicked: pageStack.push(Qt.resolvedUrl("RecordsPage.qml"))
            }
            MenuItem {
                text: qsTr("History")
                onClicked: pageStack.push(Qt.resolvedUrl("HistoryPage.qml"))
            }
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.refresh()
            }
        }

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: "IronStack"
                description: settings.baseUrl.replace(/^https?:\/\//, "")
            }

            ErrorBanner {
                text: page.errorText
            }

            Label {
                visible: page.offline && syncQueue.count === 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("No connection to the server. Workouts can still be logged and are sent later.")
            }

            SyncStatus {}

            BackgroundItem {
                visible: page.hasActiveSession
                width: parent.width
                height: Theme.itemSizeLarge
                onClicked: page.openSession(settings.activeSessionId)

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    Label {
                        text: qsTr("Continue workout")
                        color: Theme.highlightColor
                        font.pixelSize: Theme.fontSizeLarge
                    }
                    Label {
                        width: parent.width
                        truncationMode: TruncationMode.Fade
                        color: Theme.secondaryHighlightColor
                        font.pixelSize: Theme.fontSizeSmall
                        text: {
                            var started = settings.activeSessionStarted
                                    ? qsTr("started %1").arg(Format.formatDate(new Date(settings.activeSessionStarted),
                                                                               Formatter.TimeValue))
                                    : ""
                            return [settings.activeSessionName, started].filter(function(part) { return part }).join(" - ")
                        }
                    }
                }
            }

            ButtonLayout {
                visible: !page.hasActiveSession && !page.loading
                Button {
                    text: qsTr("Start workout")
                    onClicked: pageStack.push(Qt.resolvedUrl("ProgramsPage.qml"))
                }
                Button {
                    text: qsTr("Freeform workout")
                    onClicked: page.startFreeform()
                }
            }

            SectionHeader {
                text: qsTr("Last 7 days")
            }

            Row {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                StatItem {
                    width: parent.width / 3
                    value: page.summary ? page.summary.session_count : "-"
                    label: qsTr("workouts")
                }
                StatItem {
                    width: parent.width / 3
                    value: page.summary ? Store.formatHoursMinutes(page.summary.total_duration_seconds) : "-"
                    label: qsTr("time (h:min)")
                }
                StatItem {
                    width: parent.width / 3
                    value: page.summary ? Math.round(Store.kgToDisplay(page.summary.total_volume,
                                                                       settings.unitSystem)) : "-"
                    label: qsTr("volume (%1)").arg(Store.weightUnit(settings.unitSystem))
                }
            }

            SectionHeader {
                text: qsTr("Recent personal records")
            }

            Label {
                visible: page.recordsLoaded && page.recentRecords.length === 0 && !page.loading
                x: Theme.horizontalPageMargin
                color: Theme.secondaryColor
                text: qsTr("No records yet")
            }

            Repeater {
                model: page.recentRecords
                delegate: RecordItem {
                    record: modelData
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
