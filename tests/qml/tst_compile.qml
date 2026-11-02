import QtQuick 2.0
import QtTest 1.0

// Compiles every QML file of the app (without instantiating it), which
// catches syntax errors, unknown types and unknown properties without a
// device or emulator.
TestCase {
    name: "Compile"

    function compile(path) {
        var component = Qt.createComponent(Qt.resolvedUrl("../../qml/" + path))
        if (component.status !== Component.Ready)
            fail(path + ": " + component.errorString())
    }

    function test_main() { compile("harbour-ironstack.qml") }
    function test_cover() { compile("cover/CoverPage.qml") }

    function test_components_data() {
        return [
            { tag: "AchievementItem", path: "components/AchievementItem.qml" },
            { tag: "DatePickerButton", path: "components/DatePickerButton.qml" },
            { tag: "DurationField", path: "components/DurationField.qml" },
            { tag: "ErrorBanner", path: "components/ErrorBanner.qml" },
            { tag: "ExercisePanel", path: "components/ExercisePanel.qml" },
            { tag: "LineChart", path: "components/LineChart.qml" },
            { tag: "RecordItem", path: "components/RecordItem.qml" },
            { tag: "RestTimer", path: "components/RestTimer.qml" },
            { tag: "SessionController", path: "components/SessionController.qml" },
            { tag: "SetItem", path: "components/SetItem.qml" },
            { tag: "StatItem", path: "components/StatItem.qml" },
            { tag: "SuggestionLabel", path: "components/SuggestionLabel.qml" },
            { tag: "Stepper", path: "components/Stepper.qml" },
            { tag: "SyncStatus", path: "components/SyncStatus.qml" }
        ]
    }
    function test_components(data) { compile(data.path) }

    function test_pages_data() {
        return [
            "DashboardPage", "ExerciseEditDialog", "ExercisePage", "ExercisePickerPage", "ExerciseProgressPage", "HistoryPage", "LogSetDialog",
            "LoginPage", "MenuPage", "PrescriptionDialog", "ProgramEditDialog", "ProgramPage", "ProgramsPage", "RecordsPage",
            "SessionPage", "SettingsPage", "TrainingPage", "WorkoutEditDialog", "WorkoutPage"
        ].map(function(name) { return { tag: name, path: "pages/" + name + ".qml" } })
    }
    function test_pages(data) { compile(data.path) }
}
