import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store
import "../js/nutrition.js" as Nutrition
import "../js/openfoodfacts.js" as Off

// Find a product in Open Food Facts by name or barcode and add it to your
// foods, like the web's import. The API has no import, so the app reads
// Open Food Facts itself and creates the food with POST foods/ (per 100 g
// or 100 ml); a product already in the library is used as it is.
// imported(foodId) fires after a product was added or found, once the
// food is in Nutrition.foods.
Page {
    id: page

    signal imported(int foodId)

    property string query: ""
    property bool loading: false
    property bool searched: false
    property string errorText: ""
    property bool saving: false

    // [{ product, usable, name, detail }]
    property var results: []

    function search() {
        var text = query.trim()
        if (!text)
            return
        loading = true
        errorText = ""
        results = []
        var url = Off.isBarcode(text) ? Off.productUrl(text) : Off.searchUrl(text, Store.contentLanguage())
        api.openFoodFacts(url, function(ok, status, data, error) {
            loading = false
            searched = true
            if (!ok) {
                errorText = error
                return
            }
            results = Off.productsFrom(data).map(function(product) {
                var body = Off.foodBody(product)
                return {
                    product: product,
                    usable: body !== null,
                    name: String(product.product_name || product.generic_name || product.code || ""),
                    detail: [Off.firstBrand(product.brands),
                             body ? body.calories + " kcal / 100 " + body.serving_unit : qsTr("Nutrition values missing")]
                            .filter(function(p) { return p }).join(" · ")
                }
            })
        })
    }

    function add(product) {
        var body = Off.foodBody(product)
        if (!body)
            return
        saving = true
        errorText = ""
        Nutrition.ensure(api, function(ok, error) {
            if (!ok) {
                saving = false
                errorText = error
                return
            }
            var existing = Off.existingFood(Nutrition.foods, product, body)
            if (existing) {
                saving = false
                page.imported(existing.id)
                return
            }
            api.request("POST", "foods/", body, function(ok2, status, data, error2) {
                saving = false
                if (!ok2) {
                    errorText = error2
                    return
                }
                // The library is read again first: whoever gets
                // imported() looks the food up in it straight away.
                Nutrition.changed = true
                saving = true
                Nutrition.ensure(api, function() {
                    saving = false
                    page.imported(data.id)
                })
            })
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
                text: qsTr("Values are per 100 g or 100 ml. An added product becomes one of your own foods; "
                           + "Nutri-Score and NOVA group aren't kept.")
            }
            Item {
                width: 1
                height: Theme.paddingMedium
            }
        }

        delegate: ListItem {
            enabled: modelData.usable && !page.saving
            contentHeight: Math.max(Theme.itemSizeSmall, textColumn.height + 2 * Theme.paddingSmall)
            onClicked: page.add(modelData.product)
            Column {
                id: textColumn
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                opacity: modelData.usable ? 1 : Theme.opacityLow
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
