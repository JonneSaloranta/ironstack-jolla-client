import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store
import "../js/texts.js" as Texts

// Stretching, like the web's home: streak and totals, routines to start,
// minutes per week and recent sessions. From the pull-down: log a session
// after the fact, the stretch library, history and a new routine.
Page {
    id: page

    property var routines: []
    property var sessions: []
    property bool loading: false
    property string errorText: ""

    readonly property var summary: Store.stretchSummary(sessions, new Date())

    function sessionName(session) {
        return session.name ? Store.contentName(session.name) : qsTr("Stretching")
    }

    function load() {
        loading = true
        errorText = ""
        var foundRoutines = []
        var foundSessions = []
        var pending = 3
        function settle(ok, error) {
            if (ok === false)
                errorText = error
            pending--
            if (pending > 0)
                return
            loading = false
            routines = foundRoutines
            sessions = foundSessions
        }
        Store.ensureStretches(api, settle)
        Store.fetchAll(api, "stretch-routines/?page_size=100", function(results) {
            foundRoutines = foundRoutines.concat(results)
        }, settle)
        Store.fetchAll(api, "stretch-sessions/?page_size=100", function(results) {
            foundSessions = foundSessions.concat(results)
        }, settle)
    }

    function quickLog() {
        var dialog = pageStack.push(Qt.resolvedUrl("StretchSessionDialog.qml"), { routines: routines })
        dialog.accepted.connect(function() {
            api.request("POST", "stretch-sessions/", dialog.body(), function(ok, status, data, error) {
                if (!ok)
                    errorText = error
                load()
            })
        })
    }

    Component.onCompleted: load()
    onStatusChanged: {
        if (status === PageStatus.Active && Store.stretchingChanged) {
            Store.stretchingChanged = false
            load()
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            busy: page.loading
            MenuItem {
                text: qsTr("New routine")
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("RoutineEditDialog.qml"))
                    dialog.accepted.connect(function() {
                        api.request("POST", "stretch-routines/", dialog.body(), function(ok, status, data, error) {
                            if (!ok) {
                                page.errorText = error
                                return
                            }
                            page.load()
                            Store.whenIdle(pageStack, function() { pageStack.push(Qt.resolvedUrl("StretchRoutinePage.qml"), { routine: data }) })
                        })
                    })
                }
            }
            MenuItem {
                text: qsTr("History")
                onClicked: pageStack.push(Qt.resolvedUrl("StretchSessionsPage.qml"))
            }
            MenuItem {
                text: qsTr("Stretches")
                onClicked: pageStack.push(Qt.resolvedUrl("StretchesPage.qml"))
            }
            MenuItem {
                text: qsTr("Log stretching")
                onClicked: page.quickLog()
            }
        }

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingSmall

            PageHeader {
                title: qsTr("Stretching")
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }

            Row {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                StatItem {
                    width: parent.width / 3
                    value: qsTr("%n day(s)", "", page.summary.streak)
                    label: qsTr("Streak")
                }
                StatItem {
                    width: parent.width / 3
                    value: page.summary.weekCount + " · " + (Store.formatMinutes(page.summary.weekSeconds) || "0min")
                    label: qsTr("Last 7 days")
                }
                StatItem {
                    width: parent.width / 3
                    value: page.summary.count + " · " + (Store.formatMinutes(page.summary.seconds) || "0min")
                    label: qsTr("All time")
                }
            }

            SectionHeader {
                text: qsTr("Start a routine")
            }
            Repeater {
                model: page.routines
                delegate: BackgroundItem {
                    width: page.width
                    height: Math.max(Theme.itemSizeMedium, routineColumn.height + 2 * Theme.paddingSmall)
                    onClicked: pageStack.push(Qt.resolvedUrl("StretchRoutinePage.qml"), { routine: modelData })
                    Column {
                        id: routineColumn
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        Label {
                            width: parent.width
                            truncationMode: TruncationMode.Fade
                            text: Store.contentName(modelData.name) + (modelData.is_custom ? " · " + qsTr("Custom") : "")
                        }
                        Label {
                            width: parent.width
                            truncationMode: TruncationMode.Fade
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: Theme.secondaryColor
                            text: qsTr("%n stretch(es)", "", modelData.items.length)
                                  + (modelData.description ? " - " + Texts.contentText(modelData.description) : "")
                        }
                    }
                }
            }
            Label {
                visible: !page.loading && page.routines.length === 0
                x: Theme.horizontalPageMargin
                color: Theme.secondaryColor
                text: qsTr("No routines yet.")
            }

            SectionHeader {
                text: qsTr("Minutes per week")
            }
            LineChart {
                visible: page.summary.count > 0
                unit: qsTr("min")
                points: Store.weeklyStretchMinutes(page.sessions, new Date(), 8).map(function(row) {
                    return { x: row.monday.getTime(), y: row.minutes }
                })
            }
            Label {
                visible: page.summary.count === 0 && !page.loading
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                text: qsTr("Finish or log a stretching session to see your weekly minutes here.")
            }

            SectionHeader {
                visible: page.sessions.length > 0
                text: qsTr("Recent sessions")
            }
            Repeater {
                model: page.sessions.slice(0, 5)
                delegate: DetailItem {
                    label: Format.formatDate(Store.parseDate(modelData.date), Formatter.DateMedium)
                    value: page.sessionName(modelData) + " · " + Store.formatMinutes(Store.parseDuration(modelData.duration))
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
