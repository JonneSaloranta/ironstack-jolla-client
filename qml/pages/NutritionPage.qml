import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store
import "../js/nutrition.js" as Nutrition

// Nutrition, like the web's dashboard: today's calories and macros against
// the daily target, the current goal and today's diet plan. Everything
// else - diary, foods, recipes, plans, shopping, calculators, profile - is
// in the pull-down.
Page {
    id: page

    property var totals: Nutrition.zero()
    property var target: null
    property var goal: null
    property var activePlan: null
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

    function load() {
        loading = true
        errorText = ""
        var pending = 4
        function settle(ok, error) {
            if (ok === false)
                errorText = error
            if (--pending === 0)
                loading = false
        }
        Nutrition.ensure(api, function(ok, error) {
            if (!ok)
                return settle(false, error)
            Nutrition.entriesFor(api, Store.isoDate(new Date()), function(ok2, entries, error2) {
                if (ok2)
                    totals = Nutrition.total(entries, Nutrition.foods, Nutrition.recipes)
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
                      : qsTr("No goal set. Goals are set on the IronStack web.")
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
        }

        VerticalScrollDecorator {}
    }
}
