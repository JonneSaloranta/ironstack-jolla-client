import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store
import "../js/progress.js" as Progress

Page {
    id: page
    objectName: "dashboard"

    property var summary: null
    property var recentRecords: []
    property bool recordsLoaded: false
    // up-next/: {program, workout, day}, all null before any workout from
    // a program has been completed.
    property var upNext: null
    property var achievements: []
    // The built-in body weight type and its latest reading, like the web's
    // dashboard; both null without one (or without the measurements
    // permission, which isn't an error here).
    property var bodyWeightType: null
    property var bodyWeight: null
    // When the newest body measurement of any type was taken, for the
    // web's "Time to log your body measurements?" reminder.
    property string latestMeasurementAt: ""
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
        var pending = 6
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

        loadSummary(settle)

        api.request("GET", "sessions/?status=in_progress", null, function(ok, status, data, error) {
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

        loadBodyWeight()

        api.request("GET", "up-next/", null, function(ok, status, data, error) {
            if (ok)
                page.upNext = data && data.workout ? data : null
            else
                page.failed(status, error)
            settle()
        })

        api.request("GET", "analytics/achievements/", null, function(ok, status, data, error) {
            if (ok) {
                achievementTimer.index = 0
                page.achievements = data || []
            }
            else
                page.failed(status, error)
            settle()
        })

        api.request("GET", "records/", null, function(ok, status, data, error) {
            if (ok) {
                page.recentRecords = (data.results || []).slice(0, 5)
                page.recordsLoaded = true
            } else {
                page.failed(status, error)
            }
            settle()
        })
    }

    // analytics/summary/ offers 7d, 30d and all; tapping the heading
    // moves to the next.
    property string summaryRange: "7d"
    readonly property var summaryRanges: ["7d", "30d", "all"]

    function loadSummary(done) {
        api.request("GET", "analytics/summary/?range=" + summaryRange, null, function(ok, status, data, error) {
            if (ok)
                page.summary = data
            else
                page.failed(status, error)
            if (done)
                done()
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
                settings.activeSessionName = ok ? Store.contentName(data.name) : qsTr("Workout")
            })
        } else {
            settings.activeSessionName = qsTr("Freeform workout")
        }
    }

    function openSession(id) {
        pageStack.push(Qt.resolvedUrl("TrainingPage.qml"), { sessionId: id })
    }

    function loadBodyWeight() {
        api.request("GET", "measurement-types/?page_size=100", null, function(ok, status, data) {
            if (!ok)
                return
            var type = (data.results || []).filter(Store.isBodyWeightType)[0] || null
            page.bodyWeightType = type
            // Newest first: the latest reading of any type, and of body weight.
            api.request("GET", "measurements/?page_size=1", null, function(ok2, status2, readings) {
                if (ok2)
                    page.latestMeasurementAt = (readings.results || []).length ? readings.results[0].recorded_at : ""
            })
            if (type) {
                api.request("GET", "measurements/?page_size=1&measurement_type=" + type.id, null,
                            function(ok3, status3, weights) {
                    if (ok3)
                        page.bodyWeight = (weights.results || [])[0] || null
                })
            }
        })
    }

    function logBodyWeight() {
        var dialog = pageStack.push(Qt.resolvedUrl("MeasurementDialog.qml"), { type: bodyWeightType })
        dialog.accepted.connect(function() {
            api.request("POST", "measurements/", dialog.body(), function(ok, status, data, error) {
                if (!ok)
                    page.errorText = error
                loadBodyWeight()
            })
        })
    }

    // "Today" or the weekday, like the web's up-next card.
    function dayText(iso) {
        if (!iso)
            return ""
        if (Store.isToday(iso, new Date()))
            return qsTr("Today")
        return Qt.locale().dayName(Store.parseDate(iso).getDay(), Locale.LongFormat)
    }

    function startWorkout(workoutId) {
        api.request("POST", "sessions/", { workout: workoutId }, function(ok, status, data, error) {
            if (!ok) {
                page.errorText = error
                return
            }
            openSession(data.id)
        })
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
                text: qsTr("All sections")
                onClicked: pageStack.push(Qt.resolvedUrl("MenuPage.qml"))
            }
            MenuItem {
                text: qsTr("Settings")
                onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"))
            }
            MenuItem {
                text: qsTr("Progress")
                onClicked: pageStack.push(Qt.resolvedUrl("ProgressPage.qml"))
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
                showRetry: true
                onRetry: page.refresh()
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
                height: Math.max(Theme.itemSizeLarge, continueColumn.height + 2 * Theme.paddingMedium)
                onClicked: page.openSession(settings.activeSessionId)

                Column {
                    id: continueColumn
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

            SectionHeader {
                visible: upNextItem.visible
                text: qsTr("Up next")
            }

            // The next workout in the program last trained from - a
            // shortcut, nothing more; tapping shows what's in it.
            BackgroundItem {
                id: upNextItem
                visible: !page.hasActiveSession && page.upNext !== null
                width: parent.width
                height: Math.max(Theme.itemSizeMedium, upNextColumn.height + 2 * Theme.paddingMedium)
                onClicked: pageStack.push(Qt.resolvedUrl("WorkoutPage.qml"), { workout: page.upNext.workout })

                Column {
                    id: upNextColumn
                    anchors.verticalCenter: parent.verticalCenter
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    Label {
                        width: parent.width
                        wrapMode: Text.Wrap
                        color: upNextItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                        text: page.upNext ? Store.contentName(page.upNext.workout.name) : ""
                    }
                    Label {
                        width: parent.width
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryColor
                        text: page.upNext
                              ? [Store.contentName(page.upNext.program.name), page.dayText(page.upNext.day)]
                                .filter(function(part) { return part }).join(" · ")
                              : ""
                    }
                }
            }

            ButtonLayout {
                visible: !page.hasActiveSession && !page.loading
                Button {
                    text: qsTr("Start workout")
                    onClicked: {
                        if (page.upNext)
                            page.startWorkout(page.upNext.workout.id)
                        else
                            pageStack.push(Qt.resolvedUrl("ProgramsPage.qml"))
                    }
                }
                Button {
                    text: qsTr("Freeform workout")
                    onClicked: page.startFreeform()
                }
                Button {
                    visible: page.upNext !== null
                    text: qsTr("Choose another workout")
                    onClicked: pageStack.push(Qt.resolvedUrl("ProgramsPage.qml"))
                }
            }

            BackgroundItem {
                width: parent.width
                height: summaryHeader.height
                onClicked: {
                    var ranges = page.summaryRanges
                    page.summaryRange = ranges[(ranges.indexOf(page.summaryRange) + 1) % ranges.length]
                    page.loadSummary()
                }
                SectionHeader {
                    id: summaryHeader
                    text: page.summaryRange === "7d" ? qsTr("Last 7 days")
                          : page.summaryRange === "30d" ? qsTr("Last 30 days") : qsTr("All time")
                }
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

            // Body weight, like the web's dashboard stat and its "Log body
            // weight" link.
            // With large text the link goes under the weight rather than
            // fading the weight out.
            BackgroundItem {
                id: bodyWeightItem
                visible: page.bodyWeightType !== null
                width: parent.width
                readonly property real room: width - 2 * Theme.horizontalPageMargin
                readonly property bool sideBySide: weightLabel.implicitWidth + Theme.paddingLarge + logLabel.implicitWidth <= room
                height: sideBySide ? Theme.itemSizeSmall : weightLabel.height + logLabel.height + 2 * Theme.paddingSmall
                onClicked: page.logBodyWeight()
                Label {
                    id: weightLabel
                    x: Theme.horizontalPageMargin
                    y: bodyWeightItem.sideBySide ? (parent.height - height) / 2 : Theme.paddingSmall
                    width: bodyWeightItem.sideBySide ? implicitWidth : bodyWeightItem.room
                    wrapMode: Text.Wrap
                    text: qsTr("Body weight") + (page.bodyWeight
                          ? ": " + Store.formatMeasurement(page.bodyWeight.value, "weight", settings.unitSystem) : "")
                }
                Label {
                    id: logLabel
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.horizontalPageMargin
                    y: bodyWeightItem.sideBySide ? (parent.height - height) / 2 : weightLabel.y + weightLabel.height
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeSmall
                    text: qsTr("Log body weight")
                }
            }

            // Like the web's card: only a nudge, never in the way.
            BackgroundItem {
                visible: settings.bodyTrackingReminder
                         && Progress.needsBodyReminder(page.latestMeasurementAt, new Date())
                width: parent.width
                height: reminderColumn.height + 2 * Theme.paddingMedium
                onClicked: pageStack.push(Qt.resolvedUrl("MeasurementsPage.qml"))
                Column {
                    id: reminderColumn
                    anchors.verticalCenter: parent.verticalCenter
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    Label {
                        width: parent.width
                        wrapMode: Text.Wrap
                        color: Theme.highlightColor
                        text: qsTr("Time to log your body measurements?")
                    }
                    Label {
                        width: parent.width
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryHighlightColor
                        text: qsTr("It's been a while since you tracked your weight or measurements - tap here to add a new reading.")
                    }
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

            // Shared across everyone on the server; people who opted out
            // are already left out. One at a time, moving on every 4.5 s
            // like the web's carousel, or on a tap.
            SectionHeader {
                visible: page.achievements.length > 0
                text: page.achievements.length > 1
                      ? qsTr("Achievements") + " " + (achievementTimer.index + 1) + "/" + page.achievements.length
                      : qsTr("Achievements")
            }

            BackgroundItem {
                visible: page.achievements.length > 0
                width: parent.width
                height: achievementItem.height
                onClicked: achievementTimer.next()

                AchievementItem {
                    id: achievementItem
                    achievement: page.achievements[achievementTimer.index] || null
                }
            }

            Timer {
                id: achievementTimer
                property int index: 0
                function next() {
                    index = (index + 1) % Math.max(1, page.achievements.length)
                    restart()
                }
                interval: 4500
                repeat: true
                running: page.achievements.length > 1 && page.status === PageStatus.Active
                         && Qt.application.active
                onTriggered: next()
            }
        }

        VerticalScrollDecorator {}
    }
}
