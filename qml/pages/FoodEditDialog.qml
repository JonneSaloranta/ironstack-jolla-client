import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

// A food of your own, or changes to one (`food` set) - the web's food
// form: values per serving as on a nutrition label. Required: name,
// serving, calories, protein, carbohydrate and fat; the rest are optional
// and stay "unknown" when empty. The page that opened it saves body().
Dialog {
    id: dialog

    property var food: null
    readonly property var units: ["g", "ml", "piece"]

    function number(field) {
        if (!field)
            return null
        var value = Store.parseNumber(field.text)
        return isNaN(value) ? null : value
    }
    function text(value) {
        return Store.present(value) ? String(parseFloat(value)) : ""
    }

    function body() {
        return {
            name: nameField.text.trim(),
            brand: brandField.text.trim(),
            serving_size: number(servingField),
            serving_unit: units[unitBox.currentIndex],
            calories: Math.round(number(caloriesField) || 0),
            protein_grams: number(fields.protein_grams) || 0,
            carbohydrate_grams: number(fields.carbohydrate_grams) || 0,
            fat_grams: number(fields.fat_grams) || 0,
            saturated_fat_grams: number(fields.saturated_fat_grams),
            sugar_grams: number(fields.sugar_grams),
            starch_grams: number(fields.starch_grams),
            polyols_grams: number(fields.polyols_grams),
            fiber_grams: number(fields.fiber_grams),
            salt_grams: number(fields.salt_grams),
            sodium_mg: number(fields.sodium_mg) === null ? null : Math.round(number(fields.sodium_mg)),
            energy_kj: number(kjField)
        }
    }

    canAccept: nameField.text.trim() !== "" && (number(servingField) || 0) > 0 && number(caloriesField) !== null

    SilicaFlickable {
        id: flickable
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            DialogHeader {
                acceptText: qsTr("Save")
                title: dialog.food ? qsTr("Edit food") : qsTr("New food")
            }
            TextField {
                id: nameField
                width: parent.width
                label: qsTr("Name")
                placeholderText: label
                text: dialog.food ? dialog.food.name : ""
            }
            TextField {
                id: brandField
                width: parent.width
                label: qsTr("Brand")
                placeholderText: label
                text: dialog.food ? dialog.food.brand || "" : ""
            }
            Row {
                width: parent.width
                TextField {
                    id: servingField
                    width: parent.width / 2
                    label: qsTr("Serving size")
                    placeholderText: label
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    validator: RegExpValidator { regExp: /^(\d{1,5}([.,]\d{0,2})?)?$/ }
                    text: dialog.food ? dialog.text(dialog.food.serving_size) : "100"
                }
                ComboBox {
                    id: unitBox
                    width: parent.width / 2
                    label: qsTr("Unit")
                    currentIndex: dialog.food ? Math.max(0, dialog.units.indexOf(dialog.food.serving_unit)) : 0
                    menu: ContextMenu {
                        MenuItem { text: "g" }
                        MenuItem { text: "ml" }
                        MenuItem { text: qsTr("piece") }
                    }
                }
            }

            SectionHeader {
                text: qsTr("Nutrition per serving")
            }
            Row {
                width: parent.width
                TextField {
                    id: caloriesField
                    width: parent.width / 2
                    label: qsTr("Calories")
                    placeholderText: "kcal"
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator { bottom: 0; top: 99999 }
                    text: dialog.food ? String(dialog.food.calories) : ""
                }
                TextField {
                    id: kjField
                    width: parent.width / 2
                    label: qsTr("Energy (kJ)")
                    placeholderText: "kJ"
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    validator: RegExpValidator { regExp: /^(\d{1,6}([.,]\d{0,2})?)?$/ }
                    text: dialog.food ? dialog.text(dialog.food.energy_kj) : ""
                }
            }
            Repeater {
                model: [
                    [qsTr("Fat (g)"), "fat_grams"],
                    [qsTr("of which saturates"), "saturated_fat_grams"],
                    [qsTr("Carbohydrates (g)"), "carbohydrate_grams"],
                    [qsTr("of which sugars"), "sugar_grams"],
                    [qsTr("of which starch"), "starch_grams"],
                    [qsTr("of which polyols"), "polyols_grams"],
                    [qsTr("Fibre"), "fiber_grams"],
                    [qsTr("Protein (g)"), "protein_grams"],
                    [qsTr("Salt"), "salt_grams"],
                    [qsTr("Sodium (mg)"), "sodium_mg"]
                ]
                delegate: TextField {
                    width: column.width
                    label: modelData[0]
                    placeholderText: label
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    validator: RegExpValidator { regExp: /^(\d{1,5}([.,]\d{0,3})?)?$/ }
                    text: dialog.food ? dialog.text(dialog.food[modelData[1]]) : ""
                    Component.onCompleted: dialog.fields[modelData[1]] = this
                }
            }
            KeyboardRoom {
                flickable: flickable
            }
        }

        VerticalScrollDecorator {}
    }

    // field name -> its TextField, filled by the Repeater above; read only
    // when saving, after every field exists.
    property var fields: ({})
}
