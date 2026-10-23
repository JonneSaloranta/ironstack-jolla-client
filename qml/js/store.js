.pragma library

// Shared, app-wide state and formatting helpers. A .pragma library script
// is one instance for every page that imports it, so the exercise-name
// cache survives page pushes/pops.

var LB_PER_KG = 2.20462262

var exerciseNames = ({})

function exerciseName(id) {
    return exerciseNames[id] || ("#" + id)
}

function rememberExercises(list) {
    for (var i = 0; i < list.length; i++)
        exerciseNames[list[i].id] = list[i].name
}

// Fetch the names of any exercise ids not yet cached, then call done().
// The API returns only ids on prescriptions/records (see IronStack issue
// #19), so this is one GET per unknown exercise.
function ensureExercises(api, ids, done) {
    var missing = []
    for (var i = 0; i < ids.length; i++) {
        if (ids[i] && exerciseNames[ids[i]] === undefined && missing.indexOf(ids[i]) < 0)
            missing.push(ids[i])
    }
    if (missing.length === 0) {
        done()
        return
    }
    var remaining = missing.length
    missing.forEach(function(id) {
        api.request("GET", "exercises/" + id + "/", null, function(ok, status, data) {
            if (ok)
                exerciseNames[data.id] = data.name
            remaining--
            if (remaining === 0)
                done()
        })
    })
}

// Follow a paginated list endpoint to the end. onPage(results) is called
// per page; done(ok, error) once at the end.
function fetchAll(api, path, onPage, done) {
    api.request("GET", path, null, function(ok, status, data, error) {
        if (!ok) {
            done(false, error)
            return
        }
        onPage(data.results || [])
        if (data.next)
            fetchAll(api, data.next, onPage, done)
        else
            done(true, "")
    })
}

// --- units --------------------------------------------------------------
// The API is always kilograms (docs/API.md "Canonical units, always");
// conversion is purely a display concern.

function isImperial(unitSystem) {
    return unitSystem === "imperial"
}

function weightUnit(unitSystem) {
    return isImperial(unitSystem) ? "lb" : "kg"
}

function kgToDisplay(kg, unitSystem) {
    var value = parseFloat(kg)
    if (isNaN(value))
        return NaN
    return isImperial(unitSystem) ? value * LB_PER_KG : value
}

function displayToKg(value, unitSystem) {
    var number = parseFloat(String(value).replace(",", "."))
    if (isNaN(number))
        return NaN
    var kg = isImperial(unitSystem) ? number / LB_PER_KG : number
    return Math.round(kg * 100) / 100
}

function formatNumber(value) {
    if (isNaN(value))
        return "-"
    var rounded = Math.round(value * 100) / 100
    return String(rounded)
}

function formatWeight(kg, unitSystem) {
    if (kg === null || kg === undefined || kg === "")
        return "-"
    return formatNumber(kgToDisplay(kg, unitSystem)) + " " + weightUnit(unitSystem)
}

// --- time -----------------------------------------------------------------

function formatDate(iso) {
    if (!iso)
        return "-"
    return Qt.formatDate(new Date(iso), Qt.DefaultLocaleShortDate)
}

function formatDateTime(iso) {
    if (!iso)
        return "-"
    return Qt.formatDateTime(new Date(iso), Qt.DefaultLocaleShortDate)
}

function formatDuration(seconds) {
    seconds = Math.max(0, Math.floor(seconds))
    var h = Math.floor(seconds / 3600)
    var m = Math.floor((seconds % 3600) / 60)
    var s = seconds % 60
    function pad(n) { return n < 10 ? "0" + n : String(n) }
    return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : m + ":" + pad(s)
}

function elapsedSince(iso) {
    if (!iso)
        return 0
    return (Date.now() - new Date(iso).getTime()) / 1000
}

function formatHoursMinutes(seconds) {
    seconds = Math.max(0, Math.floor(seconds))
    var h = Math.floor(seconds / 3600)
    var m = Math.floor((seconds % 3600) / 60)
    return h + ":" + (m < 10 ? "0" + m : m)
}
