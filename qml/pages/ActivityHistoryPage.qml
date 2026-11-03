import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

// One activity type's history, like the web's: the summary, the duration
// trend and every activity, which can be corrected or deleted. Your own
// types can be deactivated.
Page {
    id: page

    property var type
    property var activities: []
    property bool loading: false
    property string errorText: ""

    readonly property string unitSystem: settings.unitSystem
    readonly property var summary: Store.activitySummary(activities)

    function summaryText() {
        var parts = [qsTr("%n logged", "", summary.count),
                     qsTr("total duration %1").arg(Store.formatMinutes(summary.duration))]
        if (summary.distance !== null)
            parts.push(qsTr("total distance %1").arg(Store.formatDistance(summary.distance, unitSystem)))
        if (summary.calories !== null)
            parts.push(qsTr("total calories %1").arg(summary.calories))
        return parts.join(" · ")
    }

    function load() {
        loading = true
        var found = []
        Store.fetchAll(api, "activities/?page_size=100&activity_type=" + type.id, function(results) {
            found = found.concat(results)
        }, function(ok, error) {
            loading = false
            errorText = ok ? "" : error
            if (ok)
                activities = found
        })
    }

    function write(method, path, body) {
        api.request(method, path, body, function(ok, status, data, error) {
            Store.activitiesChanged = true
            if (!ok)
                errorText = error
            load()
        })
    }

    function log() {
        var dialog = pageStack.push(Qt.resolvedUrl("ActivityDialog.qml"), { type: type })
        dialog.accepted.connect(function() { write("POST", "activities/", dialog.body()) })
    }

    function edit(activity) {
        var dialog = pageStack.push(Qt.resolvedUrl("ActivityDialog.qml"), { type: type, activity: activity })
        dialog.accepted.connect(function() { write("PATCH", "activities/" + activity.id + "/", dialog.body()) })
    }

    Component.onCompleted: load()

    RemorsePopup {
        id: remorse
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: page.activities

        PullDownMenu {
            busy: page.loading
            MenuItem {
                visible: page.type.is_custom
                text: qsTr("Deactivate type")
                onClicked: remorse.execute(qsTr("Deactivating type"), function() {
                    api.request("DELETE", "activity-types/" + page.type.id + "/", null, function(ok, status, data, error) {
                        if (!ok) {
                            page.errorText = error
                            return
                        }
                        Store.activitiesChanged = true
                        pageStack.pop()
                    })
                })
            }
            MenuItem {
                text: qsTr("Log activity")
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
            Label {
                visible: page.summary.count > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: page.summaryText()
            }

            SectionHeader {
                visible: page.activities.length > 1
                text: qsTr("Duration trend")
            }
            LineChart {
                visible: page.activities.length > 1
                unit: qsTr("min")
                points: page.activities.map(function(a) {
                    return { x: Store.parseDate(a.date).getTime(), y: Store.parseDuration(a.duration) / 60 }
                })
            }

            SectionHeader {
                visible: page.activities.length > 0
                text: qsTr("Activities")
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
                        item.remorseDelete(function() { page.write("DELETE", "activities/" + id + "/", null) })
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
                        text: Format.formatDate(Store.parseDate(modelData.date), Formatter.DateMedium)
                              + (Store.present(modelData.start_time) ? " " + modelData.start_time.substring(0, 5) : "")
                    }
                    Label {
                        id: valueLabel
                        color: Theme.highlightColor
                        text: Store.formatMinutes(Store.parseDuration(modelData.duration))
                    }
                }
                Label {
                    visible: text !== ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    text: [Store.formatDistance(modelData.distance, page.unitSystem),
                           Store.present(modelData.calories) ? modelData.calories + " kcal" : "",
                           modelData.notes || ""].filter(function(part) { return part }).join(" · ")
                }
            }
        }

        ViewPlaceholder {
            enabled: !page.loading && page.activities.length === 0 && page.errorText === ""
            text: qsTr("No activities logged yet.")
        }

        VerticalScrollDecorator {}
    }
}
