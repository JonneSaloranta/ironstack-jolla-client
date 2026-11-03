import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store
import "../js/nutrition.js" as Nutrition

// One food, like the web's: the nutrition label per serving, Nutri-Score
// and NOVA group when known. Your own foods can be edited or removed.
Page {
    id: page

    property int foodId
    readonly property var food: Nutrition.foods ? Nutrition.foods[foodId] || null : null
    property string errorText: ""

    readonly property bool editable: food !== null && Store.present(food.owner)

    function value(field, unit, places) {
        if (!food || !Store.present(food[field]))
            return ""
        var n = parseFloat(food[field])
        return (places === 0 ? Math.round(n) : Math.round(n * 100) / 100) + " " + unit
    }

    function novaText(group) {
        switch (group) {
        case 1: return qsTr("1 - Unprocessed or minimally processed")
        case 2: return qsTr("2 - Processed culinary ingredients")
        case 3: return qsTr("3 - Processed foods")
        case 4: return qsTr("4 - Ultra-processed foods")
        }
        return ""
    }

    RemorsePopup {
        id: remorse
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            visible: page.editable
            MenuItem {
                text: qsTr("Delete")
                onClicked: remorse.execute(qsTr("Deleting food"), function() {
                    api.request("DELETE", "foods/" + page.foodId + "/", null, function(ok, status, data, error) {
                        if (!ok) {
                            page.errorText = error
                            return
                        }
                        Nutrition.changed = true
                        pageStack.pop()
                    })
                })
            }
            MenuItem {
                text: qsTr("Edit")
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("FoodEditDialog.qml"), { food: page.food })
                    dialog.accepted.connect(function() {
                        api.request("PATCH", "foods/" + page.foodId + "/", dialog.body(), function(ok, status, data, error) {
                            if (!ok) {
                                page.errorText = error
                                return
                            }
                            Nutrition.foods[page.foodId] = data
                            Nutrition.changed = true
                            page.foodIdChanged()
                        })
                    })
                }
            }
        }

        Column {
            id: column
            width: parent.width

            PageHeader {
                title: page.food ? Store.shown(page.food) : ""
                description: page.food ? page.food.brand || "" : ""
            }
            ErrorBanner {
                text: page.errorText
            }

            SectionHeader {
                text: page.food ? qsTr("Per %1 %2").arg(Store.formatNumber(parseFloat(page.food.serving_size)))
                                  .arg(Nutrition.unitText(page.food.serving_unit, qsTr("pcs"))) : ""
            }
            DetailItem { label: qsTr("Energy"); value: page.food ? page.food.calories + " kcal"
                                                                   + (Store.present(page.food.energy_kj) ? " / " + Math.round(parseFloat(page.food.energy_kj)) + " kJ" : "") : "" }
            DetailItem { label: qsTr("Fat"); value: page.value("fat_grams", "g") }
            DetailItem { visible: value !== ""; label: qsTr("of which saturates"); value: page.value("saturated_fat_grams", "g") }
            DetailItem { label: qsTr("Carbohydrate"); value: page.value("carbohydrate_grams", "g") }
            DetailItem { visible: value !== ""; label: qsTr("of which sugars"); value: page.value("sugar_grams", "g") }
            DetailItem { visible: value !== ""; label: qsTr("of which starch"); value: page.value("starch_grams", "g") }
            DetailItem { visible: value !== ""; label: qsTr("of which polyols"); value: page.value("polyols_grams", "g") }
            DetailItem { visible: value !== ""; label: qsTr("Fibre"); value: page.value("fiber_grams", "g") }
            DetailItem { label: qsTr("Protein"); value: page.value("protein_grams", "g") }
            DetailItem { visible: value !== ""; label: qsTr("Salt"); value: page.value("salt_grams", "g") }
            DetailItem { visible: value !== ""; label: qsTr("Sodium"); value: page.value("sodium_mg", "mg", 0) }

            Repeater {
                model: page.food ? page.food.other_nutrients || [] : []
                delegate: DetailItem {
                    label: modelData.key
                    value: modelData.value + " " + (modelData.unit || "")
                }
            }

            SectionHeader {
                visible: page.food !== null && (Store.present(page.food.nutri_score) || Store.present(page.food.nova_group))
                text: qsTr("Quality")
            }
            DetailItem {
                visible: page.food !== null && Store.present(page.food.nutri_score)
                label: qsTr("Nutri-Score")
                value: page.food && page.food.nutri_score ? page.food.nutri_score.toUpperCase() : ""
            }
            DetailItem {
                visible: page.food !== null && Store.present(page.food.nova_group)
                label: qsTr("NOVA group")
                value: page.food ? page.novaText(page.food.nova_group) : ""
            }
            Label {
                visible: page.food !== null && Store.present(page.food.off_id)
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                topPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: qsTr("Data from Open Food Facts (ODbL), barcode %1").arg(page.food ? page.food.off_id : "")
            }
        }

        VerticalScrollDecorator {}
    }
}
