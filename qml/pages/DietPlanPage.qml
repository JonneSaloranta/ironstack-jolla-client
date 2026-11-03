import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store
import "../js/nutrition.js" as Nutrition

// One diet plan, like the web's: its targets, then each meal (per weekday
// for a weekly plan) with what the builder put in it. Activate or
// deactivate it, log a day of it to the diary, open its shopping list,
// rename or delete it. A recipe opens with its ingredients.
Page {
    id: page

    property int planId
    property var plan: null
    property bool loading: false
    property string errorText: ""

    readonly property var meals: plan ? plan.meals.slice().sort(function(a, b) {
        return (a.weekday === null ? -1 : a.weekday) - (b.weekday === null ? -1 : b.weekday) || a.order - b.order
    }) : []

    function weekdayName(index) {
        return Qt.locale().dayName((index + 1) % 7, Locale.LongFormat)
    }

    function slotName(id) {
        var slot = (Nutrition.slots || []).filter(function(s) { return s.id === id })[0]
        return slot ? Store.shown(slot) : ""
    }

    function itemName(item) {
        if (Store.present(item.food))
            return Nutrition.foods && Nutrition.foods[item.food] ? Store.shown(Nutrition.foods[item.food]) : "#" + item.food
        if (Nutrition.recipes && Nutrition.recipes[item.recipe])
            return Store.shown(Nutrition.recipes[item.recipe])
        return "#" + item.recipe
    }

    function itemCalories(item) {
        var n = Nutrition.forEntry({ food: item.food, recipe: item.recipe, quantity: item.quantity },
                                   Nutrition.foods || {}, Nutrition.recipes || {})
        return Store.present(item.recipe) && !(Nutrition.recipes && Nutrition.recipes[item.recipe]) ? null : Math.round(n.calories)
    }

    CoachLinks {
        id: coach
        kind: "diet-plans"
        planId: page.planId
        own: true
        onUpdated: page.load()
        onFailed: page.errorText = error
    }

    function load(keepError) {
        loading = true
        Nutrition.ensure(api, function() {
            api.request("GET", "diet-plans/" + planId + "/", null, function(ok, status, data, error) {
                loading = false
                errorText = ok ? (keepError || "") : error
                if (ok)
                    plan = data
            })
        })
    }

    function action(path, body) {
        loading = true
        api.request("POST", "diet-plans/" + planId + "/" + path, body, function(ok, status, data, error) {
            Store.dietPlansChanged = true
            if (path === "apply/")
                Nutrition.diaryEdited()
            load(ok ? "" : error)
        })
    }

    Component.onCompleted: load()

    RemorsePopup {
        id: remorse
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: page.meals
        section.property: "weekday"
        section.delegate: SectionHeader {
            visible: section !== ""
            text: section !== "" ? page.weekdayName(parseInt(section, 10)) : ""
        }

        PullDownMenu {
            busy: page.loading
            MenuItem {
                visible: coach.updateAvailable
                text: qsTr("Update from coach")
                onClicked: coach.update()
            }
            MenuItem {
                visible: coach.clients.length > 0
                text: qsTr("Share with clients")
                onClicked: coach.share()
            }
            MenuItem {
                text: qsTr("Delete")
                onClicked: remorse.execute(qsTr("Deleting plan"), function() {
                    api.request("DELETE", "diet-plans/" + page.planId + "/", null, function(ok, status, data, error) {
                        if (!ok)
                            return page.load(error)
                        // Its shopping list ticks go with it.
                        settings.removeCached("shopping/" + page.planId)
                        Store.dietPlansChanged = true
                        pageStack.pop()
                    })
                })
            }
            MenuItem {
                text: qsTr("Rename")
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("NameDialog.qml"), { title: qsTr("Rename"), initialName: page.plan.name })
                    dialog.accepted.connect(function() {
                        api.request("PATCH", "diet-plans/" + page.planId + "/", { name: dialog.name }, function(ok, status, data, error) {
                            Store.dietPlansChanged = true
                            page.load(ok ? "" : error)
                        })
                    })
                }
            }
            MenuItem {
                visible: page.plan !== null
                text: page.plan && page.plan.is_active ? qsTr("Deactivate") : qsTr("Activate")
                onClicked: page.action(page.plan.is_active ? "deactivate/" : "activate/", {})
            }
            MenuItem {
                text: qsTr("Shopping list")
                onClicked: pageStack.push(Qt.resolvedUrl("ShoppingListPage.qml"), { planId: page.planId })
            }
            MenuItem {
                text: qsTr("Log for date")
                onClicked: {
                    var picker = pageStack.push("Sailfish.Silica.DatePickerDialog", { date: new Date() })
                    picker.accepted.connect(function() { page.action("apply/", { date: Store.isoDate(picker.date) }) })
                }
            }
        }

        header: Column {
            width: parent.width
            PageHeader {
                title: page.plan ? page.plan.name : ""
                description: page.plan && page.plan.is_active ? qsTr("Active") : ""
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }
            Label {
                visible: page.plan !== null
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.highlightColor
                text: page.plan ? qsTr("Daily target") + ": " + page.plan.target_calories + " kcal · "
                                  + qsTr("P") + " " + Math.round(parseFloat(page.plan.target_protein_grams)) + " g · "
                                  + qsTr("C") + " " + Math.round(parseFloat(page.plan.target_carbohydrate_grams)) + " g · "
                                  + qsTr("F") + " " + Math.round(parseFloat(page.plan.target_fat_grams)) + " g" : ""
            }
        }

        delegate: Column {
            width: list.width
            bottomPadding: Theme.paddingMedium
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                topPadding: Theme.paddingMedium
                color: Theme.highlightColor
                text: page.slotName(modelData.meal_slot) + " · " + modelData.target_calories + " kcal"
            }
            Repeater {
                model: modelData.items
                // Opens the food or recipe, like the web's links.
                delegate: BackgroundItem {
                    width: list.width
                    height: itemRow.height + 2 * Theme.paddingSmall
                    onClicked: {
                        if (Store.present(modelData.recipe))
                            pageStack.push(Qt.resolvedUrl("RecipePage.qml"), { recipeId: modelData.recipe })
                        else
                            pageStack.push(Qt.resolvedUrl("FoodPage.qml"), { foodId: modelData.food })
                    }
                    Row {
                        id: itemRow
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        Label {
                            width: parent.width - kcal.width
                            truncationMode: TruncationMode.Fade
                            font.pixelSize: Theme.fontSizeSmall
                            text: page.itemName(modelData) + " · " + Store.formatNumber(parseFloat(modelData.quantity))
                                  + (Store.present(modelData.food) && Nutrition.foods && Nutrition.foods[modelData.food]
                                     ? " " + Nutrition.unitText(Nutrition.foods[modelData.food].serving_unit, qsTr("pcs"))
                                     : " " + qsTr("serving(s)"))
                        }
                        Label {
                            id: kcal
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.secondaryColor
                            text: page.itemCalories(modelData) !== null ? page.itemCalories(modelData) + " kcal" : ""
                        }
                    }
                }
            }
            Label {
                visible: modelData.items.length === 0
                x: Theme.horizontalPageMargin
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
                text: qsTr("Nothing planned")
            }
        }

        VerticalScrollDecorator {}
    }
}
