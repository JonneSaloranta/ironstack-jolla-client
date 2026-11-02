.pragma library
// IronStack's nutrition calculators (apps/nutrition/calculators.py,
// energy.py, macros.py, apps/core/bmi.py) - the same formulas, constants
// and rounding. Every result is an estimate, as the web says too.

function round(value, places) {
    var factor = Math.pow(10, places || 0)
    return Math.round(value * factor) / factor
}

var ACTIVITY_MULTIPLIERS = { sedentary: 1.2, light: 1.375, moderate: 1.55, active: 1.725, very_active: 1.9 }

// Mifflin-St Jeor, whole kcal.
function bmr(weightKg, heightCm, ageYears, sex) {
    var base = 10 * weightKg + 6.25 * heightCm - 5 * ageYears
    return round(sex === "male" ? base + 5 : base - 161)
}

function tdee(bmrValue, activityLevel) {
    return round(bmrValue * ACTIVITY_MULTIPLIERS[activityLevel])
}

var PROTEIN_G_PER_KG = {
    fat_loss_aggressive: 2.2, fat_loss_moderate: 2.2, fat_loss_conservative: 2.2, maintenance: 1.8,
    muscle_gain_lean: 2.0, muscle_gain_moderate: 2.0, muscle_gain_aggressive: 2.0
}
var DEFAULT_RATE_KG_PER_WEEK = {
    fat_loss_conservative: -0.25, fat_loss_moderate: -0.5, fat_loss_aggressive: -0.75, maintenance: 0,
    muscle_gain_lean: 0.125, muscle_gain_moderate: 0.25, muscle_gain_aggressive: 0.5
}

// Protein by g/kg, fat 25 % of calories, carbohydrate the rest; fat and
// then protein are reduced if they'd exceed the calories.
function macros(weightKg, dailyCalories, goalType) {
    var proteinKcal = weightKg * PROTEIN_G_PER_KG[goalType] * 4
    var fatKcal = dailyCalories * 0.25
    var proteinReduced = false
    var fatReduced = false
    if (proteinKcal > dailyCalories) {
        proteinKcal = dailyCalories
        proteinReduced = true
        fatKcal = 0
        fatReduced = true
    } else if (proteinKcal + fatKcal > dailyCalories) {
        fatKcal = dailyCalories - proteinKcal
        fatReduced = true
    }
    var carbKcal = Math.max(dailyCalories - proteinKcal - fatKcal, 0)
    var protein = round(proteinKcal / 4, 2)
    var fat = round(fatKcal / 9, 2)
    var carbs = round(carbKcal / 4, 2)
    function percent(kcal) { return dailyCalories > 0 ? round(kcal / dailyCalories * 100, 1) : 0 }
    return {
        protein: protein, carbohydrate: carbs, fat: fat,
        proteinPercent: percent(protein * 4), carbohydratePercent: percent(carbs * 4), fatPercent: percent(fat * 9),
        proteinReduced: proteinReduced, fatReduced: fatReduced
    }
}

function log10(x) { return Math.log(x) / Math.LN10 }

// U.S. Navy method; NaN for measurements that make no sense.
function bodyFatPercent(sex, heightCm, neckCm, waistCm, hipCm) {
    var value
    if (sex === "male") {
        var diff = waistCm - neckCm
        if (!(diff > 0) || !(heightCm > 0))
            return NaN
        value = 495 / (1.0324 - 0.19077 * log10(diff) + 0.15456 * log10(heightCm)) - 450
    } else {
        if (!(hipCm > 0))
            return NaN
        var diff2 = waistCm + hipCm - neckCm
        if (!(diff2 > 0) || !(heightCm > 0))
            return NaN
        value = 495 / (1.29579 - 0.35004 * log10(diff2) + 0.22100 * log10(heightCm)) - 450
    }
    return value > 0 ? round(value, 1) : NaN
}

var WATER_ACTIVITY_BONUS_ML = { sedentary: 0, light: 250, moderate: 500, active: 750, very_active: 1000 }

function waterLiters(weightKg, activityLevel) {
    return round((weightKg * 33 + WATER_ACTIVITY_BONUS_ML[activityLevel]) / 1000, 1)
}

function waistHipRatio(waistCm, hipCm) {
    return hipCm > 0 ? round(waistCm / hipCm, 2) : NaN
}

// "lower", "moderate" or "higher".
function whrRisk(ratio, sex) {
    var limits = sex === "male" ? [0.90, 1.0] : [0.80, 0.85]
    if (ratio < limits[0])
        return "lower"
    if (ratio < limits[1])
        return "moderate"
    return "higher"
}

// Weeks at `rate` (negative to lose) from current to target; NaN when the
// rate doesn't move toward the target, 0 when already there.
function weeksToGoal(currentKg, targetKg, rateKgPerWeek) {
    var gap = targetKg - currentKg
    if (gap === 0)
        return 0
    if (rateKgPerWeek === 0 || (gap > 0) !== (rateKgPerWeek > 0))
        return NaN
    return round(gap / rateKgPerWeek, 1)
}
