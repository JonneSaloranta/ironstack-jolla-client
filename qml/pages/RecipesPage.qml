import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store
import "../js/nutrition.js" as Nutrition

// Your recipes, then the built-in ones (the diet plan builder's), like the
// web's list: calories per serving at a glance.
Page {
    id: page

    property var recipes: []
    property bool loading: false
    property string errorText: ""

    function load() {
        loading = true
        Nutrition.ensure(api, function(ok, error) {
            loading = false
            errorText = ok ? "" : error
            var all = Nutrition.list(Nutrition.recipes || {})
            recipes = all.filter(function(r) { return Store.present(r.owner) })
                    .concat(all.filter(function(r) { return !Store.present(r.owner) }))
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
        model: page.recipes

        PullDownMenu {
            busy: page.loading
            MenuItem {
                text: qsTr("New recipe")
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("RecipeEditDialog.qml"))
                    dialog.accepted.connect(function() {
                        api.request("POST", "recipes/", dialog.body(), function(ok, status, data, error) {
                            if (!ok) {
                                page.errorText = error
                                return
                            }
                            Nutrition.changed = true
                            page.load()
                            Store.whenIdle(pageStack, function() { pageStack.push(Qt.resolvedUrl("RecipePage.qml"), { recipeId: data.id }) })
                        })
                    })
                }
            }
        }

        header: Column {
            width: parent.width
            PageHeader {
                title: qsTr("Recipes")
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }
        }

        delegate: Column {
            width: list.width
            property bool builtIn: !Store.present(modelData.owner)
            SectionHeader {
                visible: builtIn && (index === 0 || Store.present(page.recipes[index - 1].owner))
                text: qsTr("Built-in recipes")
            }
            ListItem {
                contentHeight: Math.max(Theme.itemSizeSmall, textColumn.height + 2 * Theme.paddingSmall)
                onClicked: pageStack.push(Qt.resolvedUrl("RecipePage.qml"), { recipeId: modelData.id })
                Column {
                    id: textColumn
                    anchors.verticalCenter: parent.verticalCenter
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    Label {
                        width: parent.width
                        truncationMode: TruncationMode.Fade
                        text: Store.shown(modelData)
                    }
                    Label {
                        width: parent.width
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryColor
                        text: Math.round(Nutrition.recipePerServing(modelData, Nutrition.foods).calories) + " kcal / "
                              + qsTr("serving") + " · " + qsTr("%n serving(s)", "", modelData.servings)
                    }
                }
            }
        }

        ViewPlaceholder {
            enabled: !page.loading && page.recipes.length === 0 && page.errorText === ""
            text: qsTr("No recipes yet.")
            hintText: qsTr("Pull down to create one")
        }

        VerticalScrollDecorator {}
    }
}
