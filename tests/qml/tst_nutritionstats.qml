import QtQuick 2.0
import QtTest 1.0
import "../../qml/js/store.js" as Store
import "../../qml/js/nutritionstats.js" as Stats
import "../../qml/js/openfoodfacts.js" as Off

TestCase {
    name: "NutritionStats"

    property var today: new Date(2026, 10, 3)

    function day(offset) {
        return Store.isoDate(Store.addDays(today, offset))
    }

    // { "2026-11-02": { calories: ... } } for days -1 ... -count, every
    // `calories(i)`.
    function totals(count, calories) {
        var t = {}
        for (var i = 1; i <= count; i++)
            t[day(-i)] = { calories: calories(i), protein_grams: 100, carbohydrate_grams: 200, fat_grams: 70 }
        return t
    }

    function test_summarize() {
        var s = Stats.summarize([{ calories: 1000 }, { calories: 2000 }, { calories: 2400 }, { calories: 2200 }], 30)
        compare(s.daysLogged, 4)
        compare(s.daysInRange, 30)
        compare(s.meanCalories, 1900)
        compare(s.medianCalories, 2100)
        verify(!s.possibleLoggingGaps)  // fewer than 5 days
        s = Stats.summarize([{ calories: 300 }, { calories: 2000 }, { calories: 2000 }, { calories: 2100 }, { calories: 300 }], 7)
        verify(s.possibleLoggingGaps)
        compare(Stats.summarize([], 7).meanCalories, 0)
    }

    function test_statsLeaveOutToday() {
        var t = totals(3, function() { return 2000 })
        t[day(0)] = { calories: 500 }
        t[day(-4)] = { calories: 0 }  // nothing really logged
        var s = Stats.stats(t, today, 30)
        compare(s.daysLogged, 3)
        compare(s.meanCalories, 2000)
    }

    function test_periods() {
        var t = totals(40, function() { return 2000 })
        var p = Stats.periods(t, today, day(-40))
        compare(p.map(function(x) { return x.key }).join(","), "7d,14d,30d,3m,ytd,1y,all")
        compare(p[0].summary.daysLogged, 7)
        compare(p[0].summary.daysInRange, 7)
        compare(p[2].summary.daysLogged, 30)
        // 3 months back from 2026-11-02: 2026-08-03 ... 2026-11-02
        compare(p[3].summary.daysInRange, 92)
        compare(p[4].summary.daysInRange, 306)  // 2026-01-01 ... 2026-11-02
        compare(p[6].summary.daysInRange, 40)
        compare(p[6].summary.daysLogged, 40)
        compare(Stats.monthsBefore(new Date(2026, 4, 31), 3).getDate(), 28)  // May 31 -> Feb 28
    }

    function test_calorieHistory() {
        var h = Stats.calorieHistory({ "2026-11-02": { calories: 1800.4 } }, today, 30)
        compare(h.length, 30)
        compare(h[29].value, null)  // today, nothing logged
        compare(h[28].value, 1800)
    }

    function weights(rateKgPerWeek, everyDays, spanDays) {
        var r = []
        for (var i = spanDays; i >= 1; i -= everyDays)
            r.push({ recorded_at: new Date(today.getTime() - i * 86400000).toISOString(),
                     value: String(80 - rateKgPerWeek * i / 7) })
        return r
    }

    function test_trend() {
        compare(Stats.computeTrend([{ day: "2026-10-01", kg: 80 }, { day: "2026-10-20", kg: 79 }]), null)
        var readings = Stats.weightReadings(weights(-0.5, 1, 28), null)
        var trend = Stats.computeTrend(readings)
        compare(trend.spanDays, 27)
        compare(trend.distinctDays, 28)
        // the 7-day moving average lags at the end; same figure as
        // IronStack's trends.compute_trend for these readings
        compare(trend.rate, -0.444)
        compare(Stats.trendConfidence(trend), "high")
    }

    function test_maintenance() {
        var t = totals(20, function() { return 2500 })
        var m = Stats.estimateMaintenance(t, weights(-0.5, 2, 28), today)
        compare(m.reason, "ok")
        // trend -0.442 kg/week: 2500 + 0.442 / 7 * 7700 = 2986 -> 3000, as on the server
        compare(m.trend.rate, -0.442)
        compare(m.calories, 3000)
        compare(m.confidence, "medium")
        compare(Stats.estimateMaintenance(totals(10, function() { return 2500 }), [], today).reason, "food")
        compare(Stats.estimateMaintenance(t, [], today).reason, "weight")
        compare(Stats.estimateMaintenance(totals(20, function() { return 300 }), weights(0, 2, 28), today).reason,
                "implausible")
    }

    function test_suggestion() {
        var now = new Date(today.getTime())
        var goal = { target_rate_kg_per_week: "-0.50" }
        var target = { daily_calories: 2200, source: "calculated", started_at: "2026-01-01T00:00:00Z" }
        compare(Stats.suggestAdjustment(null, target, [], now).action, "no_active_goal")
        compare(Stats.suggestAdjustment(goal, target, [], now).action, "insufficient_data")
        compare(Stats.suggestAdjustment(goal, target, weights(-0.45, 1, 27), now).action, "on_track")
        var s = Stats.suggestAdjustment(goal, target, weights(0, 1, 27), now)
        compare(s.action, "adjust")
        // -0.5 kg/week * 7700 / 7 = -550, capped at -250
        compare(s.delta, -250)
        compare(s.suggestedCalories, 1950)
        // an accepted adjustment: nothing from before it counts
        var adjusted = { daily_calories: 1950, source: "adjusted",
                         started_at: new Date(today.getTime() - 5 * 86400000).toISOString() }
        compare(Stats.suggestAdjustment(goal, adjusted, weights(0, 1, 27), now).action, "insufficient_data")
        compare(Stats.roundHalfUp(-12.5), -13)
        compare(Stats.roundHalfUp(2.675, 2), 2.68)
        // the stats round like Decimal.quantize: half to even
        compare(Stats.roundHalfEven(2260.5), 2260)
        compare(Stats.roundHalfEven(2261.5), 2262)
        compare(Stats.roundHalfEven(2261.4), 2261)
        compare(Stats.summarize([{ calories: 2000 }, { calories: 2521 }], 7).medianCalories, 2260)
    }

    function test_openFoodFacts() {
        verify(Off.isBarcode(" 6408430000258 "))
        verify(!Off.isBarcode("milk 1.5"))
        var product = { code: "6408430000258", product_name: "Kevytmaito", brands: "Valio,Arla",
                        product_quantity_unit: "ml",
                        nutriments: { "energy-kj_100g": 192, proteins_100g: 3.5, carbohydrates_100g: 4.9,
                                      fat_100g: 1.5, sodium_100g: 0.04, salt_100g: 0.1, sugars_100g: 4.888 } }
        var body = Off.foodBody(product)
        compare(body.name, "Kevytmaito")
        compare(body.brand, "Valio")
        compare(body.serving_unit, "ml")
        compare(body.serving_size, "100")
        compare(body.calories, 46)  // from kJ
        compare(body.sodium_mg, 40)
        compare(body.sugar_grams, "4.89")
        compare(body.fiber_grams, null)
        compare(body.salt_grams, "0.1")
        compare(Off.foodBody({ code: "1", product_name: "x", nutriments: { proteins_100g: 1 } }), null)
        compare(Off.productsFrom({ status: 0 }).length, 0)
        compare(Off.productsFrom({ status: 1, product: product }).length, 1)
        compare(Off.productsFrom({ hits: [product, product] }).length, 2)
        var foods = { 1: { id: 1, name: "Kevytmaito", brand: "Valio", calories: 46, serving_unit: "ml",
                           serving_size: "100.00", owner: 3, active: true } }
        compare(Off.existingFood(foods, product, body).id, 1)
        compare(Off.existingFood({ 2: { id: 2, off_id: "6408430000258", active: true } }, product, body).id, 2)
        compare(Off.existingFood({}, product, body), null)
        verify(Off.searchUrl("maito rasvaton", "fi").indexOf("q=maito%20rasvaton") > 0)
    }
}
