import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

// A diet plan's shopping list, like the web's: one trip at a time (the
// next one, or any other), each food's total and how much each day needs;
// the shopping days and whether the shopping day itself is bought for can
// be changed. Ticks are kept on the phone per plan and trip, like the
// web's (there in the browser): a convenience in the shop, not data.
Page {
    id: page

    property int planId
    property var list: null
    property var settings_: null
    property int trip: -2       // -2 = the next trip (the server decides)
    property var ticked: ({})
    property bool loading: false
    property string errorText: ""

    function weekdayName(index, format) {
        return Qt.locale().dayName((index + 1) % 7, format === undefined ? Locale.ShortFormat : format)
    }

    function tripText(t) {
        if (!t || t.weekday === null)
            return qsTr("Whole week")
        return weekdayName(t.weekday, Locale.LongFormat) + " (" + t.days.map(function(d) { return weekdayName(d) }).join(", ") + ")"
    }

    // The trip shown, as the web keys its ticks: a weekday or "week".
    function tickKey() {
        var t = list ? list.trip : null
        return "shopping/" + planId + "/" + (t && t.weekday !== null && t.weekday !== undefined ? t.weekday : "week")
    }

    function readTicks() {
        var saved = settings.cached(tickKey()) || []
        var result = {}
        saved.forEach(function(food) { result[food] = true })
        ticked = result
    }

    function saveTicks() {
        var foods = []
        for (var food in ticked) {
            if (ticked[food])
                foods.push(parseInt(food, 10))
        }
        settings.setCached(tickKey(), foods)
    }

    function load(keepError) {
        loading = true
        var path = "diet-plans/" + planId + "/shopping-list/" + (trip >= 0 ? "?trip=" + trip : "")
        api.request("GET", path, null, function(ok, status, data, error) {
            loading = false
            errorText = ok ? (keepError || "") : error
            if (ok) {
                list = data
                readTicks()
            }
        })
        api.request("GET", "diet-plans/" + planId + "/shopping-settings/", null, function(ok, status, data) {
            if (ok)
                settings_ = data
        })
    }

    function saveSettings(changes) {
        api.request("PATCH", "diet-plans/" + planId + "/shopping-settings/", changes, function(ok, status, data, error) {
            trip = -2
            load(ok ? "" : error)
        })
    }

    function toggleWeekday(day) {
        var days = (settings_ ? settings_.weekdays : []).slice()
        var at = days.indexOf(day)
        if (at >= 0)
            days.splice(at, 1)
        else
            days.push(day)
        saveSettings({ weekdays: days.sort() })
    }

    function toggleTick(food) {
        var copy = Store.copy(ticked)
        copy[food] = !copy[food]
        ticked = copy
        saveTicks()
    }

    readonly property bool anyTicked: {
        for (var food in ticked) {
            if (ticked[food])
                return true
        }
        return false
    }

    Component.onCompleted: load()

    SilicaListView {
        id: view
        anchors.fill: parent
        model: page.list ? page.list.items : []

        PullDownMenu {
            busy: page.loading
            MenuItem {
                visible: page.anyTicked
                text: qsTr("Clear ticks")
                onClicked: {
                    page.ticked = {}
                    page.saveTicks()
                }
            }
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.load()
            }
        }

        header: Column {
            width: parent.width
            PageHeader {
                title: qsTr("Shopping list")
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }
            ComboBox {
                visible: page.list !== null && page.list.trips.length > 1
                label: qsTr("Trip")
                value: page.list ? page.tripText(page.list.trip) : ""
                menu: ContextMenu {
                    Repeater {
                        model: page.list ? page.list.trips : []
                        MenuItem {
                            text: page.tripText(modelData)
                            onClicked: {
                                page.trip = modelData.weekday === null ? -2 : modelData.weekday
                                page.load()
                            }
                        }
                    }
                }
            }
            Label {
                visible: page.list !== null && page.list.trips.length <= 1
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                color: Theme.secondaryHighlightColor
                text: page.list ? page.tripText(page.list.trip) : ""
            }
        }

        delegate: ListItem {
            contentHeight: Math.max(Theme.itemSizeSmall, row.height + 2 * Theme.paddingSmall)
            onClicked: page.toggleTick(modelData.food)
            Column {
                id: row
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                opacity: page.ticked[modelData.food] ? Theme.opacityLow : 1.0
                Row {
                    width: parent.width
                    Label {
                        width: parent.width - total.width
                        truncationMode: TruncationMode.Fade
                        font.strikeout: !!page.ticked[modelData.food]
                        text: Store.shown(modelData, "food_name")
                    }
                    Label {
                        id: total
                        color: Theme.highlightColor
                        text: Store.formatNumber(Math.round(parseFloat(modelData.total) * 10) / 10) + " "
                              + (modelData.unit === "piece" ? qsTr("pcs") : modelData.unit)
                    }
                }
                Label {
                    visible: modelData.by_day.length > 1
                    width: parent.width
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    text: modelData.by_day.map(function(d) {
                        return page.weekdayName(d.weekday) + " " + Store.formatNumber(Math.round(parseFloat(d.quantity) * 10) / 10)
                    }).join(" · ")
                }
            }
        }

        footer: Column {
            width: parent.width
            visible: page.settings_ !== null
            SectionHeader {
                text: qsTr("Shopping days")
            }
            Repeater {
                model: 7
                TextSwitch {
                    text: page.weekdayName(index, Locale.LongFormat)
                    checked: page.settings_ ? page.settings_.weekdays.indexOf(index) >= 0 : false
                    automaticCheck: false
                    onClicked: page.toggleWeekday(index)
                }
            }
            TextSwitch {
                text: qsTr("Buy for the shopping day itself")
                checked: page.settings_ ? page.settings_.include_shopping_day : false
                automaticCheck: false
                onClicked: page.saveSettings({ include_shopping_day: !checked })
            }
        }

        ViewPlaceholder {
            enabled: !page.loading && page.list !== null && page.list.items.length === 0
            text: qsTr("Nothing to buy.")
        }

        VerticalScrollDecorator {}
    }
}
