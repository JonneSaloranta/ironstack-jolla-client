import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

// One measurement type's history, like the web's: BMI for body weight,
// statistics, the trend and every reading, which can be corrected or
// deleted. Your own types can be deactivated.
Page {
    id: page

    property var type
    property var readings: []
    property var profile: null
    property bool loading: false
    property string errorText: ""

    readonly property string unitSystem: settings.unitSystem
    readonly property var stats: Store.measurementStats(readings)
    readonly property real bmi: stats && profile && profile.show_bmi && Store.isBodyWeightType(type)
                                ? Store.bmi(stats.latest, profile.height) : NaN

    function shown(value) {
        return Store.formatMeasurement(value, type.unit_kind, unitSystem)
    }

    function bmiCategoryText(category) {
        switch (category) {
        case "underweight": return qsTr("Underweight")
        case "normal": return qsTr("Normal weight")
        case "overweight": return qsTr("Overweight")
        case "obese": return qsTr("Obese")
        }
        return ""
    }

    function load() {
        loading = true
        var found = []
        Store.fetchAll(api, "measurements/?page_size=100", function(results) {
            found = found.concat(results.filter(function(r) { return r.measurement_type === type.id }))
        }, function(ok, error) {
            loading = false
            errorText = ok ? "" : error
            if (ok)
                readings = found
        })
        if (Store.isBodyWeightType(type)) {
            api.request("GET", "profile/", null, function(ok, status, data) {
                if (ok)
                    profile = data
            })
        }
    }

    function write(method, path, body) {
        api.request(method, path, body, function(ok, status, data, error) {
            Store.measurementsChanged = true
            if (!ok)
                errorText = error
            load()
        })
    }

    function log() {
        var dialog = pageStack.push(Qt.resolvedUrl("MeasurementDialog.qml"), { type: type })
        dialog.accepted.connect(function() { write("POST", "measurements/", dialog.body()) })
    }

    function edit(reading) {
        var dialog = pageStack.push(Qt.resolvedUrl("MeasurementDialog.qml"), { type: type, reading: reading })
        dialog.accepted.connect(function() { write("PATCH", "measurements/" + reading.id + "/", dialog.body()) })
    }

    Component.onCompleted: load()

    RemorsePopup {
        id: remorse
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        // Newest first, like the web's table.
        model: page.readings.slice().sort(function(a, b) { return new Date(b.recorded_at) - new Date(a.recorded_at) })

        PullDownMenu {
            busy: page.loading
            MenuItem {
                visible: page.type.is_custom
                text: qsTr("Deactivate type")
                onClicked: remorse.execute(qsTr("Deactivating type"), function() {
                    api.request("DELETE", "measurement-types/" + page.type.id + "/", null, function(ok, status, data, error) {
                        if (!ok) {
                            page.errorText = error
                            return
                        }
                        Store.measurementsChanged = true
                        pageStack.pop()
                    })
                })
            }
            MenuItem {
                text: qsTr("Log reading")
                onClicked: page.log()
            }
        }

        header: Column {
            width: parent.width
            spacing: Theme.paddingSmall

            PageHeader {
                title: Store.contentName(page.type.name)
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }

            // The web's BMI card.
            Column {
                visible: !isNaN(page.bmi)
                width: parent.width
                SectionHeader {
                    text: qsTr("BMI")
                }
                DetailItem {
                    label: qsTr("BMI")
                    value: isNaN(page.bmi) ? "" : Store.formatNumber(page.bmi) + " - "
                                                  + page.bmiCategoryText(Store.bmiCategory(page.bmi))
                }
            }

            SectionHeader {
                visible: page.stats !== null
                text: qsTr("Statistics")
            }
            Column {
                visible: page.stats !== null
                width: parent.width
                DetailItem {
                    label: qsTr("Current")
                    value: page.stats ? page.shown(page.stats.latest) : ""
                }
                DetailItem {
                    label: qsTr("Change since first log")
                    value: page.stats ? (page.stats.change > 0 ? "+" : "") + page.shown(page.stats.change) : ""
                }
                DetailItem {
                    label: qsTr("Lowest")
                    value: page.stats ? page.shown(page.stats.min) : ""
                }
                DetailItem {
                    label: qsTr("Highest")
                    value: page.stats ? page.shown(page.stats.max) : ""
                }
                DetailItem {
                    label: qsTr("Average")
                    value: page.stats ? page.shown(page.stats.average) : ""
                }
                DetailItem {
                    label: qsTr("Entries logged")
                    value: page.stats ? page.stats.count : ""
                }
            }

            SectionHeader {
                visible: page.readings.length > 1
                text: qsTr("Trend")
            }
            LineChart {
                visible: page.readings.length > 1
                unit: Store.measurementUnit(page.type.unit_kind, page.unitSystem)
                points: page.readings.map(function(r) {
                    return { x: new Date(r.recorded_at).getTime(),
                             y: Store.measurementToDisplay(r.value, page.type.unit_kind, page.unitSystem) }
                })
            }

            SectionHeader {
                visible: page.readings.length > 0
                text: qsTr("Readings")
            }
        }

        delegate: ListItem {
            id: item
            contentHeight: Math.max(Theme.itemSizeSmall, row.height + 2 * Theme.paddingSmall)
            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Edit")
                    onClicked: page.edit(modelData)
                }
                MenuItem {
                    text: qsTr("Delete")
                    onClicked: {
                        var id = modelData.id
                        item.remorseDelete(function() { page.write("DELETE", "measurements/" + id + "/", null) })
                    }
                }
            }

            Column {
                id: row
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                Row {
                    width: parent.width
                    Label {
                        width: parent.width - valueLabel.width
                        truncationMode: TruncationMode.Fade
                        text: Format.formatDate(new Date(modelData.recorded_at), Formatter.DateMedium) + " "
                              + Format.formatDate(new Date(modelData.recorded_at), Formatter.TimeValue)
                    }
                    Label {
                        id: valueLabel
                        color: Theme.highlightColor
                        text: page.shown(modelData.value)
                    }
                }
                Label {
                    visible: text !== ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    text: modelData.notes || ""
                }
            }
        }

        ViewPlaceholder {
            enabled: !page.loading && page.readings.length === 0 && page.errorText === ""
            text: qsTr("No readings logged yet.")
        }

        VerticalScrollDecorator {}
    }
}
