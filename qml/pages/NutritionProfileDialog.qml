import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

// The nutrition profile's inputs, like the web's onboarding steps: body,
// activity and the activity level they suggest. The page that opened it
// saves body().
Dialog {
    id: dialog

    property var profile
    readonly property var sexes: ["male", "female"]
    readonly property var jobs: ["sedentary", "light", "moderate", "physical"]
    readonly property var levels: ["sedentary", "light", "moderate", "active", "very_active"]
    property date birthDate: profile && Store.present(profile.birth_date) ? Store.parseDate(profile.birth_date)
                                                                          : new Date(1990, 0, 1)

    function integer(field) {
        var value = parseInt(field.text, 10)
        return isNaN(value) ? null : value
    }
    function text(value) {
        return Store.present(value) ? String(value) : ""
    }

    function body() {
        return {
            biological_sex: sexes[sexBox.currentIndex],
            birth_date: Store.isoDate(birthDate),
            activity_job: jobs[jobBox.currentIndex],
            daily_steps: integer(stepsField),
            training_sessions_per_week: integer(sessionsField),
            training_session_minutes: integer(minutesField),
            other_exercise_minutes_per_week: integer(otherField),
            activity_level: levels[levelBox.currentIndex],
            self_reported_daily_calories: integer(caloriesField)
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            DialogHeader {
                acceptText: qsTr("Save")
                title: qsTr("Nutrition profile")
            }
            ComboBox {
                id: sexBox
                label: qsTr("Biological sex")
                currentIndex: Math.max(0, dialog.sexes.indexOf(dialog.profile.biological_sex))
                menu: ContextMenu {
                    MenuItem { text: qsTr("Male") }
                    MenuItem { text: qsTr("Female") }
                }
            }
            DatePickerButton {
                label: qsTr("Date of birth")
                date: dialog.birthDate
                onPicked: dialog.birthDate = date
            }
            ComboBox {
                id: jobBox
                label: qsTr("Your job")
                currentIndex: Math.max(0, dialog.jobs.indexOf(dialog.profile.activity_job))
                menu: ContextMenu {
                    MenuItem { text: qsTr("Desk job, mostly sitting") }
                    MenuItem { text: qsTr("On my feet some of the day") }
                    MenuItem { text: qsTr("On my feet most of the day") }
                    MenuItem { text: qsTr("Physically demanding / manual labor") }
                }
            }
            TextField {
                id: stepsField
                width: parent.width
                label: qsTr("Average daily steps (if you know it)")
                placeholderText: label
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 0; top: 100000 }
                text: dialog.text(dialog.profile.daily_steps)
            }
            TextField {
                id: sessionsField
                width: parent.width
                label: qsTr("Gym sessions per week")
                placeholderText: label
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 0; top: 14 }
                text: dialog.text(dialog.profile.training_sessions_per_week)
            }
            TextField {
                id: minutesField
                width: parent.width
                label: qsTr("Typical session length (minutes)")
                placeholderText: label
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 0; top: 600 }
                text: dialog.text(dialog.profile.training_session_minutes)
            }
            TextField {
                id: otherField
                width: parent.width
                label: qsTr("Other exercise (minutes/week)")
                placeholderText: label
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 0; top: 10000 }
                text: dialog.text(dialog.profile.other_exercise_minutes_per_week)
            }
            ComboBox {
                id: levelBox
                label: qsTr("Activity level")
                currentIndex: Math.max(0, dialog.levels.indexOf(dialog.profile.activity_level))
                menu: ContextMenu {
                    MenuItem { text: qsTr("Sedentary") }
                    MenuItem { text: qsTr("Lightly active") }
                    MenuItem { text: qsTr("Moderately active") }
                    MenuItem { text: qsTr("Active") }
                    MenuItem { text: qsTr("Very active") }
                }
            }
            TextField {
                id: caloriesField
                width: parent.width
                label: qsTr("Current daily calories, if you already track this")
                placeholderText: label
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 0; top: 20000 }
                text: dialog.text(dialog.profile.self_reported_daily_calories)
            }
        }

        VerticalScrollDecorator {}
    }
}
