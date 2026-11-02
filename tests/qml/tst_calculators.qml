import QtQuick 2.0
import QtTest 1.0
import "../../qml/js/calculators.js" as Calc

TestCase {
    name: "Calculators"

    function test_bmrTdee() {
        // 10*80 + 6.25*180 - 5*30 + 5
        compare(Calc.bmr(80, 180, 30, "male"), 1780)
        compare(Calc.bmr(60, 165, 30, "female"), 1320)
        compare(Calc.tdee(1780, "moderate"), 2759)
    }

    function test_macros() {
        var m = Calc.macros(80, 2500, "maintenance")
        compare(m.protein, 144)
        compare(m.fat, 69.44)
        compare(m.carbohydrate, 324.75)
        verify(!m.fatReduced)
        var low = Calc.macros(150, 1000, "fat_loss_moderate")
        verify(low.proteinReduced)
        compare(low.fat, 0)
        compare(low.carbohydrate, 0)
    }

    function test_bodyFat() {
        compare(Calc.bodyFatPercent("male", 180, 38, 85), 16.1)
        verify(isNaN(Calc.bodyFatPercent("male", 180, 40, 38)))
        verify(isNaN(Calc.bodyFatPercent("female", 165, 32, 70, null)))
    }

    function test_waterWhrWeeks() {
        compare(Calc.waterLiters(80, "moderate"), 3.1)
        compare(Calc.waistHipRatio(85, 100), 0.85)
        compare(Calc.whrRisk(0.85, "male"), "lower")
        compare(Calc.whrRisk(0.85, "female"), "higher")
        compare(Calc.weeksToGoal(90, 80, -0.5), 20)
        compare(Calc.weeksToGoal(80, 80, 0.5), 0)
        verify(isNaN(Calc.weeksToGoal(90, 80, 0.5)))
    }
}
