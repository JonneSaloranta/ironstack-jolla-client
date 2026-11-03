import QtQuick 2.0
import QtTest 1.0
import "../../qml/js/nutrition.js" as Nutrition

TestCase {
    name: "Nutrition"

    property var bread: ({ id: 5, name: "Bread", serving_size: "100.00", serving_unit: "g", calories: 214,
                           protein_grams: "11.54", carbohydrate_grams: "50.00", fat_grams: "1.92",
                           fiber_grams: "7.69", sugar_grams: null, saturated_fat_grams: null, sodium_mg: 538 })
    property var egg: ({ id: 6, name: "Egg", serving_size: "1.00", serving_unit: "piece", calories: 70,
                         protein_grams: "6.00", carbohydrate_grams: "0.50", fat_grams: "5.00",
                         fiber_grams: null, sugar_grams: null, saturated_fat_grams: null, sodium_mg: null })
    property var foods: ({ 5: bread, 6: egg })
    property var recipe: ({ id: 9, name: "Toast & eggs", servings: 2,
                            ingredients: [{ food: 5, quantity: "100" }, { food: 6, quantity: "2" }] })

    function test_forFood() {
        var n = Nutrition.forFood(bread, 50)
        compare(n.calories, 107)
        compare(n.protein_grams, 5.77)
        compare(n.fiber_grams, 3.845)
        // unknown stays unknown
        compare(n.sugar_grams, null)
    }

    function test_recipe() {
        var total = Nutrition.recipeTotal(recipe, foods)
        compare(total.calories, 214 + 140)
        // the egg's unknown fiber doesn't erase the bread's
        compare(total.fiber_grams, 7.69)
        compare(Nutrition.recipePerServing(recipe, foods).calories, 177)
    }

    function test_entries() {
        var recipes = { 9: recipe }
        var entries = [
            { food: 6, recipe: null, quantity: "3.00" },
            { food: null, recipe: 9, quantity: "1.00" },
            { food: null, recipe: null, quantity: "2.00", quick_name: "Pizza", quick_calories: 500,
              quick_protein_grams: "20.00", quick_carbohydrate_grams: null, quick_fat_grams: "10.00" }
        ]
        compare(Nutrition.forEntry(entries[0], foods, recipes).calories, 210)
        compare(Nutrition.forEntry(entries[1], foods, recipes).calories, 177)
        var quick = Nutrition.forEntry(entries[2], foods, recipes)
        compare(quick.calories, 1000)
        compare(quick.protein_grams, 40)
        compare(quick.carbohydrate_grams, 0)
        compare(Nutrition.total(entries, foods, recipes).calories, 1387)
        compare(Nutrition.entryName(entries[2], foods, recipes, "Quick entry"), "Pizza")
        compare(Nutrition.quantityText(entries[0], foods, { servings: "%1 s", portions: "%1 p", piece: "pcs" }), "3 pcs")
        compare(Nutrition.quantityText(entries[1], foods, { servings: "%1 s", portions: "%1 p", piece: "pcs" }), "1 s")
    }

    // A logged entry's own nutrition wins over today's food values, and its
    // name over the library's (a deleted recipe still has one).
    function test_loggedEntry() {
        var entry = { food: null, recipe: 56, recipe_name: "Breakfast - 2026-11-03", quantity: "1.00",
                      nutrition: { calories: "53.00", protein_grams: "10.86", carbohydrate_grams: "0.00",
                                   fat_grams: "1.01", fiber_grams: "0.00", sugar_grams: null,
                                   saturated_fat_grams: "0.00", sodium_mg: "0.00" } }
        var n = Nutrition.forEntry(entry, foods, {})
        compare(n.calories, 53)
        compare(n.protein_grams, 10.86)
        compare(n.sugar_grams, null)
        compare(Nutrition.entryName(entry, foods, {}, "Quick entry"), "Breakfast - 2026-11-03")
        var edited = { food: 6, food_name: "Egg", quantity: "1.00", nutrition: { calories: "80.00", protein_grams: "7.00",
                       carbohydrate_grams: "0.00", fat_grams: "5.00" } }
        compare(Nutrition.total([entry, edited], foods, {}).calories, 133)
        // a food no longer in the library: no unit
        compare(Nutrition.quantityText({ food: 99, quantity: "2.00" }, foods, { piece: "pcs" }), "2")
    }

    function test_fromTotals() {
        var n = Nutrition.fromTotals({ calories: "2300.00", protein_grams: "120.50", carbohydrate_grams: "210.00",
                                       fat_grams: "75.00", fiber_grams: "8.20", sugar_grams: null,
                                       saturated_fat_grams: null, sodium_mg: null })
        compare(n.calories, 2300)
        compare(n.protein_grams, 120.5)
        compare(n.fiber_grams, 8.2)
        compare(n.sugar_grams, null)
        compare(Nutrition.fromTotals(null).calories, 0)
    }

    function test_statsSummary() {
        var s = Nutrition.statsSummary({ days_logged: 20, days_in_range: 30, mean_calories: "2263",
                                         median_calories: "2260", median_protein_grams: "120.0",
                                         median_carbohydrate_grams: "210.5", median_fat_grams: "75.0",
                                         possible_logging_gaps: true })
        compare(s.daysLogged, 20)
        compare(s.daysInRange, 30)
        compare(s.meanCalories, 2263)
        compare(s.medianCarbohydrate, 210.5)
        compare(s.possibleLoggingGaps, true)
        s = Nutrition.statsSummary(null)
        compare(s.daysLogged, 0)
        compare(s.meanCalories, 0)
        compare(s.possibleLoggingGaps, false)
    }

    function test_daySummary() {
        var totals = { calories: "387.40", protein_grams: "30.60", carbohydrate_grams: "25.00", fat_grams: "12.00" }
        var target = { daily_calories: 2200, protein_grams: "160.00", ended_at: null }
        var day = Nutrition.daySummary(totals, target)
        compare(day.calories, 387)
        compare(day.protein, 31)
        compare(day.calorieTarget, 2200)
        compare(day.proteinTarget, 160)

        var empty = Nutrition.daySummary({ calories: "0.00" }, null)
        compare(empty.calories, 0)
        compare(empty.protein, 0)
        compare(empty.calorieTarget, null)
        compare(empty.proteinTarget, null)
    }

    function test_caloriesFromMacros() {
        compare(Nutrition.caloriesFromMacros("20", "30", "10"), 290)
        compare(Nutrition.caloriesFromMacros(null, "", "1"), 9)
    }

    function test_current() {
        compare(Nutrition.currentTarget([{ id: 1, ended_at: "2026-10-01" }, { id: 2, ended_at: null }]).id, 2)
        compare(Nutrition.currentTarget([]), null)
        compare(Nutrition.percentOf(1500, 2000), 75)
        compare(Nutrition.percentOf(1500, null), null)
    }

    function fakeApi() {
        var api = { calls: [], nextId: 100 }
        api.request = function(method, path, body, callback) {
            api.calls.push({ method: method, path: path, body: body })
            callback(true, 201, { id: api.nextId++ }, "")
        }
        return api
    }

    function test_copyDay() {
        var api = { calls: [] }
        api.request = function(method, path, body, callback) {
            api.calls.push({ method: method, path: path, body: body })
            callback(true, 201, { copied: 3 }, "")
        }
        var result = null
        Nutrition.copyDay(api, "2026-11-01", "2026-11-02", function(ok, copied) { result = { ok: ok, copied: copied } })
        verify(result.ok)
        compare(result.copied, 3)
        compare(api.calls.length, 1)
        compare(api.calls[0].path, "diary-entries/copy-day/")
        compare(api.calls[0].body.source_date, "2026-11-01")
        compare(api.calls[0].body.target_date, "2026-11-02")
    }

    function test_entriesFor() {
        var api = { paths: [] }
        api.request = function(method, path, body, callback) {
            api.paths.push(path)
            callback(true, 200, { results: [{ id: 1, date: "2026-11-02" }], next: null }, "")
        }
        var result = null
        Nutrition.entriesFor(api, "2026-11-02", function(ok, entries) { result = entries })
        compare(result.length, 1)
        verify(api.paths[0].indexOf("date=2026-11-02") >= 0)
    }

    function test_saveMealAsRecipe() {
        var api = fakeApi()
        var result = null
        var entries = [{ food: 5, recipe: null, quantity: "100.00" }, { food: null, recipe: 9, quantity: "1" },
                       { food: 6, recipe: null, quantity: "2.00" }]
        Nutrition.saveMealAsRecipe(api, entries, "Breakfast - 2026-11-02", function(ok, id) { result = { ok: ok, id: id } })
        verify(result.ok)
        compare(result.id, 100)
        compare(api.calls[0].body.servings, 1)
        // the recipe entry is skipped
        compare(api.calls.length, 3)
        compare(api.calls[2].body.food, 6)
        Nutrition.saveMealAsRecipe(api, [{ food: null, recipe: 9 }], "x", function(ok, id) { result = { ok: ok, id: id } })
        verify(!result.ok)
    }
}
