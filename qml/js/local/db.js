.pragma library
.import QtQuick.LocalStorage 2.0 as Sql

// The standalone mode's database (docs/STANDALONE.md): SQLite through
// QtQuick.LocalStorage. Every row keeps its API shape as JSON in `data`;
// the columns next to it are only what's filtered, sorted or added up
// (a set's exercise, weight and reps, a session's status and start...),
// so years of sets are summed by SQLite, not parsed one by one.
//
// Ids: built-in rows (seed.json) keep their ids below FIRST_USER_ID, the
// user's own rows count up from it, per table.

var FIRST_USER_ID = 100001

var db = null
var name = "harbour-ironstack-local"
var clock = function() { return new Date() }

// Every table with its typed columns (besides id and data). Kinds of
// resource without their own hot columns share the generic shape.
var GENERIC = "owner INTEGER, builtin_key TEXT, active INTEGER DEFAULT 1, parent INTEGER, ord INTEGER"
var TABLES = {
    muscle_groups: GENERIC,
    equipment: GENERIC,
    exercises: GENERIC,
    programs: GENERIC,
    workouts: GENERIC,
    prescriptions: GENERIC + ", exercise INTEGER",
    sessions: "workout INTEGER, program INTEGER, status TEXT, started_at TEXT, ended_at TEXT",
    performed_exercises: "session INTEGER, exercise INTEGER, prescription INTEGER, ord INTEGER",
    sets: "performed_exercise INTEGER, session INTEGER, exercise INTEGER, set_number INTEGER, "
          + "weight REAL, reps INTEGER, is_warmup INTEGER, is_failure INTEGER, performed_at TEXT",
    records: "exercise INTEGER, record_type TEXT, rep_count INTEGER, value REAL, set_id INTEGER, "
             + "session INTEGER, achieved_at TEXT"
}

// One function per schema version, run in order on an older database.
var MIGRATIONS = [
    function(tx) {
        tx.executeSql("CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT)")
        for (var table in TABLES)
            tx.executeSql("CREATE TABLE IF NOT EXISTS " + table + "(id INTEGER PRIMARY KEY, "
                          + TABLES[table] + ", data TEXT)")
        tx.executeSql("CREATE INDEX IF NOT EXISTS sets_exercise ON sets(exercise, performed_at)")
        tx.executeSql("CREATE INDEX IF NOT EXISTS sets_pe ON sets(performed_exercise)")
        tx.executeSql("CREATE INDEX IF NOT EXISTS sets_session ON sets(session)")
        tx.executeSql("CREATE INDEX IF NOT EXISTS pe_session ON performed_exercises(session)")
        tx.executeSql("CREATE INDEX IF NOT EXISTS pe_exercise ON performed_exercises(exercise)")
        tx.executeSql("CREATE INDEX IF NOT EXISTS sessions_started ON sessions(started_at)")
        tx.executeSql("CREATE INDEX IF NOT EXISTS records_exercise ON records(exercise)")
        tx.executeSql("CREATE INDEX IF NOT EXISTS workouts_parent ON workouts(parent)")
        tx.executeSql("CREATE INDEX IF NOT EXISTS prescriptions_parent ON prescriptions(parent)")
    }
]

function open(databaseName) {
    if (databaseName)
        name = databaseName
    db = Sql.LocalStorage.openDatabaseSync(name, "", "IronStack on this phone", 50 * 1024 * 1024)
    migrate()
    return db
}

function ensure() {
    if (!db)
        open()
    return db
}

function migrate() {
    db.transaction(function(tx) {
        tx.executeSql("CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT)")
        var rows = tx.executeSql("SELECT value FROM meta WHERE key = 'schema_version'").rows
        var version = rows.length ? parseInt(rows.item(0).value, 10) : 0
        for (var i = version; i < MIGRATIONS.length; i++)
            MIGRATIONS[i](tx)
        tx.executeSql("INSERT OR REPLACE INTO meta(key, value) VALUES('schema_version', ?)",
                      [String(MIGRATIONS.length)])
    })
}

// Empties every table - tests, and "Erase the data on this phone".
function reset() {
    ensure().transaction(function(tx) {
        for (var table in TABLES)
            tx.executeSql("DELETE FROM " + table)
        tx.executeSql("DELETE FROM meta WHERE key != 'schema_version'")
    })
}

function setClock(fn) {
    clock = fn || function() { return new Date() }
}

function now() {
    return clock()
}

function nowIso() {
    return clock().toISOString()
}

// --- plain SQL ---------------------------------------------------------------

function read(sql, args) {
    var rows = []
    ensure().readTransaction(function(tx) {
        var result = tx.executeSql(sql, args || [])
        for (var i = 0; i < result.rows.length; i++)
            rows.push(result.rows.item(i))
    })
    return rows
}

function scalar(sql, args) {
    var rows = read(sql, args)
    if (!rows.length)
        return null
    for (var key in rows[0])
        return rows[0][key]
    return null
}

// Runs fn(tx) in one transaction; what fn returns is returned.
function write(fn) {
    var out
    ensure().transaction(function(tx) { out = fn(tx) })
    return out
}

// --- meta ----------------------------------------------------------------------

function meta(key) {
    return scalar("SELECT value FROM meta WHERE key = ?", [key])
}

function setMeta(key, value, tx) {
    var sql = "INSERT OR REPLACE INTO meta(key, value) VALUES(?, ?)"
    if (tx)
        tx.executeSql(sql, [key, value === null ? null : String(value)])
    else
        write(function(t) { t.executeSql(sql, [key, value === null ? null : String(value)]) })
}

// --- rows as API objects --------------------------------------------------------

function parse(row) {
    return row ? JSON.parse(row.data) : null
}

// Rows of `table` (their API objects), optionally filtered by `where`.
function all(table, where, args, order) {
    return read("SELECT data FROM " + table + (where ? " WHERE " + where : "")
                + (order ? " ORDER BY " + order : " ORDER BY id"), args).map(parse)
}

function get(table, id) {
    if (id === null || id === undefined || isNaN(parseInt(id, 10)))
        return null
    return parse(read("SELECT data FROM " + table + " WHERE id = ?", [parseInt(id, 10)])[0])
}

function nextId(tx, table) {
    var rows = tx.executeSql("SELECT MAX(id) AS id FROM " + table).rows
    var highest = rows.length ? rows.item(0).id : null
    return Math.max(FIRST_USER_ID, (highest || 0) + 1)
}

// Writes `object` (with its id) and its typed `columns` into `table`.
function put(tx, table, object, columns) {
    var names = ["id", "data"]
    var values = [object.id, JSON.stringify(object)]
    for (var column in columns || {}) {
        names.push(column)
        var value = columns[column]
        values.push(value === undefined ? null : typeof value === "boolean" ? (value ? 1 : 0) : value)
    }
    tx.executeSql("INSERT OR REPLACE INTO " + table + "(" + names.join(", ") + ") VALUES("
                  + names.map(function() { return "?" }).join(", ") + ")", values)
    return object
}

function remove(tx, table, id) {
    tx.executeSql("DELETE FROM " + table + " WHERE id = ?", [id])
}
