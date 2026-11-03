import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store
import "../js/nutrition.js" as Nutrition
import "../js/nutritionstats.js" as Stats

// Nutrition, like the web's dashboard: today's calories and macros against
// the daily target, the current goal, today's diet plan, whether the
// target is working and the observed maintenance. Everything else -
// diary, foods, recipes, plans, shopping, stats, calculators, profile - is
// in the pull-down. The calorie adjustment is IronStack's own and can be
// accepted here; the observed maintenance is worked out from the diary and
// body weight like the web's (apps/nutrition/maintenance.py).
Page {
    id: page

    property var totals: Nutrition.zero()
    property var target: null
    property var goal: null
    property var activePlan: null
    // Diary day totals for the last 28 finished days and today.
    property var dayTotals: null
    property var weights: null
    property string weightError: ""
    readonly property var maintenance: dayTotals !== null && weights !== null
                                       ? Stats.estimateMaintenance(dayTotals, weights, new Date()) : null
    // nutrition/adjustment-suggestion/: { action, suggested_daily_calories,
    // confidence, reason } - reason in the IronStack profile's language.
    property var suggestion: null
    property bool accepting: false
    property bool loading: false
    property string errorText: ""

    function goalText(type) {
        switch (type) {
        case "fat_loss_aggressive": return qsTr("Fat loss - aggressive")
        case "fat_loss_moderate": return qsTr("Fat loss - moderate")
        case "fat_loss_conservative": return qsTr("Fat loss - conservative")
        case "maintenance": return qsTr("Maintenance")
        case "muscle_gain_lean": return qsTr("Muscle gain - lean bulk")
        case "muscle_gain_moderate": return qsTr("Muscle gain - moderate bulk")
        case "muscle_gain_aggressive": return qsTr("Muscle gain - aggressive bulk")
        }
        return type || ""
    }

    function confidenceText(confidence) {
        if (confidence === "high")
            return qsTr("High confidence")
        if (confidence === "medium")
            return qsTr("Medium confidence")
        return qsTr("Low confidence")
    }

    // A kg/week rate in the user's unit, two decimals.
    function rateText(kgPerWeek) {
        return Store.kgToDisplay(kgPerWeek, settings.unitSystem).toFixed(2)
    }

    // The web's "Accept": IronStack works the suggestion out again and,
    // if it still says adjust, replaces the target.
    function acceptSuggestion() {
        accepting = true
        api.request("POST", "nutrition/adjustment-suggestion/accept/", null, function(ok, status, data, error) {
            accepting = false
            if (!ok && status === 409 && data && data.reason)
                suggestion = data
            else if (!ok)
                errorText = error
            load()
        })
    }

    function maintenanceText(m) {
        if (!m)
            return ""
        switch (m.reason) {
        case "food":
            return qsTr("Not enough logged food yet: %1 of the %2 days needed in the last %3 days.")
                    .arg(m.stats.daysLogged).arg(Stats.MAINTENANCE_MIN_FOOD_DAYS).arg(Stats.MAINTENANCE_WINDOW_DAYS)
        case "weight":
            return qsTr("Not enough logged weight yet: it takes at least %1 weigh-in days over %2 days.")
                    .arg(Stats.MIN_DISTINCT_DAYS).arg(Stats.MIN_SPAN_DAYS)
        case "implausible":
            return qsTr("The logged food and weight don't add up to a believable figure yet. Some days may be "
                        + "only partly logged.")
        }
        var text = qsTr("You ate %1 kcal/day on average while your weight changed %2 %3/week over the last %4 days.")
                .arg(m.stats.meanCalories).arg(rateText(m.trend.rate)).arg(Store.weightUnit(settings.unitSystem))
                .arg(m.trend.spanDays)
        if (m.stats.possibleLoggingGaps)
            text += " " + qsTr("Some days may be only partly logged, which makes this estimate too low.")
        return text
    }

    function load() {
        loading = true
        errorText = ""
        var pending = 6
        function settle(ok, error) {
            if (ok === false)
                errorText = error
            if (--pending === 0)
                loading = false
        }
        Nutrition.ensure(api, function(ok, error) {
            if (!ok)
                return settle(false, error)
            var today = new Date()
            var since = Store.isoDate(Store.addDays(today, -Stats.MAINTENANCE_WINDOW_DAYS))
            Stats.entriesSince(api, since, function(ok2, entries, error2) {
                if (ok2) {
                    dayTotals = Stats.dailyTotals(entries, Nutrition.foods, Nutrition.recipes)
                    totals = dayTotals[Store.isoDate(today)] || Nutrition.zero()
                }
                settle(ok2, error2)
            })
        })
        api.request("GET", "nutrition-targets/?page_size=100", null, function(ok, status, data, error) {
            if (ok)
                target = Nutrition.currentTarget(data.results)
            settle(ok, error)
        })
        api.request("GET", "nutrition-goals/?page_size=100", null, function(ok, status, data, error) {
            if (ok)
                goal = Nutrition.currentGoal(data.results)
            settle(ok, error)
        })
        // Body weight needs the measurements permission; without it only
        // the two cards below say so.
        var weightsSince = new Date(Date.now() - Stats.MAINTENANCE_WINDOW_DAYS * 86400000)
        Stats.bodyWeightSince(api, weightsSince, function(ok, readings, error) {
            weights = ok ? readings : null
            weightError = ok ? "" : error
            settle(true, "")
        })
        api.request("GET", "nutrition/adjustment-suggestion/", null, function(ok, status, data, error) {
            suggestion = ok ? data : null
            settle(ok, error)
        })
        api.request("GET", "diet-plans/?page_size=100", null, function(ok, status, data, error) {
            if (ok)
                activePlan = (data.results || []).filter(function(p) { return p.is_active })[0] || null
            settle(ok, error)
        })
    }

    Component.onCompleted: load()
    onStatusChanged: {
        if (status === PageStatus.Active && Nutrition.diaryChanged) {
            Nutrition.diaryChanged = false
            load()
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            busy: page.loading
            MenuItem {
                text: qsTr("Calculators")
                onClicked: pageStack.push(Qt.resolvedUrl("CalculatorsPage.qml"))
            }
            MenuItem {
                text: qsTr("Statistics")
                onClicked: pageStack.push(Qt.resolvedUrl("NutritionStatsPage.qml"))
            }
            MenuItem {
                text: qsTr("Goal and profile")
                onClicked: pageStack.push(Qt.resolvedUrl("NutritionGoalsPage.qml"))
            }
            MenuItem {
                text: qsTr("Diet plans")
                onClicked: pageStack.push(Qt.resolvedUrl("DietPlansPage.qml"))
            }
            MenuItem {
                text: qsTr("Recipes")
                onClicked: pageStack.push(Qt.resolvedUrl("RecipesPage.qml"))
            }
            MenuItem {
                text: qsTr("Foods")
                onClicked: pageStack.push(Qt.resolvedUrl("FoodsPage.qml"))
            }
            MenuItem {
                text: qsTr("Open food diary")
                onClicked: pageStack.push(Qt.resolvedUrl("DiaryPage.qml"))
            }
        }

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingSmall

            PageHeader {
                title: qsTr("Nutrition")
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }

            SectionHeader {
                text: qsTr("Today so far")
            }
            MacroSummary {
                totals: page.totals
                target: page.target
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Log food now")
                onClicked: pageStack.push(Qt.resolvedUrl("DiaryPage.qml"))
            }

            SectionHeader {
                text: qsTr("Current goal")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: page.goal ? Theme.highlightColor : Theme.secondaryColor
                text: page.goal
                      ? [page.goalText(page.goal.goal_type),
                         Store.present(page.goal.target_weight)
                         ? Store.formatWeight(page.goal.target_weight, settings.unitSystem) : "",
                         page.target ? qsTr("Daily target") + " " + page.target.daily_calories + " kcal" : ""]
                        .filter(function(p) { return p }).join(" · ")
                      : qsTr("No goal set yet. Set one under Goal and profile.")
            }

            SectionHeader {
                text: qsTr("Today's plan")
            }
            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeSmall
                enabled: page.activePlan !== null
                onClicked: pageStack.push(Qt.resolvedUrl("DietPlanPage.qml"), { planId: page.activePlan.id })
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    truncationMode: TruncationMode.Fade
                    color: page.activePlan ? Theme.primaryColor : Theme.secondaryColor
                    text: page.activePlan ? page.activePlan.name : qsTr("Nothing planned")
                }
            }

            SectionHeader {
                visible: suggestionLabel.visible
                text: qsTr("Is your current target working?")
            }
            Label {
                id: suggestionLabel
                visible: page.suggestion !== null && page.suggestion.action !== "no_active_goal"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: page.suggestion && page.suggestion.action === "adjust" ? Theme.highlightColor : Theme.secondaryColor
                text: page.suggestion ? page.suggestion.reason : ""
            }
            Label {
                visible: page.suggestion !== null && page.suggestion.action === "adjust"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: visible ? page.confidenceText(page.suggestion.confidence) : ""
            }
            Button {
                visible: page.suggestion !== null && page.suggestion.action === "adjust"
                anchors.horizontalCenter: parent.horizontalCenter
                enabled: !page.accepting
                text: visible ? qsTr("Adjust to %1 kcal/day").arg(page.suggestion.suggested_daily_calories) : ""
                onClicked: page.acceptSuggestion()
            }

            SectionHeader {
                text: qsTr("Observed maintenance")
            }
            Label {
                visible: page.maintenance !== null && page.maintenance.calories !== null
                x: Theme.horizontalPageMargin
                font.pixelSize: Theme.fontSizeLarge
                color: Theme.highlightColor
                text: visible ? qsTr("%1 kcal/day").arg(page.maintenance.calories) : ""
            }
            Label {
                visible: page.maintenance !== null && page.maintenance.calories !== null
                x: Theme.horizontalPageMargin
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: visible ? page.confidenceText(page.maintenance.confidence) : ""
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
                text: page.weightError ? page.weightError : page.maintenanceText(page.maintenance)
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("An estimate of what you really burn, based on your food diary and weight. It doesn't "
                           + "change your target.")
            }
        }

        VerticalScrollDecorator {}
    }
}
