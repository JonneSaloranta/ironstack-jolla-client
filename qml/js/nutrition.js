.pragma library
// Nutrition maths, the same rules as IronStack's apps/nutrition/services.py:
// a food's values are per its serving_size of serving_unit and scale
// linearly; a recipe is the sum of its ingredients, per serving; a quick
// entry carries its own values per portion. Optional nutrients stay null
// ("unknown") unless something contributes a value.
//
// A diary entry carries its own `nutrition`, snapshotted when it was logged
// (IronStack 1.30), so the diary's figures are the web's; the maths here is
// for what isn't logged yet (a dialog's preview, a diet plan's items).
.import "store.js" as Store

var MAIN = ["calories", "protein_grams", "carbohydrate_grams", "fat_grams"]
var OPTIONAL = ["fiber_grams", "sugar_grams", "saturated_fat_grams", "sodium_mg"]
var FIELDS = MAIN.concat(OPTIONAL)

function zero() {
    var n = {}
    MAIN.forEach(function(f) { n[f] = 0 })
    OPTIONAL.forEach(function(f) { n[f] = null })
    return n
}

function number(value) {
    var n = Store.parseNumber(value)
    return isNaN(n) ? null : n
}

function add(a, b) {
    var n = {}
    MAIN.forEach(function(f) { n[f] = (a[f] || 0) + (b[f] || 0) })
    OPTIONAL.forEach(function(f) {
        n[f] = a[f] === null && b[f] === null ? null : (a[f] || 0) + (b[f] || 0)
    })
    return n
}

function scale(nutrition, factor) {
    var n = {}
    FIELDS.forEach(function(f) { n[f] = nutrition[f] === null ? null : nutrition[f] * factor })
    return n
}

// A food's nutrition for `quantity` of its serving unit.
function forFood(food, quantity) {
    var size = number(food.serving_size)
    var ratio = size ? number(quantity) / size : 0
    var n = {}
    FIELDS.forEach(function(f) {
        var value = number(food[f])
        n[f] = value === null ? (MAIN.indexOf(f) >= 0 ? 0 : null) : value * ratio
    })
    return n
}

// A recipe's total nutrition from its ingredients; `foods` maps id -> food.
function recipeTotal(recipe, foods) {
    return (recipe.ingredients || []).reduce(function(total, ingredient) {
        var food = foods[ingredient.food]
        return food ? add(total, forFood(food, ingredient.quantity)) : total
    }, zero())
}

function recipePerServing(recipe, foods) {
    return scale(recipeTotal(recipe, foods), 1 / (recipe.servings || 1))
}

// Atwater 4/4/9 - a quick entry's calories when only macros were given.
function caloriesFromMacros(protein, carbohydrate, fat) {
    return Math.round(4 * (number(protein) || 0) + 4 * (number(carbohydrate) || 0) + 9 * (number(fat) || 0))
}

function isQuick(entry) {
    return Store.present(entry.quick_calories)
}

// One diary entry's nutrition: the logged values when the entry has them,
// else worked out from the food or recipe. `foods`/`recipes` map id -> row.
function forEntry(entry, foods, recipes) {
    if (entry.nutrition) {
        var logged = {}
        FIELDS.forEach(function(f) { logged[f] = number(entry.nutrition[f]) })
        MAIN.forEach(function(f) { logged[f] = logged[f] || 0 })
        return logged
    }
    var quantity = number(entry.quantity) || 0
    if (Store.present(entry.food))
        return foods[entry.food] ? forFood(foods[entry.food], quantity) : zero()
    if (Store.present(entry.recipe))
        return recipes[entry.recipe] ? scale(recipePerServing(recipes[entry.recipe], foods), quantity) : zero()
    var n = zero()
    n.calories = number(entry.quick_calories) || 0
    n.protein_grams = number(entry.quick_protein_grams) || 0
    n.carbohydrate_grams = number(entry.quick_carbohydrate_grams) || 0
    n.fat_grams = number(entry.quick_fat_grams) || 0
    return scale(n, quantity)
}

function total(entries, foods, recipes) {
    return (entries || []).reduce(function(sum, entry) {
        return add(sum, forEntry(entry, foods, recipes))
    }, zero())
}

// An entry's name: the food, the recipe, or the quick entry's. The entry's
// own food_name/recipe_name first, so a deleted recipe still has its name.
function entryName(entry, foods, recipes, quickFallback) {
    if (entry.food_name)
        return Store.contentName(entry.food_name)
    if (entry.recipe_name)
        return Store.contentName(entry.recipe_name)
    if (Store.present(entry.food)) {
        var food = foods[entry.food]
        return food ? Store.contentName(food.name) : "#" + entry.food
    }
    if (Store.present(entry.recipe)) {
        var recipe = recipes[entry.recipe]
        return recipe ? Store.contentName(recipe.name) : "#" + entry.recipe
    }
    return entry.quick_name || quickFallback
}

// "150 g", "2 servings"-style quantity. `texts` holds the translated
// { servings: "%1 serving(s)", portions: "%1 portion(s)", piece: "pcs" }.
function quantityText(entry, foods, texts) {
    var quantity = Store.formatNumber(number(entry.quantity))
    if (Store.present(entry.food)) {
        var food = foods && foods[entry.food]
        return quantity + (food ? " " + unitText(food.serving_unit, texts.piece) : "")
    }
    return (Store.present(entry.recipe) ? texts.servings : texts.portions).replace("%1", quantity)
}

function unitText(unit, pieceText) {
    return unit === "piece" ? pieceText : unit
}

// The target in effect: the one without an end.
function currentTarget(targets) {
    return (targets || []).filter(function(t) { return !Store.present(t.ended_at) })[0] || null
}

function currentGoal(goals) {
    return (goals || []).filter(function(g) { return !Store.present(g.ended_at) })[0] || null
}

// Today on the cover: { calories, protein, calorieTarget, proteinTarget }
// from nutrition/daily-totals/'s `totals` and the current target (null
// when there's none).
function daySummary(totals, target) {
    return {
        calories: Math.round(number(totals.calories) || 0),
        protein: Math.round(number(totals.protein_grams) || 0),
        calorieTarget: target ? number(target.daily_calories) : null,
        proteinTarget: target ? Math.round(number(target.protein_grams)) : null
    }
}

// A share of a target as a whole percent, or null without a target.
function percentOf(value, target) {
    var t = number(target)
    return t ? Math.round(value / t * 100) : null
}

function round(value) {
    return value === null || value === undefined ? null : Math.round(value)
}

function round1(value) {
    return value === null || value === undefined ? null : Math.round(value * 10) / 10
}

// --- shared data ---------------------------------------------------------------
// Foods, recipes and meal slots, fetched once for every nutrition page;
// `changed` makes the next ensure() fetch them again.

var foods = null      // id -> food
var recipes = null    // id -> recipe
var slots = null      // meal slots, in order
var changed = false
// The diary, or the goal and target, changed somewhere; the nutrition
// overview reloads.
var diaryChanged = false
// Counts diary changes, for the cover to see one since it last looked.
var diaryEdits = 0

function diaryEdited() {
    diaryChanged = true
    diaryEdits++
}

function ensure(api, done) {
    if (foods !== null && !changed)
        return done(true, "")
    var found = { foods: {}, recipes: {}, slots: [] }
    var pending = 3
    var failure = ""
    function settle(ok, error) {
        if (!ok)
            failure = error
        if (--pending > 0)
            return
        if (!failure) {
            foods = found.foods
            recipes = found.recipes
            slots = found.slots.sort(function(a, b) { return a.order - b.order || a.id - b.id })
            changed = false
        }
        done(!failure, failure)
    }
    Store.fetchAll(api, "foods/?page_size=100", function(results) {
        results.forEach(function(f) { found.foods[f.id] = f })
    }, settle)
    Store.fetchAll(api, "recipes/?page_size=100", function(results) {
        results.forEach(function(r) { found.recipes[r.id] = r })
    }, settle)
    Store.fetchAll(api, "meal-slots/?page_size=100", function(results) {
        found.slots = found.slots.concat(results)
    }, settle)
}

function list(map) {
    var result = []
    for (var id in map)
        result.push(map[id])
    return result.sort(function(a, b) { return Store.contentName(a.name).localeCompare(Store.contentName(b.name)) })
}

// A day's diary entries. done(ok, entries, error)
function entriesFor(api, isoDay, done) {
    var found = []
    Store.fetchAll(api, "diary-entries/?page_size=100&date=" + isoDay, function(results) {
        found = found.concat(results)
    }, function(ok, error) {
        done(ok, ok ? found : [], error || "")
    })
}

// Requests one after another; done(ok, error) after the last or the
// first failure.
function sequence(api, requests, done) {
    var at = 0
    function next() {
        if (at === requests.length)
            return done(true, "")
        var r = requests[at++]
        api.request(r.method, r.path, r.body, function(ok, status, data, error) {
            if (!ok)
                return done(false, error)
            next()
        })
    }
    next()
}

// The web's "Copy this day to another date": every entry of `sourceIso`
// added again on `targetIso`. done(ok, copied, error)
function copyDay(api, sourceIso, targetIso, done) {
    api.request("POST", "diary-entries/copy-day/", { source_date: sourceIso, target_date: targetIso },
                function(ok, status, data, error) {
        done(ok, ok && data ? data.copied : 0, error)
    })
}

// The web's "Save as recipe" for one meal: its food entries (recipes and
// quick entries can't be ingredients) as a recipe of one serving named
// "<meal> - <date>". done(ok, recipeId, error); nothing is made without a
// food entry.
function saveMealAsRecipe(api, entries, name, done) {
    var foodEntries = entries.filter(function(e) { return Store.present(e.food) })
    if (foodEntries.length === 0)
        return done(false, null, "")
    api.request("POST", "recipes/", { name: name, servings: 1, instructions: "" }, function(ok, status, recipe, error) {
        if (!ok)
            return done(false, null, error)
        sequence(api, foodEntries.map(function(e, index) {
            return { method: "POST", path: "recipe-ingredients/",
                     body: { recipe: recipe.id, food: e.food, quantity: e.quantity, order: index } }
        }), function(ok2, error2) {
            done(ok2, recipe.id, error2)
        })
    })
}
