.pragma library
.import "db.js" as Db
.import "http.js" as Http
.import "records.js" as Records

// The smart weight suggestion - IronStack's apps/progression/engine.py
// and suggestions.py: the same seven methods, thresholds and wording
// (translated from the web's catalog), weights in kg like the server's.

var FAILURE_STREAK_FOR_DELOAD = 2
var TOP_OF_RANGE_STREAK_FOR_INCREASE = 2
var DELOAD_FACTOR = 0.9

function kg(value) {
    return Number(value).toFixed(2)
}

function round2(value) {
    return Math.round(value * 100) / 100
}

// The last `limit` completed attempts at the exercise, newest first:
// their working sets summarized (engine._summarize).
function recentAttempts(exerciseId, limit) {
    var pes = Db.read("SELECT pe.data FROM performed_exercises pe JOIN sessions s ON s.id = pe.session "
                      + "WHERE pe.exercise = ? AND s.status = 'completed' ORDER BY s.started_at DESC, pe.id DESC LIMIT 20",
                      [exerciseId]).map(Db.parse)
    var attempts = []
    for (var i = 0; i < pes.length && attempts.length < limit; i++) {
        var pe = pes[i]
        var sets = Db.all("sets", "performed_exercise = ? AND is_warmup = 0", [pe.id], "set_number, id")
        if (!sets.length)
            continue
        attempts.push({
            sets: sets,
            weight: Math.max.apply(null, sets.map(function(s) { return Number(s.weight) })),
            anyFailed: sets.some(function(s) { return s.is_failure }),
            allMetMin: pe.min_reps ? sets.every(function(s) { return s.reps >= pe.min_reps }) : true,
            allMetMax: pe.max_reps ? sets.every(function(s) { return s.reps >= pe.max_reps }) : false,
            targetRir: pe.target_rir
        })
    }
    return attempts
}

function failuresAt(attempts, weight) {
    var count = 0
    for (var i = 0; i < attempts.length; i++) {
        if (attempts[i].weight !== weight)
            break
        if (attempts[i].anyFailed || !attempts[i].allMetMin)
            count++
        else
            break
    }
    return count
}

function topOfRangeAt(attempts, weight) {
    var count = 0
    for (var i = 0; i < attempts.length; i++) {
        if (attempts[i].weight !== weight)
            break
        if (attempts[i].allMetMax && !attempts[i].anyFailed)
            count++
        else
            break
    }
    return count
}

function result(action, weight, reason, considered, source) {
    return { action: action, weight: weight === null || weight === undefined ? null : Number(weight),
             reason: reason, considered: considered, source: source || null }
}

function noHistory(p) {
    return result("insufficient_data", p.target_weight,
                  qsTranslate("Progression", "No completed history for this exercise yet - starting at the prescribed target."), 0)
}

function deload(attempts, latest, streak, text) {
    var weight = round2(latest.weight * DELOAD_FACTOR)
    return result("deload", weight, text.arg(streak).arg(kg(latest.weight)).arg(kg(weight)), attempts.length)
}

var methods = {
    manual: function(p) {
        return result("manual", p.target_weight,
                      qsTranslate("Progression", "Manual progression - you control the next weight and target."), 0)
    },
    maintenance: function(p) {
        var attempts = recentAttempts(p.exercise, FAILURE_STREAK_FOR_DELOAD + 1)
        if (!attempts.length)
            return noHistory(p)
        var latest = attempts[0]
        var streak = failuresAt(attempts, latest.weight)
        if (streak >= FAILURE_STREAK_FOR_DELOAD)
            return deload(attempts, latest, streak, qsTranslate("Progression",
                "Missed the target %1 sessions in a row at %2 kg - even maintenance loading should come down, to %3 kg."))
        return result("maintain", latest.weight, qsTranslate("Progression", "Maintenance - keeping the same load."),
                      attempts.length)
    },
    linear: function(p) {
        var attempts = recentAttempts(p.exercise, FAILURE_STREAK_FOR_DELOAD + 1)
        if (!attempts.length)
            return noHistory(p)
        var latest = attempts[0]
        var increment = Number(p.weight_increment) || 0
        if (latest.allMetMin && !latest.anyFailed)
            return result("increase", latest.weight + increment, qsTranslate("Progression",
                "Hit every rep last session at %1 kg - adding %2 kg.").arg(kg(latest.weight)).arg(kg(increment)),
                attempts.length)
        var streak = failuresAt(attempts, latest.weight)
        if (streak >= FAILURE_STREAK_FOR_DELOAD)
            return deload(attempts, latest, streak, qsTranslate("Progression",
                "Missed target reps %1 sessions in a row at %2 kg - recommending a deload to %3 kg."))
        return result("maintain", latest.weight, qsTranslate("Progression",
            "Missed target reps last session at %1 kg - try the same weight again before increasing.").arg(kg(latest.weight)),
            attempts.length)
    },
    double_progression: function(p) {
        var attempts = recentAttempts(p.exercise, FAILURE_STREAK_FOR_DELOAD + 1)
        if (!attempts.length)
            return noHistory(p)
        var latest = attempts[0]
        var increment = Number(p.weight_increment) || 0
        if (latest.allMetMax && !latest.anyFailed)
            return result("increase", latest.weight + increment, qsTranslate("Progression",
                "Hit the top of your rep range on every set at %1 kg - adding %2 kg and resetting to the bottom of the range.")
                .arg(kg(latest.weight)).arg(kg(increment)), attempts.length)
        if (latest.allMetMin && !latest.anyFailed)
            return result("maintain", latest.weight, qsTranslate("Progression",
                "Still within your rep range at %1 kg - repeat the same weight and aim for more reps next time.")
                .arg(kg(latest.weight)), attempts.length)
        return missedBottom(attempts, latest)
    },
    rep_range: function(p) {
        var attempts = recentAttempts(p.exercise, Math.max(TOP_OF_RANGE_STREAK_FOR_INCREASE, FAILURE_STREAK_FOR_DELOAD) + 1)
        if (!attempts.length)
            return noHistory(p)
        var latest = attempts[0]
        var increment = Number(p.weight_increment) || 0
        var top = topOfRangeAt(attempts, latest.weight)
        if (top >= TOP_OF_RANGE_STREAK_FOR_INCREASE)
            return result("increase", latest.weight + increment, qsTranslate("Progression",
                "Hit the top of your rep range for %1 sessions in a row at %2 kg - adding %3 kg.")
                .arg(top).arg(kg(latest.weight)).arg(kg(increment)), attempts.length)
        if (latest.allMetMin && !latest.anyFailed)
            return result("maintain", latest.weight, qsTranslate("Progression",
                "Within your rep range at %1 kg - keep working toward the top of the range before increasing.")
                .arg(kg(latest.weight)), attempts.length)
        return missedBottom(attempts, latest)
    },
    percentage_based: function(p) {
        var percentage = Number(p.percentage_target)
        if (!percentage)
            return result("insufficient_data", p.target_weight,
                          qsTranslate("Progression", "No percentage target configured on this prescription."), 0)
        var oneRm = null, source = null
        var latestPr = Db.read("SELECT value FROM records WHERE exercise = ? AND record_type = 'estimated_1rm' "
                               + "ORDER BY achieved_at DESC LIMIT 1", [p.exercise])
        if (latestPr.length) {
            oneRm = latestPr[0].value
            source = "latest_pr"
        } else {
            var attempts = recentAttempts(p.exercise, 1)
            if (attempts.length) {
                var best = attempts[0].sets.slice().sort(function(a, b) {
                    return Number(b.weight) - Number(a.weight) || b.reps - a.reps
                })[0]
                oneRm = Records.estimate(Number(best.weight), best.reps)
                source = "estimated"
            }
        }
        if (oneRm === null)
            return result("insufficient_data", null, qsTranslate("Progression",
                "No 1RM available yet - log a set first, or enter your 1RM manually."), 0)
        var suggested = round2(oneRm * percentage / 100)
        var sourceText = source === "latest_pr" ? qsTranslate("Progression", "your latest estimated-1RM PR")
                                                : qsTranslate("Progression", "a live estimate from your most recent set")
        return result("calculated", suggested, qsTranslate("Progression", "%1% of %2 kg (%3) = %4 kg.")
                      .arg(kg(percentage)).arg(kg(oneRm)).arg(sourceText).arg(kg(suggested)), 0, source)
    },
    rpe_rir: function(p) {
        var attempts = recentAttempts(p.exercise, FAILURE_STREAK_FOR_DELOAD + 1)
        if (!attempts.length)
            return noHistory(p)
        var latest = attempts[0]
        var target = latest.targetRir
        var actuals = latest.sets.filter(function(s) { return s.rir !== null && s.rir !== undefined })
                                 .map(function(s) { return s.rir })
        if (target === null || target === undefined || !actuals.length)
            return result("insufficient_data", latest.weight, qsTranslate("Progression",
                "No RIR logged against a target yet - log sets with RIR to use this method."), attempts.length)
        var actual = actuals.reduce(function(a, b) { return a + b }, 0) / actuals.length
        var actualText = String(Math.round(actual * 1e6) / 1e6)
        var increment = Number(p.weight_increment) || 0
        if (actual > target)
            return result("increase", latest.weight + increment, qsTranslate("Progression",
                "Target RIR %1, actual %2 - more in reserve than planned, adding %3 kg.")
                .arg(target).arg(actualText).arg(kg(increment)), attempts.length)
        if (actual <= target - 2) {
            var eased = round2(latest.weight * DELOAD_FACTOR)
            return result("decrease", eased, qsTranslate("Progression",
                "Target RIR %1, actual %2 - notably closer to failure than planned, easing back to %3 kg.")
                .arg(target).arg(actualText).arg(kg(eased)), attempts.length)
        }
        return result("maintain", latest.weight, qsTranslate("Progression",
            "Target RIR %1, actual %2 - close enough to plan, hold the weight.").arg(target).arg(actualText),
            attempts.length)
    }
}

function missedBottom(attempts, latest) {
    var streak = failuresAt(attempts, latest.weight)
    if (streak >= FAILURE_STREAK_FOR_DELOAD)
        return deload(attempts, latest, streak, qsTranslate("Progression",
            "Missed the bottom of your rep range %1 sessions in a row at %2 kg - recommending a deload to %3 kg."))
    return result("maintain", latest.weight, qsTranslate("Progression",
        "Missed the bottom of your rep range last session at %1 kg - try the same weight again.").arg(kg(latest.weight)),
        attempts.length)
}

function confidence(r) {
    if (r.action === "insufficient_data" || r.action === "manual")
        return "low"
    if (r.action === "calculated")
        return r.source === "latest_pr" ? "high" : r.source === "estimated" ? "medium" : "low"
    return r.considered >= 2 ? "high" : r.considered === 1 ? "medium" : "low"
}

// performed-exercises/<id>/suggestion/: every field null without a
// prescription behind the exercise, like the server.
function suggestion(match) {
    var pe = Db.get("performed_exercises", match[1])
    if (!pe)
        return Http.notFound()
    var empty = { weight: null, min_reps: null, max_reps: null, method: null, action: null, confidence: null, reason: null }
    var p = pe.prescription ? Db.get("prescriptions", pe.prescription) : null
    if (!p)
        return Http.ok(empty)
    var r = (methods[p.progression_method] || methods.manual)(p)
    return Http.ok({ weight: Http.dec(r.weight), min_reps: p.min_reps, max_reps: p.max_reps,
                     method: p.progression_method, action: r.action, confidence: confidence(r), reason: r.reason })
}

var routes = [
    ["GET", /^performed-exercises\/(\d+)\/suggestion\/$/, suggestion]
]
