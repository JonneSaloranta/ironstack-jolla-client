import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store
import "../js/nutrition.js" as Nutrition

// The food library, like the web's: search by name, brand or barcode,
// your own foods and the shared ones. Browsing opens a food; with
// `picking` a tap emits picked() - with `includeRecipes` recipes are
// offered too (logging to the diary). Foods are searched on the server
// (`foods/?search=`, which also matches a barcode); recipes, whose
// built-in names are shown translated, in the library here.
Page {
    id: page

    property bool picking: false
    property bool includeRecipes: false
    signal picked(string kind, int id)

    property bool loading: false
    property string errorText: ""
    property string searchText: ""
    // The server's matches for the search: [food], or null until it answers.
    property var found: null

    ListModel {
        id: filtered
    }

    function applyFilter() {
        var term = searchText.trim().toLowerCase()
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
        var fromServer = term && found !== null
        Nutrition.list(fromServer ? found : Nutrition.foods || {}).forEach(function(f) {
            var name = Store.contentName(f.name)
            if (!f.active || (!fromServer && !matches(name, f.brand)))
                return
            filtered.append({ kind: "food", id: f.id, name: name, section: qsTr("Foods"),
                              detail: [f.brand, f.calories + " kcal / " + Store.formatNumber(parseFloat(f.serving_size))
                                       + " " + Nutrition.unitText(f.serving_unit, qsTr("pcs")),
                                       Store.present(f.owner) ? qsTr("Custom") : ""]
                                      .filter(function(p) { return p }).join(" · ") })
        })
    }

    // One request once typing pauses; until it answers, the library
    // already loaded is searched here.
    function search() {
        var term = searchText.trim()
        if (!term) {
            found = null
            return applyFilter()
        }
        api.request("GET", "foods/?page_size=100&search=" + encodeURIComponent(term), null,
                    function(ok, status, data, error) {
            if (term !== searchText.trim())
                return
            errorText = ok ? "" : error
            found = ok ? data.results || [] : null
            // A match the library doesn't have yet (just imported by
            // someone else) is still picked and shown by id.
            if (found && Nutrition.foods)
                found.forEach(function(f) { Nutrition.foods[f.id] = f })
            applyFilter()
        })
    }

    Timer {
        id: searchTimer
        interval: 400
        onTriggered: page.search()
    }

    onSearchTextChanged: {
        found = null
        applyFilter()
        searchTimer.restart()
    }

    function load() {
        loading = true
        Nutrition.ensure(api, function(ok, error) {
            loading = false
            errorText = ok ? "" : error
            if (searchText.trim())
                search()
            else
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
