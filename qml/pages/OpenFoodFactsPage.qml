import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store
import "../js/nutrition.js" as Nutrition

// Find a product in Open Food Facts by name or barcode and add it, like
// the web's import: IronStack searches its foods and Open Food Facts
// together (foods/search-off/) and imports a product as a shared food with
// its Nutri-Score, NOVA group and OFF link (foods/import-off/), within the
// server's own Open Food Facts budget. imported(foodId) fires once the food
// is in Nutrition.foods.
Page {
    id: page

    signal imported(int foodId)

    property string query: ""
    property bool loading: false
    property bool searched: false
    property string errorText: ""
    property bool saving: false

    // [{ foodId (already here) or offId, name, detail }]
    property var results: []

    function detail(item) {
        return [item.brand, item.calories + " kcal / " + Store.formatNumber(parseFloat(item.serving_size)) + " "
                + Nutrition.unitText(item.serving_unit, qsTr("pcs")),
                item.nutri_score ? "Nutri-Score " + item.nutri_score.toUpperCase() : ""]
                .filter(function(p) { return p }).join(" · ")
    }

    function search() {
        var text = query.trim()
        if (!text)
            return
        loading = true
        errorText = ""
        results = []
        api.request("GET", "foods/search-off/?q=" + encodeURIComponent(text), null, function(ok, status, data, error) {
            loading = false
            searched = true
            if (!ok) {
                errorText = error
                return
            }
            if (data.status === "disabled")
                errorText = qsTr("Open Food Facts is turned off on this IronStack server.")
            else if (data.status === "busy")
                errorText = qsTr("Open Food Facts is busy, try again in a minute.")
            else if (data.status === "error")
                errorText = qsTr("Open Food Facts couldn't be reached.")
            results = (data.local || []).map(function(food) {
                return { foodId: food.id, food: food, name: Store.contentName(food.name),
                         detail: qsTr("Already in the food library") + " · " + detail(food) }
            }).concat((data.results || []).map(function(product) {
                return { offId: product.off_id, name: product.name, detail: detail(product) }
            }))
        })
    }

    function done(food) {
        if (Nutrition.foods)
            Nutrition.foods[food.id] = food
        Nutrition.changed = true
        page.imported(food.id)
    }

    function add(item) {
        if (item.food)
            return done(item.food)
        saving = true
        errorText = ""
        api.request("POST", "foods/import-off/", { barcode: item.offId }, function(ok, status, data, error) {
            saving = false
            if (!ok) {
                errorText = error
                return
            }
            done(data)
        })
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: page.results

        header: Column {
            width: parent.width
            PageHeader {
                title: qsTr("Open Food Facts")
            }
            ErrorBanner {
                text: page.errorText
                showRetry: page.query.trim() !== ""
                onRetry: page.search()
            }
            SearchField {
                id: searchField
                width: parent.width
                placeholderText: qsTr("Product name or barcode")
                inputMethodHints: Qt.ImhNoPredictiveText
                EnterKey.iconSource: "image://theme/icon-m-search"
                EnterKey.onClicked: {
                    page.query = text
                    focus = false
                    page.search()
                }
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Values are per 100 g or 100 ml. An added product is shared with everyone on your "
                           + "IronStack, like on the web.")
            }
            Item {
                width: 1
                height: Theme.paddingMedium
            }
        }

        delegate: ListItem {
            enabled: !page.saving
            contentHeight: Math.max(Theme.itemSizeSmall, textColumn.height + 2 * Theme.paddingSmall)
            onClicked: page.add(modelData)
            Column {
                id: textColumn
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: modelData.name
                }
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    text: modelData.detail
                }
            }
        }

        ViewPlaceholder {
            enabled: page.searched && !page.loading && page.results.length === 0 && page.errorText === ""
            text: qsTr("Nothing found")
            hintText: qsTr("Try another name, or the barcode under the stripes.")
        }

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: page.loading || page.saving
        }

        VerticalScrollDecorator {}
    }
}
