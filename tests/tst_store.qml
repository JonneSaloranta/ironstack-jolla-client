import QtQuick 2.0
import QtTest 1.0
import "../qml/js/store.js" as Store

TestCase {
    name: "Store"

    function test_weightUnit() {
        compare(Store.weightUnit("metric"), "kg")
        compare(Store.weightUnit("imperial"), "lb")
    }

    function test_kgToDisplay() {
        compare(Store.kgToDisplay("82.50", "metric"), 82.5)
        fuzzyCompare(Store.kgToDisplay("100", "imperial"), 220.462, 0.001)
        verify(isNaN(Store.kgToDisplay("", "metric")))
    }

    function test_displayToKg() {
        compare(Store.displayToKg("82,5", "metric"), 82.5)
        compare(Store.displayToKg("82.5", "metric"), 82.5)
        // 225 lb = 102.058 kg, rounded to the API's two decimals
        compare(Store.displayToKg("225", "imperial"), 102.06)
        verify(isNaN(Store.displayToKg("abc", "metric")))
    }

    function test_roundTripImperial() {
        // A weight logged in lb must come back as the same lb figure.
        var kg = Store.displayToKg("185", "imperial")
        compare(Store.formatNumber(Math.round(Store.kgToDisplay(kg, "imperial"))), "185")
    }

    function test_formatWeight() {
        compare(Store.formatWeight("80.00", "metric"), "80 kg")
        compare(Store.formatWeight("82.50", "metric"), "82.5 kg")
        compare(Store.formatWeight(null, "metric"), "-")
        compare(Store.formatWeight("", "metric"), "-")
    }

    function test_formatDuration() {
        compare(Store.formatDuration(0), "0:00")
        compare(Store.formatDuration(65), "1:05")
        compare(Store.formatDuration(3725), "1:02:05")
        compare(Store.formatDuration(-5), "0:00")
    }

    function test_formatHoursMinutes() {
        compare(Store.formatHoursMinutes(0), "0:00")
        compare(Store.formatHoursMinutes(3900), "1:05")
    }

    function test_exerciseNameCache() {
        compare(Store.exerciseName(987654), "#987654")
        Store.rememberExercises([{ id: 987654, name: "Squat" }])
        compare(Store.exerciseName(987654), "Squat")
    }
}
