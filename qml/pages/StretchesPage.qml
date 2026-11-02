import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

// The stretch library, like the web's: filter by type and muscle group,
// search. Browsing opens a stretch; with `picking` a tap emits selected()
// (adding a stretch to a routine) and the caller moves on.
Page {
    id: page

    property bool picking: false
    signal selected(int stretchId)

    property var all: []
    property bool loading: false
    property string errorText: ""
    property string searchText: ""
    property string kind: ""
    property int muscleGroup: 0
    property bool lookupsLoaded: false

    ListModel {
        id: filtered
    }

    function applyFilter() {
        var term = searchText.toLowerCase()
        filtered.clear()
        all.forEach(function(s) {
            if (kind && s.kind !== kind)
                return
            if (muscleGroup && s.muscle_groups.indexOf(muscleGroup) < 0)
                return
            var name = Store.contentName(s.name)
            if (term && name.toLowerCase().indexOf(term) < 0 && s.name.toLowerCase().indexOf(term) < 0)
                return
            filtered.append({ id: s.id, name: name, custom: s.is_custom, kind: s.kind, perSide: s.per_side,
                              hold: s.default_hold_seconds })
        })
    }

    onSearchTextChanged: applyFilter()
    onKindChanged: applyFilter()
    onMuscleGroupChanged: applyFilter()

    function load() {
        loading = true
        Store.ensureLookups(api, function() { lookupsLoaded = true })
        Store.ensureStretches(api, function(ok, error) {
            loading = false
            errorText = ok ? "" : error
            if (!ok)
                return
            var list = []
            for (var id in Store.stretches)
                list.push(Store.stretches[id])
            all = list.sort(function(a, b) { return Store.contentName(a.name).localeCompare(Store.contentName(b.name)) })
            applyFilter()
        })
    }

    function kindText(value) {
        return value === "dynamic" ? qsTr("Dynamic") : qsTr("Static")
    }

    Component.onCompleted: load()
    onStatusChanged: {
        if (status === PageStatus.Active && Store.stretchesChanged)
            load()
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: filtered

        PullDownMenu {
            busy: page.loading
            MenuItem {
                text: qsTr("New stretch")
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("StretchEditDialog.qml"))
                    dialog.accepted.connect(function() {
                        api.request("POST", "stretches/", dialog.body(), function(ok, status, data, error) {
                            if (!ok)
                                page.errorText = error
                            Store.stretchesChanged = true
                            page.load()
                        })
                    })
                }
            }
        }

        header: Column {
            width: parent.width
            PageHeader {
                title: page.picking ? qsTr("Add a stretch") : qsTr("Stretches")
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }
            ComboBox {
                label: qsTr("Type")
                menu: ContextMenu {
                    MenuItem { text: qsTr("All types"); onClicked: page.kind = "" }
                    MenuItem { text: qsTr("Static"); onClicked: page.kind = "static" }
                    MenuItem { text: qsTr("Dynamic"); onClicked: page.kind = "dynamic" }
                }
            }
            ComboBox {
                label: qsTr("Muscle group")
                menu: ContextMenu {
                    MenuItem {
                        text: qsTr("All muscle groups")
                        onClicked: page.muscleGroup = 0
                    }
                    Repeater {
                        model: Store.lookupList("muscleGroups", page.lookupsLoaded)
                        MenuItem {
                            text: modelData.name
                            onClicked: page.muscleGroup = modelData.id
                        }
                    }
                }
            }
            SearchField {
                width: parent.width
                placeholderText: qsTr("Search")
                onTextChanged: page.searchText = text
            }
        }

        delegate: ListItem {
            contentHeight: Math.max(Theme.itemSizeSmall, textColumn.height + 2 * Theme.paddingSmall)
            onClicked: {
                if (page.picking)
                    page.selected(model.id)
                else
                    pageStack.push(Qt.resolvedUrl("StretchPage.qml"), { stretchId: model.id })
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
                    text: [page.kindText(model.kind), model.hold + " s" + (model.perSide ? " " + qsTr("per side") : ""),
                           model.custom ? qsTr("Custom") : ""].filter(function(p) { return p }).join(" · ")
                }
            }
        }

        ViewPlaceholder {
            enabled: !page.loading && filtered.count === 0 && page.errorText === ""
            text: qsTr("No stretches match.")
        }

        VerticalScrollDecorator {}
    }
}
