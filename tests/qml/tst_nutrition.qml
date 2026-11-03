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

    // A built-in or deleted recipe is hidden from recipes/; its entries stay.
    function test_isKnown() {
        var recipes = { 9: recipe }
        verify(Nutrition.isKnown({ food: 5, recipe: null }, foods, recipes))
        verify(Nutrition.isKnown({ food: null, recipe: 9 }, foods, recipes))
        verify(Nutrition.isKnown({ food: null, recipe: null, quick_name: "Pizza" }, foods, recipes))
        verify(!Nutrition.isKnown({ food: null, recipe: 56 }, foods, recipes))
        verify(!Nutrition.isKnown({ food: 99, recipe: null }, foods, recipes))
        verify(!Nutrition.isKnown({ food: null, recipe: 9 }, foods, null))
    }

    function test_daySummary() {
        var recipes = { 9: recipe }
        var entries = [
            { food: 6, recipe: null, quantity: "3.00" },    // 210 kcal, 18 g protein
            { food: null, recipe: 9, quantity: "1.00" },    // 177 kcal
            { food: null, recipe: 56, quantity: "1.00" }    // can't be read
        ]
        var target = { daily_calories: 2200, protein_grams: "160.00", ended_at: null }
        var day = Nutrition.daySummary(entries, foods, recipes, target)
        compare(day.calories, 387)
        compare(day.protein, Math.round(18 + Nutrition.recipePerServing(recipe, foods).protein_grams))
        compare(day.calorieTarget, 2200)
        compare(day.proteinTarget, 160)
        compare(day.unknown, 1)

        var empty = Nutrition.daySummary([], foods, recipes, null)
        compare(empty.calories, 0)
        compare(empty.calorieTarget, null)
        compare(empty.proteinTarget, null)
        compare(empty.unknown, 0)
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
        var api = fakeApi()
        var result = null
        Nutrition.copyDay(api, [{ id: 1, date: "2026-11-01", meal_slot: 2, food: 5, recipe: null, quantity: "50.00",
                                  notes: "", quick_name: "", quick_calories: null }], "2026-11-02",
                          function(ok) { result = ok })
        verify(result)
        compare(api.calls[0].body.date, "2026-11-02")
        compare(api.calls[0].body.food, 5)
        compare(api.calls[0].body.id, undefined)
        // no "recipe": null (IronStack #39)
        verify(!api.calls[0].body.hasOwnProperty("recipe"))
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
