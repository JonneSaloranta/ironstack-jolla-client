.pragma library
.import "db.js" as Db
.import "http.js" as Http

// profile/ for the one person using this phone: the server profile's
// fields the app reads, kept in meta. No username or email - there's no
// account until the data is transferred to a server.

var EDITABLE = ["unit_system", "timezone", "height", "show_bmi", "show_achievements", "language",
                "body_tracking_reminders_enabled", "tutorials_enabled"]

function defaults() {
    return {
        username: "", email: "", date_joined: Db.nowIso(), unit_system: "metric", timezone: "", height: null,
        show_bmi: true, show_achievements: true, allow_friend_requests: false, allow_group_invites: false,
        language: "", theme: "default", appearance: "dark", body_tracking_reminders_enabled: true,
        needs_body_tracking_reminder: false, tutorials_enabled: false
    }
}

function load() {
    var stored = Db.meta("profile")
    var profile = defaults()
    if (stored) {
        var saved = JSON.parse(stored)
        for (var key in saved)
            profile[key] = saved[key]
    } else {
        Db.setMeta("profile", JSON.stringify(profile))
    }
    return profile
}

function get() {
    return Http.ok(load())
}

function update(match, query, body) {
    var profile = load()
    body = body || {}
    if (body.unit_system !== undefined && ["metric", "imperial"].indexOf(body.unit_system) < 0)
        return Http.invalid("unit_system", qsTranslate("Local", "Not a valid choice."))
    if (body.height !== undefined && body.height !== null && body.height !== "" && !(Number(body.height) > 0))
        return Http.invalid("height", qsTranslate("Local", "A valid number is required."))
    EDITABLE.forEach(function(field) {
        if (body[field] === undefined)
            return
        profile[field] = field === "height" ? Http.dec(body[field]) : body[field]
    })
    Db.setMeta("profile", JSON.stringify(profile))
    return Http.ok(profile)
}

var routes = [
    ["GET", /^profile\/$/, get],
    ["PATCH", /^profile\/$/, update],
    ["PUT", /^profile\/$/, update]
]
