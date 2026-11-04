.pragma library
.import "db.js" as Db
.import "http.js" as Http

// Exercises, muscle groups and equipment - IronStack's ExerciseViewSet,
// MuscleGroupViewSet and EquipmentViewSet, and last-performance.

var OWNER = 1          // the one local user
var dataUrl = ""       // file:// URL of qml/data, for built-in images

var FIELDS = ["name", "description", "instructions", "primary_muscle_groups", "secondary_muscle_groups",
              "equipment", "movement_type", "weight_input_mode"]

function toApi(row) {
    if (!row)
        return null
    row.is_custom = row.owner !== null && row.owner !== undefined
    row.images = (row.images || []).map(function(image) {
        var out = {}
        for (var key in image)
            out[key] = image[key]
        if (out.image && out.image.indexOf("exercise_images/") === 0)
            out.image = dataUrl + "/" + out.image
        return out
    })
    delete row.builtin_key
    return row
}

function visible(includeInactive) {
    return Db.all("exercises", includeInactive ? "" : "active = 1", [], "id").map(toApi)
}

// The exercise if the user may see it - active, built in or their own.
function find(id, includeInactive) {
    var row = Db.get("exercises", id)
    if (!row || (!includeInactive && row.active === false))
        return null
    return toApi(row)
}

function lookupList(table) {
    return function(match, query) {
        return Http.paginate(Db.all(table, "", [], "id").map(function(row) {
            return { id: row.id, name: row.name }
        }), query, table === "muscle_groups" ? "muscle-groups/" : "equipment/")
    }
}

function list(match, query) {
    var rows = visible(false)
    if (query.ids) {
        var wanted = {}
        query.ids.split(",").forEach(function(id) { wanted[parseInt(id, 10)] = true })
        rows = rows.filter(function(row) { return wanted[row.id] })
    }
    if (query.search) {
        var needle = query.search.toLowerCase()
        rows = rows.filter(function(row) { return row.name.toLowerCase().indexOf(needle) >= 0 })
    }
    rows.sort(function(a, b) { return a.name.localeCompare(b.name) || a.id - b.id })
    return Http.paginate(rows, query, "exercises/")
}

function retrieve(match) {
    var row = find(match[1])
    return row ? Http.ok(row) : Http.notFound()
}

function validate(body, partial) {
    if (!partial || body.name !== undefined) {
        if (!body.name || !String(body.name).trim())
            return Http.invalid("name", qsTranslate("Local", "This field may not be blank."))
    }
    if (body.movement_type !== undefined && body.movement_type !== null && body.movement_type !== ""
            && ["compound", "isolation"].indexOf(body.movement_type) < 0)
        return Http.invalid("movement_type", qsTranslate("Local", "Not a valid choice."))
    if (body.weight_input_mode !== undefined && ["total", "per_hand"].indexOf(body.weight_input_mode) < 0)
        return Http.invalid("weight_input_mode", qsTranslate("Local", "Not a valid choice."))
    return null
}

function apply(row, body) {
    FIELDS.forEach(function(field) {
        if (body[field] !== undefined)
            row[field] = field === "name" ? String(body[field]).trim() : body[field]
    })
    row.primary_muscle_groups = (row.primary_muscle_groups || []).map(Http.int)
    row.secondary_muscle_groups = (row.secondary_muscle_groups || []).map(Http.int)
    row.equipment = Http.int(row.equipment)
}

function create(match, query, body) {
    body = body || {}
    var error = validate(body, false)
    if (error)
        return error
    return Http.created(Db.write(function(tx) {
        var row = { id: Db.nextId(tx, "exercises"), description: "", instructions: "", instructions_attribution: "",
                    images: [], primary_muscle_groups: [], secondary_muscle_groups: [], equipment: null,
                    movement_type: "compound", weight_input_mode: "total", active: true, owner: OWNER }
        apply(row, body)
        Db.put(tx, "exercises", row, { owner: OWNER, active: true })
        return toApi(row)
    }))
}

function update(match, query, body) {
    var row = Db.get("exercises", match[1])
    if (!row || row.active === false)
        return Http.notFound()
    if (row.owner === null || row.owner === undefined)
        return { status: 403, data: { detail: qsTranslate("Local", "Built-in exercises can't be changed.") } }
    body = body || {}
    var error = validate(body, true)
    if (error)
        return error
    apply(row, body)
    Db.write(function(tx) { Db.put(tx, "exercises", row, { owner: OWNER, active: true }) })
    return Http.ok(toApi(row))
}

// Like the web's Deactivate: history keeps referring to it.
function destroy(match) {
    var row = Db.get("exercises", match[1])
    if (!row || row.active === false)
        return Http.notFound()
    if (row.owner === null || row.owner === undefined)
        return { status: 403, data: { detail: qsTranslate("Local", "Built-in exercises can't be changed.") } }
    row.active = false
    Db.write(function(tx) { Db.put(tx, "exercises", row, { owner: OWNER, active: false }) })
    return Http.noContent()
}

function addImage(match, query, body) {
    var row = Db.get("exercises", match[1])
    if (!row || row.active === false)
        return Http.notFound()
    if (row.owner === null || row.owner === undefined)
        return { status: 403, data: { detail: qsTranslate("Local", "Images of built-in exercises can't be changed.") } }
    if (!body || !body.image)
        return Http.invalid("image", qsTranslate("Local", "No file was submitted."))
    var image = Db.write(function(tx) {
        var id = (parseInt(Db.meta("next_image_id"), 10) || Db.FIRST_USER_ID)
        Db.setMeta("next_image_id", id + 1, tx)
        var created = { id: id, image: body.image, caption: body.caption || "", attribution: "",
                        order: Http.int(body.order) || 0 }
        row.images = (row.images || []).concat([created])
        Db.put(tx, "exercises", row, { owner: OWNER, active: true })
        return created
    })
    return Http.created(image)
}

function deleteImage(match) {
    var row = Db.get("exercises", match[1])
    if (!row || row.active === false || row.owner === null || row.owner === undefined)
        return Http.notFound()
    var id = parseInt(match[2], 10)
    var kept = (row.images || []).filter(function(image) { return image.id !== id })
    if (kept.length === (row.images || []).length)
        return Http.notFound()
    row.images = kept
    Db.write(function(tx) { Db.put(tx, "exercises", row, { owner: OWNER, active: true }) })
    return Http.noContent()
}

// apps.workouts.services.last_performance: the exercise's sets in the
// most recent completed session that logged any of it.
function lastPerformance(match) {
    var exercise = find(match[1], true)
    if (!exercise)
        return Http.notFound()
    var rows = Db.read("SELECT pe.id AS pe, s.id AS session, s.started_at AS started_at "
                       + "FROM performed_exercises pe JOIN sessions s ON s.id = pe.session "
                       + "WHERE pe.exercise = ? AND s.status = 'completed' "
                       + "AND EXISTS (SELECT 1 FROM sets WHERE sets.performed_exercise = pe.id) "
                       + "ORDER BY s.started_at DESC, pe.id DESC LIMIT 1", [exercise.id])
    if (!rows.length)
        return Http.ok({ session: null, started_at: null, sets: [] })
    return Http.ok({
        session: rows[0].session,
        started_at: rows[0].started_at,
        sets: Db.all("sets", "performed_exercise = ?", [rows[0].pe], "set_number, id")
    })
}

var routes = [
    ["GET", /^muscle-groups\/$/, lookupList("muscle_groups")],
    ["GET", /^equipment\/$/, lookupList("equipment")],
    ["GET", /^exercises\/$/, list],
    ["POST", /^exercises\/$/, create],
    ["GET", /^exercises\/(\d+)\/$/, retrieve],
    ["PATCH", /^exercises\/(\d+)\/$/, update],
    ["PUT", /^exercises\/(\d+)\/$/, update],
    ["DELETE", /^exercises\/(\d+)\/$/, destroy],
    ["POST", /^exercises\/(\d+)\/images\/$/, addImage],
    ["DELETE", /^exercises\/(\d+)\/images\/(\d+)\/$/, deleteImage],
    ["GET", /^exercises\/(\d+)\/last-performance\/$/, lastPerformance]
]
