.pragma library

// What every handler of the local backend answers with: the server's
// status codes and body shapes (docs/STANDALONE.md).

var PAGE_SIZE = 25      // IronStack's REST_FRAMEWORK PAGE_SIZE
var MAX_PAGE_SIZE = 100 // apps/api/pagination.py

function ok(data) { return { status: 200, data: data } }
function created(data) { return { status: 201, data: data } }
function noContent() { return { status: 204, data: null } }
function notFound() { return { status: 404, data: { detail: "Not found." } } }
function conflict(detail) { return { status: 409, data: { detail: detail } } }

// A DRF validation error: {field: ["message"]}, or {detail} for one
// that isn't about a field.
function invalid(field, message) {
    var data = {}
    data[field || "non_field_errors"] = [message]
    return { status: 400, data: data }
}

// "a=1&b=2" -> {a: "1", b: "2"}
function parseQuery(text) {
    var query = {}
    if (!text)
        return query
    text.split("&").forEach(function(part) {
        if (!part)
            return
        var at = part.indexOf("=")
        var key = decodeURIComponent((at < 0 ? part : part.slice(0, at)).replace(/\+/g, " "))
        query[key] = at < 0 ? "" : decodeURIComponent(part.slice(at + 1).replace(/\+/g, " "))
    })
    return query
}

function buildQuery(query) {
    var parts = []
    for (var key in query)
        parts.push(encodeURIComponent(key) + "=" + encodeURIComponent(query[key]))
    return parts.join("&")
}

// The page `query` asks for, as DRF's PageNumberPagination answers it.
// `next` is a path relative to /api/v1/, which Store.fetchAll follows.
function paginate(items, query, path) {
    return paginateQuery(items.length, function(limit, offset) { return items.slice(offset, offset + limit) },
                         query, path)
}

// paginate() for a list too long to build whole: `count` rows in all,
// `load(limit, offset)` returns one page's items.
function paginateQuery(count, load, query, path) {
    var size = Math.min(parseInt(query.page_size, 10) || PAGE_SIZE, MAX_PAGE_SIZE)
    var page = Math.max(parseInt(query.page, 10) || 1, 1)
    var start = (page - 1) * size
    if (page > 1 && start >= count)
        return notFound()
    var items = load(size, start)
    function link(number) {
        var q = {}
        for (var key in query)
            q[key] = query[key]
        q.page = number
        q.page_size = size
        return path + "?" + buildQuery(q)
    }
    return ok({
        count: count,
        next: start + size < count ? link(page + 1) : null,
        previous: page > 1 ? link(page - 1) : null,
        results: items
    })
}

// A decimal as the API writes it: "82.50", or null.
function dec(value, places) {
    if (value === null || value === undefined || value === "" || isNaN(Number(value)))
        return null
    return Number(value).toFixed(places === undefined ? 2 : places)
}

function num(value) {
    if (value === null || value === undefined || value === "" || isNaN(Number(value)))
        return null
    return Number(value)
}

function int(value) {
    var n = parseInt(value, 10)
    return isNaN(n) ? null : n
}

function bool(value) {
    return value === true || value === 1 || value === "true" || value === "1"
}

// The local calendar day of an ISO datetime, "YYYY-MM-DD".
function localDate(iso) {
    var d = iso instanceof Date ? iso : new Date(iso)
    function pad(n) { return n < 10 ? "0" + n : String(n) }
    return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
}
