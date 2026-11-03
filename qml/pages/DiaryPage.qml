import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store
import "../js/nutrition.js" as Nutrition

// The food diary, one day at a time like the web's: the day's totals
// against the target, then each meal with what was logged. Add a food or
// recipe, a quick entry, copy the day to another date, save a meal as a
// recipe; entries can be corrected or removed. New entries go through the
// sync queue, so they're kept on the phone without a connection and shown
// (worked out from the food or recipe) until the server has them.
Page {
    id: page
    objectName: "diaryPage"

    property date day: new Date()
    property var entries: []
    // The meals, copied from Nutrition.slots once ensure() is done: a
    // library variable doesn't notify bindings, so a diary opened before
    // the library was loaded would show no meals (nor their entries).
    property var slots: []
    property var target: null
    property bool loading: false
    property string errorText: ""
    // Something worth knowing about the last action, not an error.
    property string notice: ""

    readonly property string isoDay: Store.isoDate(day)
    // The day's entries still waiting in the sync queue.
    readonly property var pending: Store.pendingPosts(syncQueue.items, "diary-entries/").filter(function(e) {
        return e.date === isoDay
    })
    readonly property var shown: entries.concat(pending)
    readonly property var totals: Nutrition.total(shown, Nutrition.foods || {}, Nutrition.recipes || {})

    readonly property var texts: ({ servings: qsTr("%1 serving(s)"), portions: qsTr("%1 portion(s)"), piece: qsTr("pcs") })

    function entriesOf(slotId) {
        return shown.filter(function(e) { return e.meal_slot === slotId })
    }

    // The day is read here, not from isoDay: onDayChanged runs before
    // that binding has followed, which showed the previous day's entries
    // (and edited or deleted those). A reply for a day no longer shown is
    // dropped.
    function load(keepError) {
        var iso = Store.isoDate(day)
        loading = true
        Nutrition.ensure(api, function(ok, error) {
            if (!ok) {
                loading = false
                errorText = error
                return
            }
            slots = Nutrition.slots || []
            Nutrition.entriesFor(api, iso, function(ok2, found, error2) {
                if (iso !== Store.isoDate(day))
                    return
                loading = false
                errorText = ok2 ? (keepError || "") : error2
                if (ok2)
                    entries = found
            })
        })
        api.request("GET", "nutrition-targets/?page_size=100", null, function(ok, status, data) {
            if (ok)
                target = Nutrition.currentTarget(data.results)
        })
    }

    function changed(error) {
        Nutrition.diaryEdited()
        load(error || "")
    }

    function slotCalories(slotEntries) {
        return Math.round(Nutrition.total(slotEntries, Nutrition.foods, Nutrition.recipes).calories) + " kcal"
    }

    // The meal for a new entry: the first one, unless one is given.
    function defaultSlot() {
        return slots[0] || null
    }

    function addFood(slot) {
        var picker = pageStack.push(Qt.resolvedUrl("FoodsPage.qml"), { picking: true, includeRecipes: true })
        picker.picked.connect(function(kind, id) {
            var dialog = pageStack.replace(Qt.resolvedUrl("DiaryEntryDialog.qml"), {
                kind: kind, itemId: id, slot: slot || defaultSlot(), day: day
            })
            dialog.accepted.connect(function() { log(dialog.body()) })
        })
    }

    function log(body) {
        syncQueue.enqueue("POST", "diary-entries/", body)
        Nutrition.diaryEdited()
    }

    function quickEntry(slot) {
        var dialog = pageStack.push(Qt.resolvedUrl("DiaryEntryDialog.qml"), {
            kind: "quick", slot: slot || defaultSlot(), day: day
        })
        dialog.accepted.connect(function() { log(dialog.body()) })
    }

    function edit(entry) {
        var slot = slots.filter(function(s) { return s.id === entry.meal_slot })[0] || null
        var dialog = pageStack.push(Qt.resolvedUrl("DiaryEntryDialog.qml"), { entry: entry, slot: slot })
        dialog.accepted.connect(function() {
            api.request("PATCH", "diary-entries/" + entry.id + "/", dialog.body(), function(ok, status, data, error) {
                changed(ok ? "" : error)
            })
        })
    }

    function copyDay() {
        var picker = pageStack.push("Sailfish.Silica.DatePickerDialog", { date: Store.addDays(day, 1) })
        picker.accepted.connect(function() {
            loading = true
            Nutrition.copyDay(api, isoDay, Store.isoDate(picker.date), function(ok, copied, error) {
                loading = false
                Nutrition.diaryEdited()
                errorText = ok ? "" : error
                if (ok)
                    day = picker.date
            })
        })
    }

    function saveAsRecipe(slot) {
        var name = Store.contentName(slot.name) + " - " + isoDay
        Nutrition.saveMealAsRecipe(api, entriesOf(slot.id), name, function(ok, recipeId, error) {
            if (!ok) {
                errorText = error || qsTr("Nothing logged for this meal yet to save as a recipe.")
                return
            }
            Nutrition.changed = true
            Store.whenIdle(pageStack, function() { pageStack.push(Qt.resolvedUrl("RecipePage.qml"), { recipeId: recipeId }) })
        })
    }

    SyncWatcher {
        writes: "diary-entries/"
        onSynced: page.changed("")
        onFailed: page.changed(error)
    }

    onDayChanged: {
        entries = []
        notice = ""
        load()
    }
    Component.onCompleted: load()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            busy: page.loading
            MenuItem {
                enabled: page.entries.length > 0
                text: qsTr("Copy this day to another date")
                onClicked: page.copyDay()
            }
            MenuItem {
                text: qsTr("Quick entry")
                onClicked: page.quickEntry(null)
            }
            MenuItem {
                text: qsTr("Add food")
                onClicked: page.addFood(null)
            }
        }

        Column {
            id: column
            width: parent.width

            PageHeader {
                title: qsTr("Food diary")
            }

            // Previous day, the day (tap to jump), next day.
            Item {
                width: parent.width
                height: Theme.itemSizeSmall
                IconButton {
                    id: previousDay
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-left"
                    onClicked: page.day = Store.addDays(page.day, -1)
                }
                BackgroundItem {
                    anchors.left: previousDay.right
                    anchors.right: nextDay.left
                    height: parent.height
                    onClicked: {
                        var picker = pageStack.push("Sailfish.Silica.DatePickerDialog", { date: page.day })
                        picker.accepted.connect(function() { page.day = picker.date })
                    }
                    Label {
                        anchors.centerIn: parent
                        color: Theme.highlightColor
                        text: Store.isToday(page.isoDay, new Date()) ? qsTr("Today")
                              : Format.formatDate(page.day, Formatter.DateFull)
                    }
                }
                IconButton {
                    id: nextDay
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-right"
                    onClicked: page.day = Store.addDays(page.day, 1)
                }
            }

            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }

            Label {
                visible: page.notice !== ""
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: visible ? implicitHeight + Theme.paddingMedium : 0
                verticalAlignment: Text.AlignTop
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.highlightColor
                text: page.notice
            }

            SyncStatus {}

            MacroSummary {
                totals: page.totals
                target: page.target
            }

            Repeater {
                model: page.slots
                delegate: Column {
                    property var slot: modelData
                    property var slotEntries: page.entriesOf(modelData.id)
                    width: page.width

                    // The meal's name and calories; its menu adds to it.
                    ListItem {
                        contentHeight: Theme.itemSizeSmall
                        onClicked: page.addFood(slot)
                        menu: ContextMenu {
                            MenuItem {
                                text: qsTr("Add food")
                                onClicked: page.addFood(slot)
                            }
                            MenuItem {
                                text: qsTr("Quick entry")
                                onClicked: page.quickEntry(slot)
                            }
                            MenuItem {
                                visible: slotEntries.length > 0
                                text: qsTr("Save as recipe")
                                onClicked: page.saveAsRecipe(slot)
                            }
                        }
                        SectionHeader {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Store.contentName(slot.name) + (slotEntries.length ? " · " + page.slotCalories(slotEntries) : "")
                        }
                    }

                    Repeater {
                        model: slotEntries
                        delegate: ListItem {
                            id: entryItem
                            property var nutrition: Nutrition.forEntry(modelData, Nutrition.foods, Nutrition.recipes)
                            contentHeight: Math.max(Theme.itemSizeSmall, entryColumn.height + 2 * Theme.paddingSmall)
                            // Waiting in the sync queue: nothing to edit on the server yet.
                            property bool pending: modelData.pendingId !== undefined
                            onClicked: {
                                if (!pending)
                                    page.edit(modelData)
                            }
                            menu: pending ? null : entryMenu
                            Component {
                                id: entryMenu
                                ContextMenu {
                                    MenuItem {
                                        text: qsTr("Edit")
                                        onClicked: page.edit(modelData)
                                    }
                                    MenuItem {
                                        text: qsTr("Delete")
                                        onClicked: {
                                            var id = modelData.id
                                            entryItem.remorseDelete(function() {
                                                api.request("DELETE", "diary-entries/" + id + "/", null,
                                                            function(ok, status, data, error) { page.changed(ok ? "" : error) })
                                            })
                                        }
                                    }
                                }
                            }
                            Column {
                                id: entryColumn
                                anchors.verticalCenter: parent.verticalCenter
                                x: Theme.horizontalPageMargin
                                width: parent.width - 2 * Theme.horizontalPageMargin
                                Row {
                                    width: parent.width
                                    Label {
                                        width: parent.width - kcalLabel.width
                                        truncationMode: TruncationMode.Fade
                                        text: Nutrition.entryName(modelData, Nutrition.foods, Nutrition.recipes, qsTr("Quick entry"))
                                    }
                                    Label {
                                        id: kcalLabel
                                        color: Theme.highlightColor
                                        text: Math.round(nutrition.calories) + " kcal"
                                    }
                                }
                                Label {
                                    width: parent.width
                                    truncationMode: TruncationMode.Fade
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                    color: Theme.secondaryColor
                                    text: (pending ? qsTr("Not sent yet") + " · " : "")
                                          + Nutrition.quantityText(modelData, Nutrition.foods, page.texts)
                                          + " · " + qsTr("P") + " " + Math.round(nutrition.protein_grams)
                                          + " · " + qsTr("C") + " " + Math.round(nutrition.carbohydrate_grams)
                                          + " · " + qsTr("F") + " " + Math.round(nutrition.fat_grams)
                                          + (modelData.notes ? " · " + modelData.notes : "")
                                }
                            }
                        }
                    }
                }
            }

            Label {
                visible: !page.loading && page.shown.length === 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                topPadding: Theme.paddingLarge
                horizontalAlignment: Text.AlignHCenter
                color: Theme.secondaryColor
                text: qsTr("Nothing logged yet.")
            }
        }

        VerticalScrollDecorator {}
    }
}
