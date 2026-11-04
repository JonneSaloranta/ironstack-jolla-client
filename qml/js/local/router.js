.pragma library
.import "db.js" as Db
.import "http.js" as Http
.import "seed.js" as Seed
.import "exercises.js" as Exercises
.import "programs.js" as Programs
.import "sessions.js" as Sessions
.import "records.js" as Records
.import "progression.js" as Progression
.import "analytics.js" as Analytics
.import "profile.js" as Profile

// The standalone mode's backend (docs/STANDALONE.md): ApiClient hands it
// every request the app makes - method, a path under /api/v1/ and the
// body - and gets back {status, data} the way IronStack would answer.

var routes = [].concat(Exercises.routes, Programs.routes, Sessions.routes, Records.routes,
                       Progression.routes, Analytics.routes, Profile.routes)

// Sections still to come to standalone mode: their lists answer empty,
// so the pages that show them alongside training just show nothing.
var LATER = /^(measurement-types|measurements|activity-types|activities|stretches|stretch-routines|stretch-routine-items|stretch-sessions|foods|meal-slots|recipes|recipe-ingredients|diary-entries|nutrition-goals|nutrition-targets|diet-plans|diet-plan-meals|diet-plan-items)\/$/

var ready = false

// Opens the database and brings IronStack's built-in content in.
function init(seedText, dataUrl, databaseName) {
    Db.open(databaseName)
    Seed.apply(seedText)
    Exercises.dataUrl = dataUrl || ""
    ready = true
}

function handle(method, path, body) {
    if (!ready)
        init("", "")
    method = String(method).toUpperCase()
    path = String(path)
    var api = path.indexOf("/api/v1/")
    if (api >= 0)
        path = path.slice(api + 8)
    path = path.replace(/^\/+/, "")
    var at = path.indexOf("?")
    var query = Http.parseQuery(at < 0 ? "" : path.slice(at + 1))
    var bare = at < 0 ? path : path.slice(0, at)
    if (bare && bare.charAt(bare.length - 1) !== "/")
        bare += "/"

    for (var i = 0; i < routes.length; i++) {
        var route = routes[i]
        if (route[0] !== method)
            continue
        var match = route[1].exec(bare)
        if (match)
            return route[2](match, query, body)
    }
    if (method === "GET" && LATER.test(bare))
        return Http.paginate([], query, bare)
    console.warn("Local backend: no " + method + " " + bare)
    return { status: 404, data: { detail: qsTranslate("Local", "Not available without a server.") } }
}

// Everything the user has on this phone as one JSON document - the
// built-in content left out, it comes with the app.
function backup() {
    if (!ready)
        init("", "")
    var tables = {}
    for (var table in Db.TABLES) {
        var generic = Db.TABLES[table].indexOf("builtin_key") >= 0
        tables[table] = Db.all(table, generic ? "owner IS NOT NULL" : "", [], "id")
    }
    return JSON.stringify({
        format: "harbour-ironstack-backup", version: 1, exported_at: Db.nowIso(),
        schema_version: Db.meta("schema_version"), seed_version: Db.meta("seed_version"),
        profile: JSON.parse(Db.meta("profile") || "{}"), tables: tables
    }, null, 1)
}
