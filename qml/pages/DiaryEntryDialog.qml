import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store
import "../js/nutrition.js" as Nutrition

// A diary entry, like the web's forms: a food (amount in its unit), a
// recipe (servings) or a quick entry (name, calories and macros per
// portion; calories estimated from the macros when left empty). With
// `entry` set it corrects one. The page that opened it saves body().
Dialog {
    id: dialog

    property var entry: null
    // "food", "recipe" or "quick"
    property string kind: entry ? (Store.present(entry.food) ? "food" : Store.present(entry.recipe) ? "recipe" : "quick")
                                : "food"
    property int itemId: entry ? (kind === "food" ? entry.food : kind === "recipe" ? entry.recipe : 0) : 0
    property var slot: null
    property date day: entry ? Store.parseDate(entry.date) : new Date()

    readonly property var food: kind === "food" && Nutrition.foods ? Nutrition.foods[itemId] || null : null
    readonly property var recipe: kind === "recipe" && Nutrition.recipes ? Nutrition.recipes[itemId] || null : null

    function number(field) {
        var value = Store.parseNumber(field.text)
        return isNaN(value) ? null : value
    }

    function body() {
        var result = {
            date: Store.isoDate(day),
            meal_slot: slot.id,
            quantity: number(quantityField) || 1,
            notes: notesArea.text
        }
        // A null food or recipe crashes the server (IronStack #39), so the
        // one not used is left out.
        if (kind === "quick") {
            result.quick_name = nameField.text.trim()
            result.quick_protein_grams = number(proteinField)
            result.quick_carbohydrate_grams = number(carbsField)
            result.quick_fat_grams = number(fatField)
            var calories = number(caloriesField)
            result.quick_calories = calories !== null ? Math.round(calories)
                    : Nutrition.caloriesFromMacros(result.quick_protein_grams, result.quick_carbohydrate_grams,
                                                   result.quick_fat_grams)
        } else {
            result[kind] = itemId
        }
        return result
    }

    readonly property var preview: kind === "food" && food ? Nutrition.forFood(food, number(quantityField) || 0)
                                 : kind === "recipe" && recipe
                                   ? Nutrition.scale(Nutrition.recipePerServing(recipe, Nutrition.foods), number(quantityField) || 0)
                                   : null

    canAccept: slot !== null && (number(quantityField) || 0) > 0
               && (kind !== "quick" || number(caloriesField) !== null || number(proteinField) !== null
                   || number(carbsField) !== null || number(fatField) !== null)

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            DialogHeader {
                acceptText: qsTr("Save")
                title: dialog.kind === "quick" ? qsTr("Quick entry")
                       : dialog.food ? Store.shown(dialog.food)
                       : dialog.recipe ? Store.shown(dialog.recipe) : ""
            }

            ComboBox {
                label: qsTr("Meal")
                value: dialog.slot ? Store.shown(dialog.slot) : ""
                menu: ContextMenu {
                    Repeater {
                        model: Nutrition.slots || []
                        MenuItem {
                            text: Store.shown(modelData)
                            onClicked: dialog.slot = modelData
                        }
                    }
                }
            }
            DatePickerButton {
                label: qsTr("Date")
                date: dialog.day
                onPicked: dialog.day = date
            }

            TextField {
                id: nameField
                visible: dialog.kind === "quick"
                width: parent.width
                label: qsTr("Name")
                placeholderText: qsTr("Optional - e.g. the restaurant dish.")
                text: dialog.entry ? dialog.entry.quick_name || "" : ""
            }
            TextField {
                id: caloriesField
                visible: dialog.kind === "quick"
                width: parent.width
                label: qsTr("Calories")
                placeholderText: qsTr("kcal. Leave blank to estimate it from the macros.")
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 0; top: 99999 }
                text: dialog.entry && Store.present(dialog.entry.quick_calories) ? String(dialog.entry.quick_calories) : ""
            }
            Row {
                visible: dialog.kind === "quick"
                width: parent.width
                TextField {
                    id: proteinField
                    width: parent.width / 3
                    label: qsTr("Protein (g)")
                    placeholderText: qsTr("Protein")
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    validator: RegExpValidator { regExp: /^(\d{1,4}([.,]\d{0,2})?)?$/ }
                    text: dialog.entry && Store.present(dialog.entry.quick_protein_grams)
                          ? String(parseFloat(dialog.entry.quick_protein_grams)) : ""
                }
                TextField {
                    id: carbsField
                    width: parent.width / 3
                    label: qsTr("Carbohydrates (g)")
                    placeholderText: qsTr("Carbohydrates")
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    validator: RegExpValidator { regExp: /^(\d{1,4}([.,]\d{0,2})?)?$/ }
                    text: dialog.entry && Store.present(dialog.entry.quick_carbohydrate_grams)
                          ? String(parseFloat(dialog.entry.quick_carbohydrate_grams)) : ""
                }
                TextField {
                    id: fatField
                    width: parent.width / 3
                    label: qsTr("Fat (g)")
                    placeholderText: qsTr("Fat")
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    validator: RegExpValidator { regExp: /^(\d{1,4}([.,]\d{0,2})?)?$/ }
                    text: dialog.entry && Store.present(dialog.entry.quick_fat_grams)
                          ? String(parseFloat(dialog.entry.quick_fat_grams)) : ""
                }
            }

            TextField {
                id: quantityField
                width: parent.width
                label: dialog.kind === "food" && dialog.food
                       ? qsTr("Amount (%1)").arg(Nutrition.unitText(dialog.food.serving_unit, qsTr("pcs")))
                       : dialog.kind === "recipe" ? qsTr("Servings") : qsTr("Portions")
                placeholderText: label
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                validator: RegExpValidator { regExp: /^(\d{1,5}([.,]\d{0,2})?)?$/ }
                text: dialog.entry ? String(parseFloat(dialog.entry.quantity))
                      : dialog.kind === "food" && dialog.food ? String(parseFloat(dialog.food.serving_size)) : "1"
            }

            Label {
                visible: dialog.preview !== null
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.highlightColor
                text: dialog.preview
                      ? Math.round(dialog.preview.calories) + " kcal · " + qsTr("P") + " " + Nutrition.round1(dialog.preview.protein_grams)
                        + " g · " + qsTr("C") + " " + Nutrition.round1(dialog.preview.carbohydrate_grams)
                        + " g · " + qsTr("F") + " " + Nutrition.round1(dialog.preview.fat_grams) + " g"
                      : ""
            }

            TextArea {
                id: notesArea
                width: parent.width
                label: qsTr("Notes")
                placeholderText: label
                text: dialog.entry ? dialog.entry.notes || "" : ""
            }
        }

        VerticalScrollDecorator {}
    }
}
