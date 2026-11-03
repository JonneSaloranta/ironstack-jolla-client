import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

// Body tracking, like the web's: every measurement type with its latest
// reading. All readings are fetched in one go and grouped here: a request
// per type would be one per type on every visit, against the rate limit.
Page {
    id: page

    property var types: []
    // type id -> its readings
    property var readings: ({})
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
            // Body weight first (the one nearly everyone tracks, as the web's
            // progress list), the rest by the name as shown.
            types = foundTypes.sort(function(a, b) {
                return Store.isBodyWeightType(b) - Store.isBodyWeightType(a)
                        || Store.contentName(a.name).localeCompare(Store.contentName(b.name))
            })
            readings = byType
        }
        Store.fetchAll(api, "measurement-types/?page_size=100", function(results) {
            foundTypes = foundTypes.concat(results)
        }, settle)
        Store.fetchAll(api, "measurements/?page_size=100", function(results) {
            results.forEach(function(r) {
                (byType[r.measurement_type] = byType[r.measurement_type] || []).push(r)
            })
        }, settle)
    }

    function logReading(type) {
        var dialog = pageStack.push(Qt.resolvedUrl("MeasurementDialog.qml"),
                                    type ? { type: type } : { types: types, type: types[0] || null })
        dialog.accepted.connect(function() {
            syncQueue.enqueue("POST", "measurements/", dialog.body())
        })
    }

    SyncWatcher {
        writes: "measurements/"
        onSynced: page.load()
        onFailed: page.errorText = error
    }

    Component.onCompleted: load()
    onStatusChanged: {
        if (status === PageStatus.Active && Store.measurementsChanged) {
            Store.measurementsChanged = false
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
                text: qsTr("New measurement type")
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("MeasurementTypeDialog.qml"))
                    dialog.accepted.connect(function() {
                        api.request("POST", "measurement-types/", dialog.body(), function(ok, status, data, error) {
                            if (!ok)
                                page.errorText = error
                            page.load()
                        })
                    })
                }
            }
            MenuItem {
                text: qsTr("Log reading")
                enabled: page.types.length > 0
                onClicked: page.logReading(null)
            }
        }

        header: Column {
            width: parent.width
            PageHeader {
                title: qsTr("Body tracking")
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }
            SyncStatus {}
        }

        delegate: ListItem {
            property var stats: Store.measurementStats(page.readings[modelData.id])
            contentHeight: Math.max(Theme.itemSizeMedium, textColumn.height + 2 * Theme.paddingMedium)
            onClicked: pageStack.push(Qt.resolvedUrl("MeasurementHistoryPage.qml"), { type: modelData })

            Column {
                id: textColumn
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    // An untracked type is dimmed, like the web's card.
                    color: stats ? Theme.primaryColor : Theme.secondaryColor
                    text: Store.contentName(modelData.name) + (modelData.is_custom ? " · " + qsTr("Custom") : "")
                }
                Label {
                    width: parent.width
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: stats ? Theme.highlightColor : Theme.secondaryColor
                    text: stats ? qsTr("Latest: %1").arg(Store.formatMeasurement(stats.latest, modelData.unit_kind,
                                                                                 settings.unitSystem))
                                  + " - " + Format.formatDate(new Date(stats.latestAt), Formatter.DateMedium)
                                : qsTr("No readings yet")
                }
            }
        }

        ViewPlaceholder {
            enabled: !page.loading && page.types.length === 0 && page.errorText === ""
            text: qsTr("No measurement types yet.")
        }

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: page.loading && page.types.length === 0
        }

        VerticalScrollDecorator {}
    }
}
