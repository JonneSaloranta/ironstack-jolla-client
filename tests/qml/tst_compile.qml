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
            { tag: "BarChart", path: "components/BarChart.qml" },
            { tag: "CoachLinks", path: "components/CoachLinks.qml" },
            { tag: "CooldownCard", path: "components/CooldownCard.qml" },
            { tag: "DatePickerButton", path: "components/DatePickerButton.qml" },
            { tag: "DurationField", path: "components/DurationField.qml" },
            { tag: "ErrorBanner", path: "components/ErrorBanner.qml" },
            { tag: "ExercisePanel", path: "components/ExercisePanel.qml" },
            { tag: "LineChart", path: "components/LineChart.qml" },
            { tag: "MacroSummary", path: "components/MacroSummary.qml" },
            { tag: "RecordItem", path: "components/RecordItem.qml" },
            { tag: "RestTimer", path: "components/RestTimer.qml" },
            { tag: "SessionController", path: "components/SessionController.qml" },
            { tag: "SetItem", path: "components/SetItem.qml" },
            { tag: "StatItem", path: "components/StatItem.qml" },
            { tag: "SuggestionLabel", path: "components/SuggestionLabel.qml" },
            { tag: "Stepper", path: "components/Stepper.qml" },
            { tag: "SyncStatus", path: "components/SyncStatus.qml" },
            { tag: "SyncWatcher", path: "components/SyncWatcher.qml" }
        ]
    }
    function test_components(data) { compile(data.path) }

    function test_pages_data() {
        return [
            "ActivitiesPage", "ActivityDialog", "ActivityHistoryPage", "AssistantChatPage", "AssistantPage", "AssistantSettingsPage", "BarcodeScannerPage", "BlockedUsersPage", "ChatPage", "ClientPage", "ClientsDialog", "CoachUpdateDialog", "CoachingPage", "CalculatorsPage", "DashboardPage", "DiaryEntryDialog", "DiaryPage", "DietPlanDialog", "DietPlanPage", "DietPlansPage", "ExerciseEditDialog", "ExercisePage", "ExercisePickerPage", "ExerciseProgressPage", "FoodEditDialog", "FoodPage", "FoodsPage", "FriendPickerDialog", "GuidePage", "GroupEditDialog", "GroupPage", "HistoryPage", "LogSetDialog",
            "LoginPage", "MeasurementDialog", "MeasurementHistoryPage", "MeasurementTypeDialog", "MeasurementsPage", "MenuPage", "NameDialog", "NutritionGoalDialog", "NutritionGoalsPage", "NutritionPage", "NutritionProfileDialog", "NutritionStatsPage", "OpenFoodFactsPage", "PrescriptionDialog", "ProgramEditDialog", "ProgramPage", "ProgramsPage", "ProgressPage", "QuantityDialog", "RecipeEditDialog", "RecipePage", "RecipesPage", "RecordsPage", "RoutineEditDialog", "RoutineItemDialog",
            "SessionPage", "SettingsPage", "ShoppingListPage", "SocialPage", "StretchEditDialog", "StretchPage", "StretchPlayerPage", "StretchRoutinePage", "StretchSessionDialog", "StretchSessionsPage", "StretchesPage", "StretchingPage", "TourPage", "TrainingPage", "UserSearchPage", "WorkoutEditDialog", "WorkoutPage"
        ].map(function(name) { return { tag: name, path: "pages/" + name + ".qml" } })
    }
    function test_pages(data) { compile(data.path) }
}
