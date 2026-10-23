import QtQuick 2.0
import QtTest 1.0

// Compiles every QML file of the app (without instantiating it), which
// catches syntax errors, unknown types and unknown properties without a
// device or emulator.
TestCase {
    name: "Compile"

    function compile(path) {
        var component = Qt.createComponent(Qt.resolvedUrl("../qml/" + path))
        if (component.status !== Component.Ready)
            fail(path + ": " + component.errorString())
    }

    function test_main() { compile("harbour-ironstack.qml") }
    function test_cover() { compile("cover/CoverPage.qml") }

    function test_components_data() {
        return [
            { tag: "ErrorBanner", path: "components/ErrorBanner.qml" },
            { tag: "RecordItem", path: "components/RecordItem.qml" },
            { tag: "StatItem", path: "components/StatItem.qml" }
        ]
    }
    function test_components(data) { compile(data.path) }

    function test_pages_data() {
        return [
            "DashboardPage", "ExercisePickerPage", "HistoryPage", "LogSetDialog",
            "LoginPage", "ProgramPage", "ProgramsPage", "RecordsPage",
            "SessionPage", "WorkoutPage"
        ].map(function(name) { return { tag: name, path: "pages/" + name + ".qml" } })
    }
    function test_pages(data) { compile(data.path) }
}
