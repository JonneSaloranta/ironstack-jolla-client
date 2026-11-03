import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store
import "../js/nutrition.js" as Nutrition

// The food library, like the web's: search by name or brand, your own
// foods and the shared ones. Browsing opens a food; with `picking` a tap
// emits picked() - with `includeRecipes` your recipes are offered too
// (logging to the diary). The API has no food search (IronStack #28), so
// the library is fetched once and searched here.
Page {
    id: page

    property bool picking: false
    property bool includeRecipes: false
    signal picked(string kind, int id)

    property bool loading: false
    property string errorText: ""
    property string searchText: ""

    ListModel {
        id: filtered
    }

    function applyFilter() {
        var term = searchText.toLowerCase()
        filtered.clear()
        function matches(name, extra) {
            return !term || name.toLowerCase().indexOf(term) >= 0 || (extra || "").toLowerCase().indexOf(term) >= 0
        }
        if (includeRecipes) {
            Nutrition.list(Nutrition.recipes || {}).forEach(function(r) {
                var name = Store.contentName(r.name)
                if (matches(name, r.name))
                    filtered.append({ kind: "recipe", id: r.id, name: name, section: qsTr("Recipes"),
                                      detail: Math.round(Nutrition.recipePerServing(r, Nutrition.foods).calories)
                                              + " kcal / " + qsTr("serving") })
            })
        }
        Nutrition.list(Nutrition.foods || {}).forEach(function(f) {
            var name = Store.contentName(f.name)
            if (!f.active || !matches(name, f.brand))
                return
            filtered.append({ kind: "food", id: f.id, name: name, section: qsTr("Foods"),
                              detail: [f.brand, f.calories + " kcal / " + Store.formatNumber(parseFloat(f.serving_size))
                                       + " " + Nutrition.unitText(f.serving_unit, qsTr("pcs")),
                                       Store.present(f.owner) ? qsTr("Custom") : ""]
                                      .filter(function(p) { return p }).join(" · ") })
        })
    }

    onSearchTextChanged: applyFilter()

    function load() {
        loading = true
        Nutrition.ensure(api, function(ok, error) {
            loading = false
            errorText = ok ? "" : error
            applyFilter()
        })
    }

    Component.onCompleted: load()
    onStatusChanged: {
        if (status === PageStatus.Active && Nutrition.changed)
            load()
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: filtered
        section.property: page.includeRecipes ? "section" : ""
        section.delegate: SectionHeader { text: section }

        PullDownMenu {
            busy: page.loading
            MenuItem {
                text: qsTr("Find in Open Food Facts")
                onClicked: {
                    var off = pageStack.push(Qt.resolvedUrl("OpenFoodFactsPage.qml"))
                    off.imported.connect(function(foodId) {
                        // Picking: straight on with the food, as if it
                        // had been tapped here. Browsing: open it.
                        page.applyFilter()
                        pageStack.pop(page, PageStackAction.Immediate)
                        if (page.picking)
                            page.picked("food", foodId)
                        else
                            pageStack.push(Qt.resolvedUrl("FoodPage.qml"), { foodId: foodId })
                    })
                }
            }
            MenuItem {
                text: qsTr("New food")
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("FoodEditDialog.qml"))
                    dialog.accepted.connect(function() {
                        api.request("POST", "foods/", dialog.body(), function(ok, status, data, error) {
                            if (!ok)
                                page.errorText = error
                            Nutrition.changed = true
                            page.load()
                        })
                    })
                }
            }
        }

        header: Column {
            width: parent.width
            PageHeader {
                title: page.picking ? qsTr("Add food") : qsTr("Foods")
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }
            SearchField {
                width: parent.width
                placeholderText: qsTr("Search foods")
                onTextChanged: page.searchText = text
            }
        }

        delegate: ListItem {
            contentHeight: Math.max(Theme.itemSizeSmall, textColumn.height + 2 * Theme.paddingSmall)
            onClicked: {
                if (page.picking)
                    page.picked(model.kind, model.id)
                else
                    pageStack.push(Qt.resolvedUrl(model.kind === "recipe" ? "RecipePage.qml" : "FoodPage.qml"),
                                   model.kind === "recipe" ? { recipeId: model.id } : { foodId: model.id })
            }
            Column {
                id: textColumn
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    text: Theme.highlightText(model.name, page.searchText, Theme.highlightColor)
                    textFormat: Text.StyledText
                }
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    text: model.detail
                }
            }
        }

        ViewPlaceholder {
            enabled: !page.loading && filtered.count === 0 && page.errorText === ""
            text: qsTr("No foods found.")
        }

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: page.loading && filtered.count === 0
        }

        VerticalScrollDecorator {}
    }
}
