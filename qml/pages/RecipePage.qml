import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store
import "../js/nutrition.js" as Nutrition
import "../js/texts.js" as Texts

// One recipe, like the web's: nutrition per serving, the ingredients and
// the instructions. Log it to the diary; edit your own, its ingredients
// (added, amounts changed, removed) or delete it - a built-in one is read
// only, like on the web.
Page {
    id: page

    property int recipeId
    property var recipe: Nutrition.recipes ? Nutrition.recipes[recipeId] || null : null
    property bool loading: false
    property string errorText: ""
    readonly property bool editable: recipe !== null && Store.present(recipe.owner)

    readonly property var perServing: recipe ? Nutrition.recipePerServing(recipe, Nutrition.foods || {}) : Nutrition.zero()

    function load(keepError) {
        loading = true
        Nutrition.ensure(api, function() {
            api.request("GET", "recipes/" + recipeId + "/", null, function(ok, status, data, error) {
                loading = false
                errorText = ok ? (keepError || "") : error
                if (ok) {
                    Nutrition.recipes[recipeId] = data
                    recipe = data
                }
            })
        })
    }

    function write(method, path, body) {
        api.request(method, path, body, function(ok, status, data, error) {
            Nutrition.changed = true
            load(ok ? "" : error)
        })
    }

    function addIngredient() {
        var picker = pageStack.push(Qt.resolvedUrl("FoodsPage.qml"), { picking: true })
        picker.picked.connect(function(kind, foodId) {
            var food = Nutrition.foods[foodId]
            var dialog = pageStack.replace(Qt.resolvedUrl("QuantityDialog.qml"), {
                title: Store.contentName(food.name),
                unitLabel: Nutrition.unitText(food.serving_unit, qsTr("pcs")),
                initialQuantity: parseFloat(food.serving_size)
            })
            dialog.accepted.connect(function() {
                write("POST", "recipe-ingredients/", { recipe: recipeId, food: foodId, quantity: dialog.quantity,
                                                       order: (recipe.ingredients || []).length })
            })
        })
    }

    function editIngredient(ingredient) {
        var food = Nutrition.foods[ingredient.food]
        var dialog = pageStack.push(Qt.resolvedUrl("QuantityDialog.qml"), {
            title: food ? Store.contentName(food.name) : "",
            unitLabel: food ? Nutrition.unitText(food.serving_unit, qsTr("pcs")) : "",
            initialQuantity: parseFloat(ingredient.quantity)
        })
        dialog.accepted.connect(function() {
            write("PATCH", "recipe-ingredients/" + ingredient.id + "/", { quantity: dialog.quantity })
        })
    }

    function logToDiary() {
        var dialog = pageStack.push(Qt.resolvedUrl("DiaryEntryDialog.qml"), {
            kind: "recipe", itemId: recipeId, slot: (Nutrition.slots || [])[0] || null
        })
        dialog.accepted.connect(function() {
            syncQueue.enqueue("POST", "diary-entries/", dialog.body())
            Nutrition.diaryEdited()
        })
    }

    Component.onCompleted: load()

    RemorsePopup {
        id: remorse
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: page.recipe ? (page.recipe.ingredients || []).slice().sort(function(a, b) { return a.order - b.order || a.id - b.id }) : []

        PullDownMenu {
            busy: page.loading
            MenuItem {
                visible: page.editable
                text: qsTr("Delete")
                onClicked: remorse.execute(qsTr("Deleting recipe"), function() {
                    api.request("DELETE", "recipes/" + page.recipeId + "/", null, function(ok, status, data, error) {
                        if (!ok) {
                            page.errorText = error
                            return
                        }
                        Nutrition.changed = true
                        pageStack.pop()
                    })
                })
            }
            MenuItem {
                visible: page.editable
                text: qsTr("Edit")
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("RecipeEditDialog.qml"), { recipe: page.recipe })
                    dialog.accepted.connect(function() { page.write("PATCH", "recipes/" + page.recipeId + "/", dialog.body()) })
                }
            }
            MenuItem {
                visible: page.editable
                text: qsTr("Add ingredient")
                onClicked: page.addIngredient()
            }
            MenuItem {
                enabled: page.recipe !== null && (page.recipe.ingredients || []).length > 0
                text: qsTr("Log to diary")
                onClicked: page.logToDiary()
            }
        }

        header: Column {
            width: parent.width
            PageHeader {
                title: page.recipe ? Store.contentName(page.recipe.name) : ""
                description: page.recipe ? qsTr("%n serving(s)", "", page.recipe.servings)
                                           + (page.editable ? "" : " · " + qsTr("Built-in")) : ""
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }
            SectionHeader {
                text: qsTr("Per serving")
            }
            MacroSummary {
                totals: page.perServing
            }
            Label {
                visible: text !== ""
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                topPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                text: page.recipe ? Texts.contentText(page.recipe.instructions) : ""
            }
            SectionHeader {
                text: qsTr("Ingredients")
            }
        }

        delegate: ListItem {
            id: item
            property var food: Nutrition.foods ? Nutrition.foods[modelData.food] : null
            contentHeight: Math.max(Theme.itemSizeSmall, row.height + 2 * Theme.paddingSmall)
            onClicked: {
                if (page.editable)
                    page.editIngredient(modelData)
            }
            menu: page.editable ? ingredientMenu : null
            Component {
                id: ingredientMenu
                ContextMenu {
                    MenuItem {
                        text: qsTr("Edit")
                        onClicked: page.editIngredient(modelData)
                    }
                    MenuItem {
                        text: qsTr("Remove")
                        onClicked: {
                            var id = modelData.id
                            item.remorseDelete(function() { page.write("DELETE", "recipe-ingredients/" + id + "/", null) })
                        }
                    }
                }
            }
            Row {
                id: row
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                Label {
                    width: parent.width - amount.width
                    truncationMode: TruncationMode.Fade
                    text: food ? Store.contentName(food.name) : "#" + modelData.food
                }
                Label {
                    id: amount
                    color: Theme.highlightColor
                    text: Store.formatNumber(parseFloat(modelData.quantity)) + " "
                          + (food ? Nutrition.unitText(food.serving_unit, qsTr("pcs")) : "")
                          + (food ? " · " + Math.round(Nutrition.forFood(food, modelData.quantity).calories) + " kcal" : "")
                }
            }
        }

        ViewPlaceholder {
            enabled: !page.loading && page.recipe !== null && (page.recipe.ingredients || []).length === 0
            text: qsTr("No ingredients yet.")
            hintText: page.editable ? qsTr("Pull down to add one") : ""
        }

        VerticalScrollDecorator {}
    }
}
