import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/store.js" as Store
import "../js/nutrition.js" as Nutrition

// A new diet plan - the web's diet plan form: name, daily targets, which
// meals, and whether to vary the meals across a week. IronStack's diet
// builder fills it in. The targets start from the current daily target.
// The page that opened it saves body().
Dialog {
    id: dialog

    property var target: null
    property var slots: []
    property var chosen: []

    function number(field) {
        var value = Store.parseNumber(field.text)
        return isNaN(value) ? null : value
    }

    function toggle(id) {
        var copy = chosen.slice()
        var at = copy.indexOf(id)
        if (at >= 0)
            copy.splice(at, 1)
        else
            copy.push(id)
        chosen = copy
    }

    function body() {
        return {
            name: nameField.text.trim(),
            target_calories: Math.round(number(caloriesField)),
            target_protein_grams: number(proteinField),
            target_carbohydrate_grams: number(carbsField),
            target_fat_grams: number(fatField),
            is_weekly: weeklySwitch.checked,
            meal_slots: chosen
        }
    }

    canAccept: nameField.text.trim() !== "" && number(caloriesField) > 0 && number(proteinField) !== null
               && number(carbsField) !== null && number(fatField) !== null && chosen.length > 0

    Component.onCompleted: {
        api.request("GET", "nutrition-targets/?page_size=100", null, function(ok, status, data) {
            if (ok)
                target = Nutrition.currentTarget(data.results)
        })
        Nutrition.ensure(api, function() {
            slots = Nutrition.slots || []
            chosen = slots.map(function(s) { return s.id })
        })
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            DialogHeader {
                acceptText: qsTr("Create")
                title: qsTr("New diet plan")
            }
            TextField {
                id: nameField
                width: parent.width
                label: qsTr("Plan name")
                placeholderText: label
            }
            TextField {
                id: caloriesField
                width: parent.width
                label: qsTr("Daily calories")
                placeholderText: label
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 1; top: 20000 }
                text: dialog.target ? String(dialog.target.daily_calories) : ""
            }
            Row {
                width: parent.width
                TextField {
                    id: proteinField
                    width: parent.width / 3
                    label: qsTr("Protein (g)")
                    placeholderText: qsTr("Protein")
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    validator: RegExpValidator { regExp: /^(\d{1,4}([.,]\d{0,2})?)?$/ }
                    text: dialog.target ? String(Math.round(parseFloat(dialog.target.protein_grams))) : ""
                }
                TextField {
                    id: carbsField
                    width: parent.width / 3
                    label: qsTr("Carbohydrates (g)")
                    placeholderText: qsTr("Carbohydrates")
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    validator: RegExpValidator { regExp: /^(\d{1,4}([.,]\d{0,2})?)?$/ }
                    text: dialog.target ? String(Math.round(parseFloat(dialog.target.carbohydrate_grams))) : ""
                }
                TextField {
                    id: fatField
                    width: parent.width / 3
                    label: qsTr("Fat (g)")
                    placeholderText: qsTr("Fat")
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    validator: RegExpValidator { regExp: /^(\d{1,4}([.,]\d{0,2})?)?$/ }
                    text: dialog.target ? String(Math.round(parseFloat(dialog.target.fat_grams))) : ""
                }
            }
            TextSwitch {
                id: weeklySwitch
                text: qsTr("Vary meals across a whole week instead of repeating one day")
            }
            SectionHeader {
                text: qsTr("Which meals?")
            }
            Repeater {
                model: dialog.slots
                TextSwitch {
                    text: Store.contentName(modelData.name)
                    checked: dialog.chosen.indexOf(modelData.id) >= 0
                    automaticCheck: false
                    onClicked: dialog.toggle(modelData.id)
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
