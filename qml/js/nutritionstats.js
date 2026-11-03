.pragma library
// The web's nutrition statistics and observed maintenance (IronStack
// apps/nutrition/services.py nutrition_stats*, trends.py, maintenance.py),
// worked out here from diary entries and body weight readings - the API
// has neither. Pure functions except the two fetch helpers at the end.
.import "store.js" as Store
.import "nutrition.js" as Nutrition

var STATS_WINDOW_DAYS = 30
var LOGGING_GAP_MEAN_BELOW_MEDIAN = 0.10
var LOGGING_GAP_MIN_DAYS = 5
var KCAL_PER_KG_BODY_FAT = 7700

// Decimal's ROUND_HALF_UP: halves away from zero.
function roundHalfUp(value, places) {
    var factor = Math.pow(10, places || 0)
    var scaled = Math.abs(value) * factor
    // 1e-9: 2.675 * 100 is 267.49999999999997 in binary floating point.
    return (value < 0 ? -1 : 1) * Math.floor(scaled + 0.5 + 1e-9) / factor
}

// Decimal.quantize's default ROUND_HALF_EVEN, which the server's stats
// use: 2260.5 -> 2260, 2261.5 -> 2262.
function roundHalfEven(value, places) {
    var factor = Math.pow(10, places || 0)
    var scaled = value * factor
    var floor = Math.floor(scaled)
    var diff = scaled - floor
    var result = diff > 0.5 + 1e-9 ? floor + 1 : diff < 0.5 - 1e-9 ? floor : (floor % 2 === 0 ? floor : floor + 1)
    return result / factor
}

// Each day's total nutrition: { "2026-11-02": nutrition }, only days with
// an entry.
function dailyTotals(entries, foods, recipes) {
    var totals = {}
    ;(entries || []).forEach(function(entry) {
        var n = Nutrition.forEntry(entry, foods, recipes)
        totals[entry.date] = totals[entry.date] ? Nutrition.add(totals[entry.date], n) : n
    })
    return totals
}

// Days in [startIso, endIso] with something logged; a day with nothing
// isn't counted as zero calories (_logged_days).
function loggedDays(totals, startIso, endIso) {
    var days = []
    for (var day in totals) {
        if (day >= startIso && day <= endIso && totals[day].calories > 0)
            days.push(totals[day])
    }
    return days
}

function median(values) {
    var sorted = values.slice().sort(function(a, b) { return a - b })
    var mid = Math.floor(sorted.length / 2)
    return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
}

// The stats page's figures for one period (_summarize): days logged of
// days in range, mean and median calories, median macros, and whether
// the mean is low enough against the median to suggest partly logged
// days.
function summarize(logged, daysInRange) {
    var summary = { daysLogged: logged.length, daysInRange: daysInRange, meanCalories: 0, medianCalories: 0,
                    medianProtein: 0, medianCarbohydrate: 0, medianFat: 0, possibleLoggingGaps: false }
    if (logged.length === 0)
        return summary
    function pick(field) { return logged.map(function(n) { return n[field] || 0 }) }
    var calories = pick("calories")
    summary.meanCalories = roundHalfEven(calories.reduce(function(a, b) { return a + b }, 0) / logged.length)
    summary.medianCalories = roundHalfEven(median(calories))
    summary.medianProtein = roundHalfEven(median(pick("protein_grams")), 1)
    summary.medianCarbohydrate = roundHalfEven(median(pick("carbohydrate_grams")), 1)
    summary.medianFat = roundHalfEven(median(pick("fat_grams")), 1)
    summary.possibleLoggingGaps = logged.length >= LOGGING_GAP_MIN_DAYS
            && summary.meanCalories < summary.medianCalories * (1 - LOGGING_GAP_MEAN_BELOW_MEDIAN)
    return summary
}

function daysBetween(a, b) {
    return Math.round((b - a) / 86400000)
}

// The last `days` finished days, today left out (nutrition_stats).
function stats(totals, today, days) {
    var end = Store.addDays(today, -1)
    var start = Store.addDays(end, -(days - 1))
    return summarize(loggedDays(totals, Store.isoDate(start), Store.isoDate(end)), days)
}

// The same day-of-month `months` earlier, clamped to that month's length.
function monthsBefore(date, months) {
    var index = date.getFullYear() * 12 + date.getMonth() - months
    var year = Math.floor(index / 12)
    var month = index % 12
    var length = new Date(year, month + 1, 0).getDate()
    return new Date(year, month, Math.min(date.getDate(), length))
}

// The stats page's fixed periods (nutrition_stats_by_period), all ending
// yesterday: [{ key, summary }] for 7d, 14d, 30d, 3m, ytd, 1y, all.
// `firstIso` is the first diary day (null without any).
function periods(totals, today, firstIso) {
    var end = Store.addDays(today, -1)
    var allStart = firstIso && Store.parseDate(firstIso) < today ? Store.parseDate(firstIso) : Store.addDays(today, 0)
    var starts = [
        ["7d", Store.addDays(end, -6)],
        ["14d", Store.addDays(end, -13)],
        ["30d", Store.addDays(end, -29)],
        ["3m", Store.addDays(monthsBefore(end, 3), 1)],
        ["ytd", new Date(today.getFullYear(), 0, 1)],
        ["1y", Store.addDays(monthsBefore(end, 12), 1)],
        ["all", allStart]
    ]
    return starts.map(function(s) {
        return { key: s[0], summary: summarize(loggedDays(totals, Store.isoDate(s[1]), Store.isoDate(end)),
                                               Math.max(daysBetween(s[1], end) + 1, 0)) }
    })
}

// The last `days` days, today included, one point per day; a day with
// nothing logged is null, not zero (calorie_history).
// [{ x: <ms>, value: kcal or null }]
function calorieHistory(totals, today, days) {
    var result = []
    for (var i = days - 1; i >= 0; i--) {
        var day = Store.addDays(today, -i)
        var n = totals[Store.isoDate(day)]
        result.push({ x: day.getTime(), value: n ? Math.round(n.calories) : null })
    }
    return result
}

// --- weight trend (trends.py) ------------------------------------------------

var MOVING_AVERAGE_WINDOW_DAYS = 7
var MIN_SPAN_DAYS = 14
var MIN_DISTINCT_DAYS = 4

// readings: [{ day: "2026-11-02", kg }] -> { day: average of that day }.
function bucketByDay(readings) {
    var sums = {}
    readings.forEach(function(r) {
        var b = sums[r.day] = sums[r.day] || { total: 0, count: 0 }
        b.total += r.kg
        b.count++
    })
    var days = {}
    for (var day in sums)
        days[day] = sums[day].total / sums[day].count
    return days
}

// The weight change per week from a 7-day moving average over the
// readings, or null below 4 weigh-in days or a 14-day span.
// { rate (kg/week, 3 decimals), spanDays, distinctDays }
function computeTrend(readings) {
    var byDay = bucketByDay(readings || [])
    var days = Object.keys(byDay).sort()
    if (days.length < MIN_DISTINCT_DAYS)
        return null
    var spanDays = daysBetween(Store.parseDate(days[0]), Store.parseDate(days[days.length - 1]))
    if (spanDays < MIN_SPAN_DAYS)
        return null
    function trendAt(day) {
        var windowStart = Store.isoDate(Store.addDays(Store.parseDate(day), -(MOVING_AVERAGE_WINDOW_DAYS - 1)))
        var values = days.filter(function(d) { return d >= windowStart && d <= day })
                         .map(function(d) { return byDay[d] })
        return values.reduce(function(a, b) { return a + b }, 0) / values.length
    }
    var rate = (trendAt(days[days.length - 1]) - trendAt(days[0])) / (spanDays / 7)
    return { rate: roundHalfUp(rate, 3), spanDays: spanDays, distinctDays: days.length }
}

// Body weight readings as the trend wants them, `since` (a Date) on.
function weightReadings(readings, since) {
    return (readings || []).filter(function(r) {
        return !since || new Date(r.recorded_at) >= since
    }).map(function(r) {
        return { day: Store.isoDate(new Date(r.recorded_at)), kg: Store.parseNumber(r.value) }
    })
}

function trendConfidence(trend) {
    if (trend.distinctDays >= 10 && trend.spanDays >= 21)
        return "high"
    if (trend.distinctDays >= 6 && trend.spanDays >= 14)
        return "medium"
    return "low"
}

// --- observed maintenance (maintenance.py) -------------------------------------

var MAINTENANCE_WINDOW_DAYS = 28
var MAINTENANCE_MIN_FOOD_DAYS = 14
var MAINTENANCE_ROUNDING_KCAL = 50
var PLAUSIBLE_KCAL = [1000, 6000]

// What the user really burns, from the last 28 finished days' food and
// weight. Information only - never changes a target.
// { calories, confidence, reason, stats, trend } - `calories` null when
// there isn't enough data; `reason` is "food", "weight", "implausible" or
// "ok" for the page to word.
function estimateMaintenance(totals, bodyWeightReadings, today) {
    var foodStats = stats(totals, today, MAINTENANCE_WINDOW_DAYS)
    var result = { calories: null, confidence: null, reason: "", stats: foodStats, trend: null }
    if (foodStats.daysLogged < MAINTENANCE_MIN_FOOD_DAYS) {
        result.reason = "food"
        return result
    }
    var end = Store.isoDate(Store.addDays(today, -1))
    var since = Store.addDays(today, -MAINTENANCE_WINDOW_DAYS)
    var trend = computeTrend(weightReadings(bodyWeightReadings, since).filter(function(r) { return r.day <= end }))
    result.trend = trend
    if (trend === null) {
        result.reason = "weight"
        return result
    }
    var raw = foodStats.meanCalories - trend.rate / 7 * KCAL_PER_KG_BODY_FAT
    var calories = roundHalfUp(raw / MAINTENANCE_ROUNDING_KCAL) * MAINTENANCE_ROUNDING_KCAL
    if (calories < PLAUSIBLE_KCAL[0] || calories > PLAUSIBLE_KCAL[1]) {
        result.reason = "implausible"
        return result
    }
    result.calories = calories
    result.reason = "ok"
    if (foodStats.possibleLoggingGaps)
        result.confidence = "low"
    else if (foodStats.daysLogged >= 24 && trend.distinctDays >= 10)
        result.confidence = "high"
    else if (foodStats.daysLogged >= 18 && trend.distinctDays >= 6)
        result.confidence = "medium"
    else
        result.confidence = "low"
    return result
}

// --- fetching ------------------------------------------------------------------

// Diary entries from `startIso` on (all of them with null).
// done(ok, entries, error)
function entriesSince(api, startIso, done) {
    var found = []
    Store.fetchAll(api, "diary-entries/?page_size=100" + (startIso ? "&date_after=" + startIso : ""), function(results) {
        found = found.concat(results)
    }, function(ok, error) {
        done(ok, ok ? found : [], error || "")
    })
}

// Body weight readings (the built-in type) recorded from `since` (a Date)
// on. done(ok, readings, error) - no body weight type means no readings.
function bodyWeightSince(api, since, done) {
    api.request("GET", "measurement-types/?page_size=100", null, function(ok, status, data, error) {
        if (!ok)
            return done(false, [], error)
        var type = (data.results || []).filter(Store.isBodyWeightType)[0]
        if (!type)
            return done(true, [], "")
        var found = []
        Store.fetchAll(api, "measurements/?page_size=100&measurement_type=" + type.id
                       + "&recorded_after=" + encodeURIComponent(since.toISOString()), function(results) {
            found = found.concat(results)
        }, function(ok2, error2) {
            done(ok2, ok2 ? found : [], error2 || "")
        })
    })
}
