import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/store.js" as Store
import "../js/calculators.js" as Calc

// The web's nutrition calculators: BMR and TDEE, macros, body fat (U.S.
// Navy method), water, BMI, waist-to-hip ratio and time to goal. Inputs
// in your units; nothing is saved. Every result is an estimate.
Page {
    id: page

    readonly property string unitSystem: settings.unitSystem
    readonly property bool imperial: Store.isImperial(unitSystem)
    property int calculator: 0
    readonly property var calculators: [qsTr("BMR and TDEE"), qsTr("Macros"), qsTr("Body fat"), qsTr("Water intake"),
                                        qsTr("BMI"), qsTr("Waist-to-hip ratio"), qsTr("Time to goal")]
    readonly property var sexes: ["male", "female"]
    readonly property var levels: ["sedentary", "light", "moderate", "active", "very_active"]
    readonly property var goals: ["fat_loss_aggressive", "fat_loss_moderate", "fat_loss_conservative", "maintenance",
                                  "muscle_gain_lean", "muscle_gain_moderate", "muscle_gain_aggressive"]

    function num(field) {
        var value = Store.parseNumber(field.text)
        return isNaN(value) ? NaN : value
    }
    // Weight in kg and lengths in cm, whatever the unit setting.
    function kg(field) {
        return imperial ? num(field) / Store.LB_PER_KG : num(field)
    }
    function cm(field) {
        return imperial ? num(field) * 2.54 : num(field)
    }

    readonly property string weightLabel: imperial ? "lb" : "kg"
    readonly property string lengthLabel: imperial ? "in" : "cm"

    function result() {
        var sex = sexes[sexBox.currentIndex]
        var level = levels[levelBox.currentIndex]
        var goal = goals[goalBox.currentIndex]
        switch (calculator) {
        case 0: {
            var b = Calc.bmr(kg(weightField), cm(heightField), num(ageField), sex)
            if (isNaN(b))
                return ""
            return qsTr("BMR %1 kcal").arg(b) + "\n" + qsTr("TDEE %1 kcal/day").arg(Calc.tdee(b, level))
        }
        case 1: {
            var m = Calc.macros(kg(weightField), num(caloriesField), goal)
            if (isNaN(m.protein) || !(num(caloriesField) > 0))
                return ""
            return qsTr("Protein") + " " + m.protein + " g (" + m.proteinPercent + " %)\n"
                    + qsTr("Carbohydrates") + " " + m.carbohydrate + " g (" + m.carbohydratePercent + " %)\n"
                    + qsTr("Fat") + " " + m.fat + " g (" + m.fatPercent + " %)"
        }
        case 2: {
            var bf = Calc.bodyFatPercent(sex, cm(heightField), cm(neckField), cm(waistField), cm(hipField))
            return isNaN(bf) ? (num(waistField) > 0 ? qsTr("Check your measurements.") : "") : bf + " %"
        }
        case 3: {
            var w = Calc.waterLiters(kg(weightField), level)
            return isNaN(w) ? "" : qsTr("%1 litres a day").arg(w)
        }
        case 4: {
            var bmi = Store.bmi(kg(weightField), cm(heightField) / 100)
            return isNaN(bmi) ? "" : Store.formatNumber(bmi)
        }
        case 5: {
            var r = Calc.waistHipRatio(cm(waistField), cm(hipField))
            if (isNaN(r))
                return ""
            var risk = Calc.whrRisk(r, sex)
            return r + " - " + (risk === "lower" ? qsTr("Lower risk") : risk === "moderate" ? qsTr("Moderate risk")
                                                                                           : qsTr("Higher risk"))
        }
        case 6: {
            var rate = Calc.DEFAULT_RATE_KG_PER_WEEK[goal]
            var weeks = Calc.weeksToGoal(kg(weightField), kg(targetField), rate)
            if (isNaN(kg(targetField)))
                return ""
            if (isNaN(weeks))
                return qsTr("This goal doesn't move toward the target weight.")
            var date = Store.addDays(new Date(), Math.round(weeks * 7))
            return qsTr("%1 weeks").arg(weeks) + " - " + Format.formatDate(date, Formatter.DateMedium)
        }
        }
        return ""
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            PageHeader {
                title: qsTr("Calculators")
            }
            ComboBox {
                label: qsTr("Calculator")
                currentIndex: page.calculator
                menu: ContextMenu {
                    Repeater {
                        model: page.calculators
                        MenuItem {
                            text: modelData
                            onClicked: page.calculator = index
                        }
                    }
                }
            }

            ComboBox {
                id: sexBox
                visible: [0, 2, 5].indexOf(page.calculator) >= 0
                label: qsTr("Biological sex")
                menu: ContextMenu {
                    MenuItem { text: qsTr("Male") }
                    MenuItem { text: qsTr("Female") }
                }
            }
            TextField {
                id: weightField
                visible: [0, 1, 3, 4, 6].indexOf(page.calculator) >= 0
                width: parent.width
                label: page.calculator === 6 ? qsTr("Current weight (%1)").arg(page.weightLabel)
                                             : qsTr("Weight (%1)").arg(page.weightLabel)
                placeholderText: label
                inputMethodHints: Qt.ImhFormattedNumbersOnly
            }
            TextField {
                id: targetField
                visible: page.calculator === 6
                width: parent.width
                label: qsTr("Target weight (%1)").arg(page.weightLabel)
                placeholderText: label
                inputMethodHints: Qt.ImhFormattedNumbersOnly
            }
            TextField {
                id: heightField
                visible: [0, 2, 4].indexOf(page.calculator) >= 0
                width: parent.width
                label: qsTr("Height (%1)").arg(page.lengthLabel)
                placeholderText: label
                inputMethodHints: Qt.ImhFormattedNumbersOnly
            }
            TextField {
                id: ageField
                visible: page.calculator === 0
                width: parent.width
                label: qsTr("Age (years)")
                placeholderText: label
                inputMethodHints: Qt.ImhDigitsOnly
            }
            TextField {
                id: caloriesField
                visible: page.calculator === 1
                width: parent.width
                label: qsTr("Daily calories")
                placeholderText: label
                inputMethodHints: Qt.ImhDigitsOnly
            }
            TextField {
                id: neckField
                visible: page.calculator === 2
                width: parent.width
                label: qsTr("Neck (%1)").arg(page.lengthLabel)
                placeholderText: label
                inputMethodHints: Qt.ImhFormattedNumbersOnly
            }
            TextField {
                id: waistField
                visible: page.calculator === 2 || page.calculator === 5
                width: parent.width
                label: qsTr("Waist (%1)").arg(page.lengthLabel)
                placeholderText: label
                inputMethodHints: Qt.ImhFormattedNumbersOnly
            }
            TextField {
                id: hipField
                visible: page.calculator === 5 || (page.calculator === 2 && sexBox.currentIndex === 1)
                width: parent.width
                label: qsTr("Hip (%1)").arg(page.lengthLabel)
                placeholderText: label
                inputMethodHints: Qt.ImhFormattedNumbersOnly
            }
            ComboBox {
                id: levelBox
                visible: page.calculator === 0 || page.calculator === 3
                label: qsTr("Activity level")
                currentIndex: 2
                menu: ContextMenu {
                    MenuItem { text: qsTr("Sedentary") }
                    MenuItem { text: qsTr("Lightly active") }
                    MenuItem { text: qsTr("Moderately active") }
                    MenuItem { text: qsTr("Active") }
                    MenuItem { text: qsTr("Very active") }
                }
            }
            ComboBox {
                id: goalBox
                visible: page.calculator === 1 || page.calculator === 6
                label: qsTr("Goal")
                currentIndex: 3
                menu: ContextMenu {
                    MenuItem { text: qsTr("Fat loss - aggressive") }
                    MenuItem { text: qsTr("Fat loss - moderate") }
                    MenuItem { text: qsTr("Fat loss - conservative") }
                    MenuItem { text: qsTr("Maintenance") }
                    MenuItem { text: qsTr("Muscle gain - lean bulk") }
                    MenuItem { text: qsTr("Muscle gain - moderate bulk") }
                    MenuItem { text: qsTr("Muscle gain - aggressive bulk") }
                }
            }

            SectionHeader {
                text: qsTr("Result")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeLarge
                color: Theme.highlightColor
                // Re-read whenever an input changes.
                text: {
                    weightField.text; targetField.text; heightField.text; ageField.text; caloriesField.text
                    neckField.text; waistField.text; hipField.text
                    sexBox.currentIndex; levelBox.currentIndex; goalBox.currentIndex; page.calculator
                    return page.result() || "-"
                }
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                topPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: qsTr("An estimate, not medical advice.")
            }
        }

        VerticalScrollDecorator {}
    }
}
