import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store
import "../js/texts.js" as Texts

// One stretch routine, like the web's: its stretches with hold, sets and
// rest. Start it as a guided session, or log it as done. Your own routines
// can be edited - details, stretches added, changed, reordered, removed -
// or deactivated; a built-in one can be copied to edit.
Page {
    id: page

    property var routine
    property bool loading: false
    property string errorText: ""

    readonly property bool editable: routine ? routine.is_custom : false
    readonly property var items: routine ? routine.items.slice().sort(function(a, b) {
        return a.order - b.order || a.id - b.id
    }) : []
    readonly property var steps: Store.stretchSteps(items, Store.stretches || {})
    readonly property int estimatedSeconds: steps.reduce(function(total, s) { return total + s.seconds }, 0)

    function load(keepError) {
        loading = true
        Store.ensureStretches(api, function() {
            api.request("GET", "stretch-routines/" + routine.id + "/", null, function(ok, status, data, error) {
                loading = false
                errorText = ok ? (keepError || "") : error
                if (ok)
                    routine = data
            })
        })
    }

    function write(method, path, body) {
        api.request(method, path, body, function(ok, status, data, error) {
            Store.stretchingChanged = true
            load(ok ? "" : error)
        })
    }

    function itemText(item) {
        var stretch = Store.stretches ? Store.stretches[item.stretch] : null
        var hold = Store.present(item.hold_seconds) ? item.hold_seconds : (stretch ? stretch.default_hold_seconds : "?")
        var parts = [hold + " s" + (stretch && stretch.per_side ? " " + qsTr("per side") : "")]
        if (item.sets > 1)
            parts.push(qsTr("%n set(s)", "", item.sets))
        if (item.rest_seconds)
            parts.push(qsTr("Rest") + " " + item.rest_seconds + " s")
        return parts.join(" · ")
    }

    function addStretch() {
        var picker = pageStack.push(Qt.resolvedUrl("StretchesPage.qml"), { picking: true })
        picker.selected.connect(function(stretchId) {
            var dialog = pageStack.replace(Qt.resolvedUrl("RoutineItemDialog.qml"), { stretchId: stretchId })
            dialog.accepted.connect(function() {
                var body = dialog.body()
                body.routine = routine.id
                body.order = items.length ? items[items.length - 1].order + 1 : 0
                write("POST", "stretch-routine-items/", body)
            })
        })
    }

    function editItem(item) {
        var dialog = pageStack.push(Qt.resolvedUrl("RoutineItemDialog.qml"), { item: item })
        dialog.accepted.connect(function() { write("PATCH", "stretch-routine-items/" + item.id + "/", dialog.body()) })
    }

    function move(index, direction) {
        var other = Store.swapTarget(items.length, index, direction)
        if (other < 0)
            return
        var a = items[index]
        var b = items[other]
        var orderA = a.order === b.order ? other : b.order
        var orderB = a.order === b.order ? index : a.order
        api.request("PATCH", "stretch-routine-items/" + a.id + "/", { order: orderA }, function(ok, status, data, error) {
            if (!ok)
                return load(error)
            write("PATCH", "stretch-routine-items/" + b.id + "/", { order: orderB })
        })
    }

    function copy() {
        loading = true
        api.request("GET", "stretch-routines/?page_size=100", null, function(ok, status, data) {
            var taken = ok ? data.results.filter(function(r) { return r.is_custom }).map(function(r) { return r.name }) : []
            var name = Store.copyName(qsTr("%1 (copy)").arg(Store.contentName(routine.name)), taken)
            Store.copyRoutine(api, routine, name, Texts.contentText(routine.description), function(ok2, created, error) {
                loading = false
                if (!ok2) {
                    errorText = error
                    return
                }
                Store.stretchingChanged = true
                pageStack.replace(Qt.resolvedUrl("StretchRoutinePage.qml"), { routine: created })
            })
        })
    }

    function logDone() {
        var dialog = pageStack.push(Qt.resolvedUrl("StretchSessionDialog.qml"), {
            routines: [routine], routine: routine,
            initialMinutes: Math.max(1, Math.round(estimatedSeconds / 60))
        })
        dialog.accepted.connect(function() {
            api.request("POST", "stretch-sessions/", dialog.body(), function(ok, status, data, error) {
                errorText = ok ? "" : error
                Store.stretchingChanged = true
            })
        })
    }

    Component.onCompleted: load()

    RemorsePopup {
        id: remorse
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: page.items

        PullDownMenu {
            busy: page.loading
            MenuItem {
                visible: page.editable
                text: qsTr("Deactivate")
                onClicked: remorse.execute(qsTr("Deactivating routine"), function() {
                    api.request("DELETE", "stretch-routines/" + page.routine.id + "/", null, function(ok, status, data, error) {
                        if (!ok) {
                            page.errorText = error
                            return
                        }
                        Store.stretchingChanged = true
                        pageStack.pop()
                    })
                })
            }
            MenuItem {
                visible: page.editable
                text: qsTr("Edit routine")
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("RoutineEditDialog.qml"), { routine: page.routine })
                    dialog.accepted.connect(function() {
                        page.write("PATCH", "stretch-routines/" + page.routine.id + "/", dialog.body())
                    })
                }
            }
            MenuItem {
                visible: !page.editable
                text: qsTr("Copy to edit")
                onClicked: page.copy()
            }
            MenuItem {
                visible: page.editable
                text: qsTr("Add a stretch")
                onClicked: page.addStretch()
            }
            MenuItem {
                enabled: page.items.length > 0
                text: qsTr("Log stretching")
                onClicked: page.logDone()
            }
            MenuItem {
                enabled: page.items.length > 0
                text: qsTr("Start routine")
                onClicked: pageStack.push(Qt.resolvedUrl("StretchPlayerPage.qml"), { routine: page.routine, steps: page.steps })
            }
        }

        header: Column {
            width: parent.width
            PageHeader {
                title: page.routine ? Store.contentName(page.routine.name) : ""
                description: page.editable ? qsTr("Custom") : qsTr("Built-in routine")
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }
            Label {
                visible: text !== ""
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: [page.routine ? Texts.contentText(page.routine.description) : "",
                       page.items.length ? "≈ " + Store.formatMinutes(page.estimatedSeconds) : ""]
                      .filter(function(p) { return p }).join("\n")
            }
        }

        delegate: ListItem {
            id: item
            contentHeight: Math.max(Theme.itemSizeSmall, textColumn.height + 2 * Theme.paddingSmall)
            onClicked: pageStack.push(Qt.resolvedUrl("StretchPage.qml"), { stretchId: modelData.stretch })
            menu: page.editable ? itemMenu : null

            Component {
                id: itemMenu
                ContextMenu {
                    MenuItem {
                        text: qsTr("Edit")
                        onClicked: page.editItem(modelData)
                    }
                    MenuItem {
                        visible: index > 0
                        text: qsTr("Move up")
                        onClicked: page.move(index, -1)
                    }
                    MenuItem {
                        visible: index < page.items.length - 1
                        text: qsTr("Move down")
                        onClicked: page.move(index, 1)
                    }
                    MenuItem {
                        text: qsTr("Remove")
                        onClicked: {
                            var id = modelData.id
                            item.remorseDelete(function() { page.write("DELETE", "stretch-routine-items/" + id + "/", null) })
                        }
                    }
                }
            }

            Column {
                id: textColumn
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    text: Store.stretchName(modelData.stretch)
                }
                Label {
                    width: parent.width
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    text: page.itemText(modelData)
                }
            }
        }

        ViewPlaceholder {
            enabled: !page.loading && page.items.length === 0
            text: qsTr("No stretches in this routine yet.")
        }

        VerticalScrollDecorator {}
    }
}
