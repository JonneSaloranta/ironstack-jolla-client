import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store
import "../js/progress.js" as Progress

// The web's Progress page for a date range: workouts, training time and
// volume; how each body measurement changed; strength trend per exercise;
// weekly and muscle-group volume; personal records grouped by exercise.
// The API has no analytics over time (IronStack #35), so it's worked out
// here from completed sessions, records and measurements.
Page {
    id: page

    property string range: "30d"
    readonly property var ranges: ["7d", "30d", "3m", "6m", "1y", "all"]

    property var sessions: []
    property var records: []
    property var readings: null
    property var types: []
    property var primaryGroups: ({})
    property string bodyError: ""
    property int pending: 0
    property string errorText: ""
    // Exercise ids whose rep records are shown.
    property var expanded: ({})

    readonly property bool loading: pending > 0
    readonly property var start: Store.rangeStart(range, new Date())
    readonly property var today: new Date()

    readonly property var summary: Progress.trainingSummary(sessions, start, today)
    readonly property var weekly: Progress.weeklyVolume(sessions, start, today)
    readonly property var muscles: Progress.muscleGroupVolume(sessions, start, today, primaryGroups)
    readonly property var recordGroups: Progress.recordGroups(records, start, today)
    readonly property var body: readings ? Progress.bodyProgress(readings, types, start, today, settings.unitSystem) : []
    readonly property var trained: {
        var seen = {}
        var list = []
        sessions.forEach(function(s) {
            (s.performed_exercises || []).forEach(function(pe) {
                if (s.status === "completed" && !seen[pe.exercise]) {
                    seen[pe.exercise] = true
                    list.push({ id: pe.exercise, name: pe.exercise_name })
                }
            })
        })
        return list.sort(function(a, b) { return Store.contentName(a.name).localeCompare(Store.contentName(b.name)) })
    }

    function rangeText(key) {
        switch (key) {
        case "7d": return qsTr("7 days")
        case "30d": return qsTr("30 days")
        case "3m": return qsTr("3 months")
        case "6m": return qsTr("6 months")
        case "1y": return qsTr("1 year")
        }
        return qsTr("All time")
    }

    function weight(kg) {
        return Math.round(Store.kgToDisplay(kg, settings.unitSystem))
    }

    function settle(ok, error) {
        if (!ok && error)
            errorText = error
        pending--
    }

    // Sessions and records depend on the range; measurements and the
    // exercises' muscle groups are read once.
    // `start` isn't read here: onRangeChanged can run before the binding
    // has followed the new range. A reply for an earlier range that comes
    // in late is dropped.
    property int rangeLoads: 0

    function loadRange() {
        errorText = ""
        pending += 2
        var load = ++rangeLoads
        var start = Store.rangeStart(range, new Date())
        var path = "sessions/?status=completed&page_size=100"
                + (start ? "&started_after=" + Store.isoDate(start) : "")
        var found = []
        Store.fetchAll(api, path, function(results) {
            found = found.concat(results)
        }, function(ok, error) {
            if (ok && load === rangeLoads)
                sessions = found
            settle(ok, error)
        })

        // Newest first and no date filter: read until past the start.
        var foundRecords = []
        var startDay = start ? Store.isoDate(start) : ""
        function recordPage(url) {
            api.request("GET", url, null, function(ok, status, data, error) {
                if (!ok)
                    return settle(false, error)
                var results = data.results || []
                foundRecords = foundRecords.concat(results)
                var last = results[results.length - 1]
                if (data.next && last && (!startDay || Store.isoDate(new Date(last.achieved_at)) >= startDay))
                    recordPage(data.next)
                else {
                    if (load === rangeLoads)
                        records = foundRecords
                    settle(true, "")
                }
            })
        }
        recordPage("records/?page_size=100")
    }

    function loadOnce() {
        pending += 3
        Store.ensureLookups(api, function() {
            var groups = {}
            Store.fetchAll(api, "exercises/?page_size=100", function(results) {
                results.forEach(function(e) { groups[e.id] = e.primary_muscle_groups || [] })
            }, function(ok, error) {
                if (ok)
                    primaryGroups = groups
                settle(ok, error)
            })
        })
        // Body measurements need their own permission; without it only
        // that section says so.
        var foundTypes = []
        Store.fetchAll(api, "measurement-types/?page_size=100", function(results) {
            foundTypes = foundTypes.concat(results)
        }, function(ok, error) {
            if (ok)
                types = foundTypes
            else
                bodyError = error
            pending--
        })
        var foundReadings = []
        Store.fetchAll(api, "measurements/?page_size=100", function(results) {
            foundReadings = foundReadings.concat(results)
        }, function(ok, error) {
            if (ok)
                readings = foundReadings
            else
                bodyError = error
            pending--
        })
    }

    function reload() {
        loadRange()
        loadOnce()
    }

    onRangeChanged: loadRange()
    Component.onCompleted: reload()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            busy: page.loading
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.reload()
            }
        }

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingSmall

            PageHeader {
                title: qsTr("Progress")
            }

            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.reload()
            }

            ComboBox {
                label: qsTr("Period")
                currentIndex: page.ranges.indexOf(page.range)
                menu: ContextMenu {
                    Repeater {
                        model: page.ranges
                        MenuItem {
                            text: page.rangeText(modelData)
                            onClicked: page.range = modelData
                        }
                    }
                }
            }

            Row {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                StatItem {
                    width: parent.width / 3
                    value: page.summary.sessionCount
                    label: qsTr("workouts")
                }
                StatItem {
                    width: parent.width / 3
                    value: Store.formatHoursMinutes(page.summary.duration)
                    label: qsTr("time (h:min)")
                }
                StatItem {
                    width: parent.width / 3
                    value: page.weight(page.summary.volume)
                    label: qsTr("volume (%1)").arg(Store.weightUnit(settings.unitSystem))
                }
            }

            SectionHeader {
                text: qsTr("Body measurements")
            }

            Label {
                visible: text !== ""
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
                text: page.bodyError
                      ? page.bodyError
                      : page.readings !== null && page.body.length === 0
                        ? qsTr("No body measurements in this range.") : ""
            }

            Repeater {
                model: page.body
                delegate: ListItem {
                    contentHeight: Math.max(Theme.itemSizeSmall, bodyColumn.height + 2 * Theme.paddingSmall)
                    onClicked: pageStack.push(Qt.resolvedUrl("MeasurementHistoryPage.qml"), { type: modelData.type })
                    Column {
                        id: bodyColumn
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        Row {
                            width: parent.width
                            Label {
                                width: parent.width - bodyValue.width
                                truncationMode: TruncationMode.Fade
                                text: Store.contentName(modelData.type.name)
                            }
                            Label {
                                id: bodyValue
                                color: Theme.highlightColor
                                text: Store.formatNumber(modelData.value) + " " + modelData.unit
                            }
                        }
                        Label {
                            width: parent.width
                            wrapMode: Text.Wrap
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: Theme.secondaryColor
                            text: modelData.change === null
                                  ? qsTr("One reading in this range")
                                  : Progress.signed(modelData.change) + " " + modelData.unit
                                    + (modelData.changePercent !== null
                                       ? " (" + Progress.signed(modelData.changePercent) + " %)" : "")
                        }
                    }
                }
            }

            SectionHeader {
                visible: page.trained.length > 0
                text: qsTr("Strength trend")
            }

            ComboBox {
                visible: page.trained.length > 0
                label: qsTr("Exercise")
                value: qsTr("Choose an exercise")
                menu: ContextMenu {
                    Repeater {
                        model: page.trained
                        MenuItem {
                            text: Store.contentName(modelData.name)
                            onClicked: pageStack.push(Qt.resolvedUrl("ExerciseProgressPage.qml"),
                                                      { exercise: modelData, range: page.range })
                        }
                    }
                }
            }

            SectionHeader {
                text: qsTr("Weekly training volume")
            }

            BarChart {
                visible: page.weekly.length > 0
                unit: Store.weightUnit(settings.unitSystem)
                bars: page.weekly.map(function(w) {
                    return { value: page.weight(w.value),
                             label: Format.formatDate(new Date(w.x), Formatter.DateMedium) }
                })
            }

            Label {
                visible: page.weekly.length === 0 && !page.loading
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                text: qsTr("No completed workouts in this range.")
            }

            SectionHeader {
                visible: page.muscles.length > 0
                text: qsTr("Muscle-group volume")
            }

            Repeater {
                model: page.muscles
                delegate: Item {
                    width: column.width
                    height: muscleName.height + muscleBar.height + Theme.paddingSmall
                    Label {
                        id: muscleName
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin - muscleValue.width
                        truncationMode: TruncationMode.Fade
                        font.pixelSize: Theme.fontSizeSmall
                        text: Store.muscleGroupName(modelData.id) || "#" + modelData.id
                    }
                    Label {
                        id: muscleValue
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.horizontalPageMargin
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.highlightColor
                        text: page.weight(modelData.value) + " " + Store.weightUnit(settings.unitSystem)
                    }
                    Rectangle {
                        id: muscleBar
                        anchors.top: muscleName.bottom
                        x: Theme.horizontalPageMargin
                        height: Theme.paddingSmall
                        radius: height / 2
                        color: Theme.highlightColor
                        width: Math.max(height, (column.width - 2 * Theme.horizontalPageMargin)
                                                * modelData.value / page.muscles[0].value)
                    }
                }
            }

            SectionHeader {
                text: qsTr("Personal records")
            }

            Label {
                visible: page.recordGroups.length === 0 && !page.loading
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                text: qsTr("No records in this range.")
            }

            Repeater {
                model: page.recordGroups
                delegate: Column {
                    id: group
                    property var entry: modelData
                    readonly property bool open: page.expanded[entry.exercise] === true
                    width: column.width

                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        truncationMode: TruncationMode.Fade
                        color: Theme.highlightColor
                        text: Store.contentName(group.entry.name)
                    }
                    Repeater {
                        model: group.open ? group.entry.primary.concat(group.entry.secondary) : group.entry.primary
                        delegate: Item {
                            width: group.width
                            height: Math.max(recordLabel.height, recordValue.height) + Theme.paddingSmall
                            Label {
                                id: recordLabel
                                x: Theme.horizontalPageMargin
                                width: parent.width - 2 * Theme.horizontalPageMargin - recordValue.width - Theme.paddingMedium
                                wrapMode: Text.Wrap
                                font.pixelSize: Theme.fontSizeSmall
                                text: Store.recordLabel(modelData, qsTr("%1RM")) + " · "
                                      + Format.formatDate(new Date(modelData.achieved_at), Formatter.DateMedium)
                            }
                            Label {
                                id: recordValue
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.horizontalPageMargin
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.highlightColor
                                text: Store.recordValueText(modelData, settings.unitSystem, "%1 " + qsTr("reps"))
                            }
                        }
                    }
                    BackgroundItem {
                        visible: group.entry.secondary.length > 0
                        width: parent.width
                        height: Theme.itemSizeExtraSmall
                        onClicked: {
                            var e = Store.copy(page.expanded)
                            e[group.entry.exercise] = !group.open
                            page.expanded = e
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            x: Theme.horizontalPageMargin
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.secondaryHighlightColor
                            text: group.open ? qsTr("Show less")
                                             : qsTr("Show %n more", "", group.entry.secondary.length)
                        }
                    }
                    Item {
                        width: 1
                        height: Theme.paddingMedium
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: page.loading && page.sessions.length === 0
    }
}
