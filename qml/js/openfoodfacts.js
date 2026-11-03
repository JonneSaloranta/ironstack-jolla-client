.pragma library
// Open Food Facts search and barcode lookup, done by the app itself: the
// IronStack API has no import (COMPATIBILITY.md), so a product is turned
// into a plain food of your own with POST foods/ - the same values the
// web's import stores (apps/nutrition/openfoodfacts.py parse_product),
// per 100 g or 100 ml. Nutri-Score, NOVA group and the OFF id are
// read-only in the API and can't be kept.

var SEARCH_URL = "https://search.openfoodfacts.org/search"
var PRODUCT_URL = "https://world.openfoodfacts.org/api/v2/product/"
var FIELDS = "code,product_name,generic_name,brands,nutriments,product_quantity_unit,nutriscore_grade,nova_group"
var PAGE_SIZE = 20

// An EAN/UPC barcode rather than words.
function isBarcode(text) {
    return /^\d{8,14}$/.test(String(text).trim())
}

function searchUrl(query, language) {
    return SEARCH_URL + "?q=" + encodeURIComponent(String(query).trim()) + "&page_size=" + PAGE_SIZE
            + "&langs=" + encodeURIComponent(language || "en") + "&fields=" + FIELDS
}

function productUrl(barcode) {
    return PRODUCT_URL + String(barcode).trim() + ".json?fields=" + FIELDS
}

// A search response's products, or a barcode lookup's one (none when OFF
// doesn't know the barcode).
function productsFrom(data) {
    if (!data)
        return []
    if (data.hits)
        return data.hits
    return data.status === 1 && data.product ? [data.product] : []
}

function text(value) {
    if (value instanceof Array)
        return value.join(",")
    return value || ""
}

function firstBrand(brands) {
    if (brands instanceof Array)
        return brands.length ? String(brands[0]).trim() : ""
    return String(brands || "").split(",")[0].trim()
}

function present(value) {
    return value !== null && value !== undefined && value !== "" && !isNaN(parseFloat(value))
}

// A decimal for the API: not negative, at most `places` decimals.
function decimal(value, places) {
    var factor = Math.pow(10, places)
    return String(Math.round(Math.max(0, parseFloat(value)) * factor) / factor)
}

function optional(nutriments, key, places) {
    return present(nutriments[key]) ? decimal(nutriments[key], places) : null
}

// A product as the body of POST foods/, or null when it has no barcode,
// name or core macros (a food of misleading zeros isn't worth making).
function foodBody(product) {
    var n = product.nutriments || {}
    var calories = n["energy-kcal_100g"]
    if (!present(calories) && present(n["energy-kj_100g"]))
        calories = parseFloat(n["energy-kj_100g"]) / 4.184
    var name = product.product_name || product.generic_name
    if (!product.code || !name || !present(calories) || !present(n.proteins_100g)
            || !present(n.carbohydrates_100g) || !present(n.fat_100g))
        return null
    return {
        name: String(name).substring(0, 200),
        brand: firstBrand(product.brands).substring(0, 200),
        serving_size: "100",
        serving_unit: product.product_quantity_unit === "ml" ? "ml" : "g",
        calories: Math.max(0, Math.round(parseFloat(calories))),
        protein_grams: decimal(n.proteins_100g, 2),
        carbohydrate_grams: decimal(n.carbohydrates_100g, 2),
        fat_grams: decimal(n.fat_100g, 2),
        fiber_grams: optional(n, "fiber_100g", 2),
        sugar_grams: optional(n, "sugars_100g", 2),
        saturated_fat_grams: optional(n, "saturated-fat_100g", 2),
        sodium_mg: present(n.sodium_100g) ? Math.max(0, Math.round(parseFloat(n.sodium_100g) * 1000)) : null,
        energy_kj: optional(n, "energy-kj_100g", 2),
        starch_grams: optional(n, "starch_100g", 2),
        polyols_grams: optional(n, "polyols_100g", 2),
        salt_grams: optional(n, "salt_100g", 3)
    }
}

// A food already in the library from this product: one the server
// imported (same OFF id), or one of your own with the same name, brand
// and calories (an earlier import from the app).
function existingFood(foods, product, body) {
    for (var id in foods) {
        var food = foods[id]
        if (!food.active)
            continue
        if (food.off_id && food.off_id === product.code)
            return food
        if (body && food.owner !== null && food.owner !== undefined && food.name === body.name
                && (food.brand || "") === body.brand && food.calories === body.calories
                && food.serving_unit === body.serving_unit && parseFloat(food.serving_size) === 100)
            return food
    }
    return null
}
