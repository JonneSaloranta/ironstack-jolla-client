.pragma library

// What needs an IronStack server, and how it's shown in standalone mode
// (docs/STANDALONE.md): dimmed with a word on what it would do, or - with
// Settings' "Show what needs a server" off - not at all.

// Only with a server, whatever the mode.
var SERVER = ["social", "coaching", "assistant", "guide", "recently_active", "food_search"]
// Not in standalone mode yet; it works with a server.
var LATER = ["body", "nutrition"]

function needsServer(feature) {
    return SERVER.indexOf(feature) >= 0
}

function comingLater(feature) {
    return LATER.indexOf(feature) >= 0
}

// "enabled", "dimmed" or "hidden".
function state(settings, feature) {
    if (!feature || !settings.standalone || (!needsServer(feature) && !comingLater(feature)))
        return "enabled"
    return settings.showServerFeatures ? "dimmed" : "hidden"
}

function enabled(settings, feature) {
    return state(settings, feature) === "enabled"
}
