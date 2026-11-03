import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/social.js" as Social

// The people you've blocked: they can't find you, send requests or
// message you. Unblocking doesn't make them a friend again.
Page {
    id: page

    property var blocks: []
    property bool loading: false
    property string errorText: ""

    function load(keepError) {
        loading = true
        api.request("GET", "social/blocks/", null, function(ok, status, data, error) {
            loading = false
            errorText = ok ? (keepError || "") : error
            if (ok)
                blocks = data || []
        })
    }

    Component.onCompleted: load()

    SilicaListView {
        id: list
        anchors.fill: parent
        model: page.blocks

        header: Column {
            width: list.width
            PageHeader {
                title: qsTr("Blocked users")
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }
        }

        delegate: ListItem {
            id: item
            readonly property var who: modelData
            contentHeight: Theme.itemSizeSmall
            onClicked: openMenu()
            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Unblock")
                    onClicked: {
                        var id = item.who.id
                        item.remorseAction(qsTr("Unblocking"), function() {
                            api.request("DELETE", "social/blocks/" + id + "/", null, function(ok, status, data, error) {
                                Social.changed = true
                                page.load(ok ? "" : error)
                            })
                        })
                    }
                }
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                truncationMode: TruncationMode.Fade
                text: item.who.username || ""
            }
        }

        ViewPlaceholder {
            enabled: !page.loading && page.blocks.length === 0 && page.errorText === ""
            text: qsTr("Nobody blocked")
        }
    }
}
