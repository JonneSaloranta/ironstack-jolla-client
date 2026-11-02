import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

// An exercise's strength trend, like the web's exercise analytics page:
// estimated 1RM over time, sessions and volume for a date range. Worked out
// here from completed sessions - the API has no analytics endpoint for it
// (IronStack #35).
Page {
    id: page

    property var exercise
    property string range: "30d"
    property var trend: null
    property bool loading: false
    property string errorText: ""

    readonly property var ranges: ["7d", "30d", "3m", "6m", "1y", "all"]

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

    function load() {
        loading = true
        errorText = ""
        var start = Store.rangeStart(range, new Date())
        var path = "sessions/?status=completed&page_size=100"
                + (start ? "&started_after=" + Store.isoDate(start) : "")
        var sessions = []
        Store.fetchAll(api, path, function(results) {
            sessions = sessions.concat(results)
        }, function(ok, error) {
            loading = false
            if (!ok) {
                errorText = error
                return
            }
            trend = Store.exerciseTrend(sessions, exercise.id)
        })
    }

    onRangeChanged: load()
    Component.onCompleted: load()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: qsTr("Strength trend")
                description: Store.contentName(page.exercise.name)
            }

            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
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
                    width: parent.width / 2
                    value: page.trend ? page.trend.sessionCount : "-"
                    label: qsTr("workouts")
                }
                StatItem {
                    width: parent.width / 2
                    value: page.trend ? Math.round(Store.kgToDisplay(page.trend.volume, settings.unitSystem)) : "-"
                    label: qsTr("volume (%1)").arg(Store.weightUnit(settings.unitSystem))
                }
            }

            SectionHeader {
                //: Estimated one-rep max
                text: qsTr("Estimated 1RM")
            }

            LineChart {
                visible: page.trend !== null && page.trend.points.length > 0
                unit: Store.weightUnit(settings.unitSystem)
                points: page.trend ? page.trend.points.map(function(p) {
                    return { x: p.x, y: Store.kgToDisplay(p.y, settings.unitSystem) }
                }) : []
            }

            Label {
                visible: page.trend !== null && page.trend.points.length === 0 && !page.loading
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                text: qsTr("No completed sets of this exercise in this period.")
            }
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: page.loading
    }
}
