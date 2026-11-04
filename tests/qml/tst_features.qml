import QtQuick 2.0
import QtTest 1.0
import "../../qml/js/features.js" as Features

// What needs a server, and how it shows in standalone mode.
TestCase {
    name: "Features"

    function test_state() {
        var server = { standalone: false, showServerFeatures: true }
        compare(Features.state(server, "social"), "enabled")
        compare(Features.state(server, "body"), "enabled")

        var dimmed = { standalone: true, showServerFeatures: true }
        compare(Features.state(dimmed, "social"), "dimmed")
        compare(Features.state(dimmed, "nutrition"), "dimmed")
        compare(Features.state(dimmed, ""), "enabled")
        compare(Features.state(dimmed, "anything-else"), "enabled")

        var hidden = { standalone: true, showServerFeatures: false }
        compare(Features.state(hidden, "assistant"), "hidden")
        verify(!Features.enabled(hidden, "recently_active"))
    }

    function test_kinds() {
        verify(Features.needsServer("coaching"))
        verify(!Features.needsServer("body"))
        verify(Features.comingLater("body"))
    }
}
