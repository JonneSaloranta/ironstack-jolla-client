import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

// One of a trainer's clients, like the web's client page: the last 30
// days of training, their highlights, latest records, latest body
// measurements and the programs you've shared that they've imported.
Page {
    id: page

    property string username
    property var client: null
    property bool loading: false
    property string errorText: ""

    readonly property var summary: client ? client.training_summary : null
    readonly property var measured: client ? (client.measurements || []).filter(function(m) {
        return Store.present(m.latest_value)
    }) : []

    function load() {
        loading = true
        api.request("GET", "coaching/clients/" + encodeURIComponent(username) + "/", null,
                    function(ok, status, data, error) {
            loading = false
            errorText = ok ? "" : error
            if (ok)
                client = data
        })
    }

    Component.onCompleted: load()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            busy: page.loading
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.load()
            }
        }

        Column {
            id: column
            width: parent.width

            PageHeader {
                title: page.client ? page.client.client.display_name || page.username : page.username
                description: qsTr("Client")
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }

            SectionHeader {
                text: qsTr("Last 30 days")
            }
            Row {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                StatItem {
                    width: parent.width / 3
                    value: page.summary ? page.summary.session_count : "-"
                    label: qsTr("workouts")
                }
                StatItem {
                    width: parent.width / 3
                    value: page.summary ? Store.formatHoursMinutes(page.summary.total_duration_seconds) : "-"
                    label: qsTr("time (h:min)")
                }
                StatItem {
                    width: parent.width / 3
                    value: page.summary ? Math.round(Store.kgToDisplay(page.summary.total_volume, settings.unitSystem)) : "-"
                    label: qsTr("volume (%1)").arg(Store.weightUnit(settings.unitSystem))
                }
            }

            SectionHeader {
                visible: page.client !== null && (page.client.highlights || []).length > 0
                text: qsTr("Highlights")
            }
            Repeater {
                model: page.client ? page.client.highlights || [] : []
                delegate: DetailItem {
                    label: modelData.label
                    value: modelData.value
                }
            }

            SectionHeader {
                visible: page.measured.length > 0
                text: qsTr("Body measurements")
            }
            Repeater {
                model: page.measured
                delegate: DetailItem {
                    label: Store.shown(modelData)
                    value: Store.formatMeasurement(modelData.latest_value, modelData.unit_kind, settings.unitSystem)
                           + " · " + Format.formatDate(new Date(modelData.latest_recorded_at), Formatter.DateMedium)
                }
            }

            SectionHeader {
                visible: page.client !== null && (page.client.assigned_programs || []).length > 0
                text: qsTr("Your programs they use")
            }
            Repeater {
                model: page.client ? page.client.assigned_programs || [] : []
                delegate: DetailItem {
                    label: modelData.name
                    value: modelData.last_session_at
                           ? qsTr("Last trained %1").arg(Format.formatDate(new Date(modelData.last_session_at), Formatter.DateMedium))
                           : qsTr("Not trained yet")
                }
            }

            SectionHeader {
                visible: page.client !== null && (page.client.recent_records || []).length > 0
                text: qsTr("Latest records")
            }
            Repeater {
                model: page.client ? page.client.recent_records || [] : []
                delegate: RecordItem {
                    record: modelData
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
