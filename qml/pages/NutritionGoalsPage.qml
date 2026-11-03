import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store
import "../js/nutrition.js" as Nutrition

// The nutrition goal and daily target with their history, and the
// nutrition profile behind them, like the web's: set up the profile, start
// a new goal (IronStack calculates its target), correct the profile.
Page {
    id: page

    property var goals: []
    property var targets: []
    property var profile: null
    property bool noProfile: false
    property bool loading: false
    property string errorText: ""

    readonly property var goal: Nutrition.currentGoal(goals)
    readonly property var target: Nutrition.currentTarget(targets)

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

    function activityText(level) {
        switch (level) {
        case "sedentary": return qsTr("Sedentary")
        case "light": return qsTr("Lightly active")
        case "moderate": return qsTr("Moderately active")
        case "active": return qsTr("Active")
        case "very_active": return qsTr("Very active")
        }
        return level || ""
    }

    function load(keepError) {
        loading = true
        var pending = 3
        var failure = keepError || ""
        function settle(ok, error) {
            if (ok === false)
                failure = error
            if (--pending === 0) {
                loading = false
                errorText = failure
            }
        }
        api.request("GET", "nutrition-goals/?page_size=100", null, function(ok, status, data, error) {
            if (ok)
                goals = data.results
            settle(ok, error)
        })
        api.request("GET", "nutrition-targets/?page_size=100", null, function(ok, status, data, error) {
            if (ok)
                targets = data.results
            settle(ok, error)
        })
        api.request("GET", "nutrition/profile/", null, function(ok, status, data, error) {
            noProfile = status === 404
            profile = ok ? data : null
            settle(ok || status === 404, error)
        })
    }

    function editProfile() {
        var dialog = pageStack.push(Qt.resolvedUrl("NutritionProfileDialog.qml"), { profile: page.profile || {} })
        dialog.accepted.connect(function() {
            // PUT creates the profile, PATCH corrects it.
            api.request(page.profile ? "PATCH" : "PUT", "nutrition/profile/", dialog.body(),
                        function(ok, status, data, error) {
                page.load(ok ? "" : error)
            })
        })
    }

    function newGoal() {
        var dialog = pageStack.push(Qt.resolvedUrl("NutritionGoalDialog.qml"), { goal: page.goal })
        dialog.accepted.connect(function() {
            loading = true
            api.request("POST", "nutrition-goals/", dialog.body(), function(ok, status, data, error) {
                Nutrition.diaryChanged = true
                page.load(ok ? "" : error)
            })
        })
    }

    Component.onCompleted: load()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            visible: page.profile !== null || page.noProfile
            busy: page.loading
            MenuItem {
                text: page.profile ? qsTr("Edit profile") : qsTr("Set up nutrition profile")
                onClicked: page.editProfile()
            }
            MenuItem {
                visible: page.profile !== null
                text: qsTr("New goal")
                onClicked: page.newGoal()
            }
        }

        Column {
            id: column
            width: parent.width

            PageHeader {
                title: qsTr("Goal and profile")
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }

            SectionHeader {
                text: qsTr("Current goal")
            }
            DetailItem {
                visible: page.goal !== null
                label: qsTr("Goal")
                value: page.goal ? page.goalText(page.goal.goal_type) : ""
            }
            DetailItem {
                visible: page.goal !== null && Store.present(page.goal.target_weight)
                label: qsTr("Target weight")
                value: page.goal ? Store.formatWeight(page.goal.target_weight, settings.unitSystem) : ""
            }
            DetailItem {
                visible: page.goal !== null && Store.present(page.goal.target_rate_kg_per_week)
                label: qsTr("Rate per week")
                value: page.goal ? Store.formatWeight(page.goal.target_rate_kg_per_week, settings.unitSystem) : ""
            }

            SectionHeader {
                text: qsTr("Daily target")
            }
            DetailItem {
                visible: page.target !== null
                label: qsTr("Calories")
                value: page.target ? page.target.daily_calories + " kcal" : ""
            }
            DetailItem {
                visible: page.target !== null
                label: qsTr("Protein")
                value: page.target ? Math.round(parseFloat(page.target.protein_grams)) + " g" : ""
            }
            DetailItem {
                visible: page.target !== null
                label: qsTr("Carbohydrates")
                value: page.target ? Math.round(parseFloat(page.target.carbohydrate_grams)) + " g" : ""
            }
            DetailItem {
                visible: page.target !== null
                label: qsTr("Fat")
                value: page.target ? Math.round(parseFloat(page.target.fat_grams)) + " g" : ""
            }
            Label {
                visible: text !== ""
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: page.target ? page.target.reason || "" : ""
            }
            Label {
                visible: !page.loading && page.goal === null && page.target === null
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                text: page.profile ? qsTr("No goal set yet. Pull down to set one.")
                                   : qsTr("No goal set yet. Set up your nutrition profile first.")
            }

            SectionHeader {
                text: qsTr("Nutrition profile")
            }
            Label {
                visible: page.noProfile
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                text: qsTr("No nutrition profile yet. Pull down to set it up: the daily target is calculated "
                           + "from it, your height (Settings) and your latest body weight.")
            }
            Column {
                visible: page.profile !== null
                width: parent.width
                DetailItem {
                    label: qsTr("Age (years)")
                    value: page.profile && Store.present(page.profile.age_years) ? page.profile.age_years : "-"
                }
                DetailItem {
                    label: qsTr("Biological sex")
                    value: page.profile ? (page.profile.biological_sex === "female" ? qsTr("Female")
                                           : page.profile.biological_sex === "male" ? qsTr("Male") : "-") : ""
                }
                DetailItem {
                    label: qsTr("Activity level")
                    value: page.profile ? page.activityText(page.profile.activity_level) || "-" : ""
                }
                DetailItem {
                    visible: page.profile !== null && Store.present(page.profile.training_sessions_per_week)
                    label: qsTr("Gym sessions per week")
                    value: page.profile ? page.profile.training_sessions_per_week : ""
                }
            }

            SectionHeader {
                visible: page.goals.length > 1
                text: qsTr("Earlier goals")
            }
            Repeater {
                model: page.goals.filter(function(g) { return Store.present(g.ended_at) })
                delegate: DetailItem {
                    label: Format.formatDate(new Date(modelData.started_at), Formatter.DateMedium)
                    value: page.goalText(modelData.goal_type)
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
