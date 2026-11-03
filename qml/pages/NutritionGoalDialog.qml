import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

// A new nutrition goal, like the web's goal page: the goal, its rate per
// week (filled in from the goal, as on the web) and an optional target
// weight. IronStack ends the current goal and target and calculates a new
// target. The page that opened it saves body().
Dialog {
    id: dialog

    // The current goal, to start from; null for none.
    property var goal: null

    readonly property string unitSystem: settings.unitSystem
    // apps.nutrition.energy.GoalType, in the web's order, and
    // DEFAULT_RATE_KG_PER_WEEK.
    readonly property var types: ["fat_loss_aggressive", "fat_loss_moderate", "fat_loss_conservative", "maintenance",
                                  "muscle_gain_lean", "muscle_gain_moderate", "muscle_gain_aggressive"]
    readonly property var defaultRates: [-0.75, -0.5, -0.25, 0, 0.125, 0.25, 0.5]
    readonly property string goalType: types[typeBox.currentIndex]
    readonly property real rateKg: rateToKg(rateField.text)

    function rateText(kg) {
        return String(Math.round(Store.kgToDisplay(kg, unitSystem) * 1000) / 1000)
    }

    function rateToKg(text) {
        var value = Store.parseNumber(text)
        if (isNaN(value))
            return NaN
        return Math.round((Store.isImperial(unitSystem) ? value / Store.LB_PER_KG : value) * 1000) / 1000
    }

    // goal_rate_error: the rate's sign has to agree with the goal.
    readonly property string rateError: {
        if (isNaN(rateKg))
            return ""
        if (goalType.indexOf("fat_loss") === 0 && rateKg >= 0)
            return qsTr("A fat-loss goal needs a negative rate - you're asking to lose weight.")
        if (goalType.indexOf("muscle_gain") === 0 && rateKg <= 0)
            return qsTr("A muscle-gain goal needs a positive rate - you're asking to gain weight.")
        if (goalType === "maintenance" && rateKg !== 0)
            return qsTr("A maintenance goal's rate should be 0 per week.")
        return ""
    }

    canAccept: !isNaN(rateKg) && rateError === ""

    function body() {
        var weight = Store.displayToKg(weightField.text, unitSystem)
        return {
            goal_type: goalType,
            target_rate_kg_per_week: rateKg.toFixed(3),
            target_weight: isNaN(weight) ? null : weight.toFixed(2),
            notes: notesField.text
        }
    }

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
        return type
    }

    Component.onCompleted: {
        var index = goal ? types.indexOf(goal.goal_type) : -1
        typeBox.currentIndex = index >= 0 ? index : types.indexOf("maintenance")
        rateField.text = goal && Store.present(goal.target_rate_kg_per_week)
                ? rateText(goal.target_rate_kg_per_week) : rateText(defaultRates[typeBox.currentIndex])
        if (goal && Store.present(goal.target_weight))
            weightField.text = Store.formatNumber(Store.kgToDisplay(goal.target_weight, unitSystem))
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            DialogHeader {
                acceptText: qsTr("Save")
                title: qsTr("New goal")
            }
            ComboBox {
                id: typeBox
                label: qsTr("Goal")
                menu: ContextMenu {
                    Repeater {
                        model: dialog.types
                        MenuItem {
                            text: dialog.goalText(modelData)
                            onClicked: rateField.text = dialog.rateText(dialog.defaultRates[index])
                        }
                    }
                }
            }
            TextField {
                id: rateField
                width: parent.width
                label: qsTr("Rate (%1/week)").arg(Store.weightUnit(dialog.unitSystem))
                placeholderText: label
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                description: dialog.rateError
                             || qsTr("Negative to lose weight, positive to gain. Capped at a safe rate for your "
                                     + "bodyweight.")
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: weightField.focus = true
            }
            TextField {
                id: weightField
                width: parent.width
                label: qsTr("Target weight (%1, optional)").arg(Store.weightUnit(dialog.unitSystem))
                placeholderText: label
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: notesField.focus = true
            }
            TextField {
                id: notesField
                width: parent.width
                label: qsTr("Notes")
                placeholderText: label
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("The current goal and target are kept in the history. The new daily target is "
                           + "calculated from your nutrition profile, height and latest body weight.")
            }
        }
    }
}
