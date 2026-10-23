import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

Page {
    id: page
    objectName: "dashboard"

    property var summary: null
    property var activeSession: null
    property var recentRecords: []
    property string errorText: ""
    property bool loading: false

    function refresh() {
        errorText = ""
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
                page.errorText = error
            settle()
        })

        api.request("GET", "analytics/summary/?range=7d", null, function(ok, status, data, error) {
            if (ok)
                page.summary = data
            else
                page.errorText = error
            settle()
        })

        // Newest first; an in-progress session is always among the most
        // recent ones (see IronStack issue #17 for a status filter).
        api.request("GET", "sessions/", null, function(ok, status, data, error) {
            page.activeSession = null
            if (ok) {
                var results = data.results || []
                for (var i = 0; i < results.length; i++) {
                    if (results[i].is_in_progress) {
                        page.activeSession = results[i]
                        break
                    }
                }
                updateActiveSession()
            } else {
                page.errorText = error
            }
            settle()
        })

        api.request("GET", "records/", null, function(ok, status, data, error) {
            if (ok) {
                var results = (data.results || []).slice(0, 5)
                Store.ensureExercises(api, results.map(function(r) { return r.exercise }), function() {
                    page.recentRecords = results
                    settle()
                })
            } else {
                page.errorText = error
                settle()
            }
        })
    }

    function updateActiveSession() {
        var session = page.activeSession
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
        pageStack.push(Qt.resolvedUrl("SessionPage.qml"), { sessionId: id })
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

            BackgroundItem {
                visible: page.activeSession !== null
                width: parent.width
                height: Theme.itemSizeLarge
                onClicked: page.openSession(page.activeSession.id)

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
                        text: settings.activeSessionName + " - "
                              + qsTr("started %1").arg(Store.formatDateTime(settings.activeSessionStarted))
                    }
                }
            }

            ButtonLayout {
                visible: page.activeSession === null && !page.loading
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
                visible: page.recentRecords.length === 0 && !page.loading
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
