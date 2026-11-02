import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

// Stretching history, like the web's: every session, which can be
// corrected (date, duration, notes) or deleted.
Page {
    id: page

    property var sessions: []
    property bool loading: false
    property string errorText: ""

    function statusText(status) {
        if (status === "abandoned")
            return qsTr("Abandoned")
        if (status === "in_progress")
            return qsTr("In progress")
        return ""
    }

    function load(keepError) {
        loading = true
        var found = []
        Store.fetchAll(api, "stretch-sessions/?page_size=100", function(results) {
            found = found.concat(results)
        }, function(ok, error) {
            loading = false
            errorText = ok ? (keepError || "") : error
            if (ok)
                sessions = found
        })
    }

    function write(method, path, body) {
        api.request(method, path, body, function(ok, status, data, error) {
            Store.stretchingChanged = true
            load(ok ? "" : error)
        })
    }

    Component.onCompleted: load()

    SilicaListView {
        id: list
        anchors.fill: parent
        model: page.sessions

        header: Column {
            width: parent.width
            PageHeader {
                title: qsTr("History")
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }
        }

        delegate: ListItem {
            id: item
            contentHeight: Math.max(Theme.itemSizeSmall, row.height + 2 * Theme.paddingSmall)
            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Edit")
                    onClicked: {
                        var session = modelData
                        var dialog = pageStack.push(Qt.resolvedUrl("StretchSessionDialog.qml"), { session: session })
                        dialog.accepted.connect(function() {
                            page.write("PATCH", "stretch-sessions/" + session.id + "/", dialog.body())
                        })
                    }
                }
                MenuItem {
                    text: qsTr("Delete")
                    onClicked: {
                        var id = modelData.id
                        item.remorseDelete(function() { page.write("DELETE", "stretch-sessions/" + id + "/", null) })
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
                        text: modelData.name ? Store.contentName(modelData.name) : qsTr("Stretching")
                    }
                    Label {
                        id: valueLabel
                        color: Theme.highlightColor
                        text: Store.formatMinutes(Store.parseDuration(modelData.duration))
                    }
                }
                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    text: [Format.formatDate(Store.parseDate(modelData.date), Formatter.DateMedium),
                           page.statusText(modelData.status),
                           modelData.after_workout ? qsTr("Cool-down") : "",
                           modelData.notes || ""].filter(function(p) { return p }).join(" · ")
                }
            }
        }

        ViewPlaceholder {
            enabled: !page.loading && page.sessions.length === 0 && page.errorText === ""
            text: qsTr("No stretching sessions yet.")
        }

        VerticalScrollDecorator {}
    }
}
