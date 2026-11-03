import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store
import "../js/nutrition.js" as Nutrition
import "../js/nutritionstats.js" as Stats

// The web's nutrition statistics: the last 30 days (days logged, mean and
// typical calories, median macros), the same for fixed periods, and daily
// calories with the target line. Worked out from the whole diary - the API
// has no date filter (IronStack #26), so this reads every entry - with
// entry nutrition from the foods as they are now (#27).
Page {
    id: page

    property var totals: ({})
    property string firstDay: ""
    property var target: null
    property bool loading: false
    property string errorText: ""

    readonly property var today: new Date()
    readonly property var summary: Stats.stats(totals, today, Stats.STATS_WINDOW_DAYS)
    readonly property var periods: Stats.periods(totals, today, firstDay || null)
    readonly property var history: Stats.calorieHistory(totals, today, Stats.STATS_WINDOW_DAYS)

    function periodText(key) {
        switch (key) {
        case "7d": return qsTr("7 days")
        case "14d": return qsTr("14 days")
        case "30d": return qsTr("30 days")
        case "3m": return qsTr("3 months")
        case "ytd": return qsTr("Year to date")
        case "1y": return qsTr("1 year")
        }
        return qsTr("All time")
    }

    function withTarget(value, field, unit) {
        return value + (page.target ? " / " + Math.round(parseFloat(page.target[field])) : "") + " " + unit
    }

    function load() {
        loading = true
        errorText = ""
        api.request("GET", "nutrition-targets/?page_size=100", null, function(ok, status, data) {
            if (ok)
                target = Nutrition.currentTarget(data.results)
        })
        Nutrition.ensure(api, function(ok, error) {
            if (!ok) {
                loading = false
                errorText = error
                return
            }
            Stats.entriesSince(api, null, function(ok2, entries, error2) {
                loading = false
                if (!ok2) {
                    errorText = error2
                    return
                }
                totals = Stats.dailyTotals(entries, Nutrition.foods, Nutrition.recipes)
                firstDay = entries.reduce(function(first, e) {
                    return !first || e.date < first ? e.date : first
                }, "")
            })
        })
    }

    Component.onCompleted: load()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            busy: page.loading
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.load()
            }
        }

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingSmall

            PageHeader {
                title: qsTr("Statistics")
            }

            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }

            SectionHeader {
                text: qsTr("Last 30 days")
            }

            DetailItem {
                label: qsTr("Days logged")
                value: page.summary.daysLogged + " / " + page.summary.daysInRange
            }
            DetailItem {
                label: qsTr("Mean calories")
                value: page.summary.daysLogged
                       ? page.withTarget(page.summary.meanCalories, "daily_calories", "kcal") : "-"
            }
            DetailItem {
                label: qsTr("Typical day (median)")
                value: page.summary.daysLogged ? page.summary.medianCalories + " kcal" : "-"
            }
            DetailItem {
                visible: page.summary.daysLogged > 0
                label: qsTr("Median protein")
                value: page.withTarget(Math.round(page.summary.medianProtein), "protein_grams", "g")
            }
            DetailItem {
                visible: page.summary.daysLogged > 0
                label: qsTr("Median carbohydrates")
                value: page.withTarget(Math.round(page.summary.medianCarbohydrate), "carbohydrate_grams", "g")
            }
            DetailItem {
                visible: page.summary.daysLogged > 0
                label: qsTr("Median fat")
                value: page.withTarget(Math.round(page.summary.medianFat), "fat_grams", "g")
            }

            Label {
                visible: page.summary.possibleLoggingGaps
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.highlightColor
                text: qsTr("Your mean is clearly below your typical day, so some days may be only partly logged.")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("The mean shows your real total intake per day, big days included. The median shows "
                           + "a typical day, and one barely-logged day hardly moves it. Only finished days you "
                           + "logged something count: today is left out until it's over, and a day with nothing "
                           + "logged isn't counted as zero calories.")
            }

            SectionHeader {
                text: qsTr("Per day")
            }

            // Period | days | mean | median | P | C | F. Each number column
            // is as wide as its widest text; with large text, when the
            // period no longer fits beside them, it goes on a line of its own.
            Item {
                id: table
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: tableColumn.height

                //: Column headers: period, days logged, mean and median calories, protein, carbohydrates, fat
                readonly property var headers: [qsTr("Period"), qsTr("Days"), qsTr("Mean"), qsTr("Med."), qsTr("P"), qsTr("C"), qsTr("F")]
                readonly property var rows: page.periods.map(function(p) {
                    var s = p.summary
                    return {
                        period: page.periodText(p.key),
                        cells: s.daysLogged
                               ? [s.daysLogged + "/" + s.daysInRange, String(s.meanCalories), String(s.medianCalories),
                                  String(Math.round(s.medianProtein)), String(Math.round(s.medianCarbohydrate)),
                                  String(Math.round(s.medianFat))]
                               : [s.daysLogged + "/" + s.daysInRange, "-", "-", "-", "-", "-"]
                    }
                })
                readonly property real gap: Theme.paddingMedium
                readonly property var cellWidths: {
                    var widths = []
                    for (var c = 0; c < 6; c++) {
                        var w = metrics.advanceWidth(headers[c + 1])
                        rows.forEach(function(r) { w = Math.max(w, metrics.advanceWidth(r.cells[c])) })
                        widths.push(Math.ceil(w) + gap)
                    }
                    return widths
                }
                readonly property real numbersWidth: cellWidths.reduce(function(a, b) { return a + b }, 0)
                readonly property real periodWidth: {
                    var w = metrics.advanceWidth(headers[0])
                    rows.forEach(function(r) { w = Math.max(w, metrics.advanceWidth(r.period)) })
                    return Math.ceil(w)
                }
                readonly property bool stacked: periodWidth + numbersWidth > width

                FontMetrics {
                    id: metrics
                    font.pixelSize: Theme.fontSizeExtraSmall
                }

                Column {
                    id: tableColumn
                    width: parent.width

                    Row {
                        anchors.right: parent.right
                        Repeater {
                            model: table.stacked ? table.headers.slice(1) : table.headers
                            Label {
                                width: table.stacked ? table.cellWidths[index]
                                     : index === 0 ? table.width - table.numbersWidth : table.cellWidths[index - 1]
                                horizontalAlignment: !table.stacked && index === 0 ? Text.AlignLeft : Text.AlignRight
                                font.pixelSize: Theme.fontSizeExtraSmall
                                color: Theme.secondaryHighlightColor
                                text: modelData
                            }
                        }
                    }

                    Repeater {
                        model: table.rows
                        delegate: Column {
                            width: tableColumn.width
                            Label {
                                visible: table.stacked
                                width: parent.width
                                font.pixelSize: Theme.fontSizeExtraSmall
                                text: modelData.period
                            }
                            Row {
                                anchors.right: parent.right
                                Label {
                                    visible: !table.stacked
                                    width: table.width - table.numbersWidth
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                    truncationMode: TruncationMode.Fade
                                    text: modelData.period
                                }
                                Repeater {
                                    model: modelData.cells
                                    Label {
                                        width: table.cellWidths[index]
                                        horizontalAlignment: Text.AlignRight
                                        font.pixelSize: Theme.fontSizeExtraSmall
                                        color: Theme.highlightColor
                                        text: modelData
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Days: days logged / days in the period. Mean and median calories in kcal, median "
                           + "macros in grams. Today isn't included.")
            }

            SectionHeader {
                text: qsTr("Daily calories (last 30 days)")
            }

            BarChart {
                visible: page.summary.daysLogged > 0 || page.history[page.history.length - 1].value !== null
                unit: "kcal"
                reference: page.target ? page.target.daily_calories : NaN
                bars: page.history.map(function(d) {
                    return { value: d.value, label: Format.formatDate(new Date(d.x), Formatter.DateMedium) }
                })
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: page.summary.daysLogged === 0 && page.history[page.history.length - 1].value === null
                      ? qsTr("Log a few days in your food diary to see your trend here.")
                      : page.target
                        ? qsTr("Dashed line: your current target, %1 kcal. It's the same on every day, even if "
                               + "your target was different back then.").arg(page.target.daily_calories)
                        : ""
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
