import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

// Activities, like the web's: every activity type with how many are
// logged. All activities are fetched in one go and grouped here: a request
// per type would be one per type on every visit, against the rate limit.
Page {
    id: page

    property var types: []
    // type id -> its activities, newest first
    property var activities: ({})
    property bool loading: false
    property string errorText: ""

    function load() {
        loading = true
        errorText = ""
        var foundTypes = []
        var byType = {}
        var pending = 2
        function settle(ok, error) {
            if (!ok)
                errorText = error
            pending--
            if (pending > 0)
                return
            loading = false
            types = foundTypes.sort(function(a, b) {
                return Store.shown(a).localeCompare(Store.shown(b))
            })
            activities = byType
        }
        Store.fetchAll(api, "activity-types/?page_size=100", function(results) {
            foundTypes = foundTypes.concat(results)
        }, settle)
        Store.fetchAll(api, "activities/?page_size=100", function(results) {
            results.forEach(function(a) {
                (byType[a.activity_type] = byType[a.activity_type] || []).push(a)
            })
        }, settle)
    }

    function logActivity() {
        var dialog = pageStack.push(Qt.resolvedUrl("ActivityDialog.qml"), { types: types, type: types[0] || null })
        dialog.accepted.connect(function() {
            syncQueue.enqueue("POST", "activities/", dialog.body())
        })
    }

    SyncWatcher {
        writes: "activities/"
        onSynced: page.load()
        onFailed: page.errorText = error
    }

    Component.onCompleted: load()
    onStatusChanged: {
        if (status === PageStatus.Active && Store.activitiesChanged) {
            Store.activitiesChanged = false
            load()
        }
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: page.types

        PullDownMenu {
            busy: page.loading
            MenuItem {
                text: qsTr("New activity type")
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("NameDialog.qml"), { title: qsTr("New activity type") })
                    dialog.accepted.connect(function() {
                        api.request("POST", "activity-types/", { name: dialog.name }, function(ok, status, data, error) {
                            if (!ok)
                                page.errorText = error
                            page.load()
                        })
                    })
                }
            }
            MenuItem {
                text: qsTr("Log activity")
                enabled: page.types.length > 0
                onClicked: page.logActivity()
            }
        }

        header: Column {
            width: parent.width
            PageHeader {
                title: qsTr("Activities")
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }
            SyncStatus {}
        }

        delegate: ListItem {
            property int count: (page.activities[modelData.id] || []).length
            contentHeight: Math.max(Theme.itemSizeMedium, textColumn.height + 2 * Theme.paddingMedium)
            onClicked: pageStack.push(Qt.resolvedUrl("ActivityHistoryPage.qml"), { type: modelData })

            Column {
                id: textColumn
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    color: count ? Theme.primaryColor : Theme.secondaryColor
                    text: Store.shown(modelData) + (modelData.is_custom ? " · " + qsTr("Custom") : "")
                }
                Label {
                    width: parent.width
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: count ? Theme.highlightColor : Theme.secondaryColor
                    text: count ? qsTr("%n logged", "", count) : qsTr("No activities yet")
                }
            }
        }

        ViewPlaceholder {
            enabled: !page.loading && page.types.length === 0 && page.errorText === ""
            text: qsTr("No activity types yet.")
        }

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: page.loading && page.types.length === 0
        }

        VerticalScrollDecorator {}
    }
}
