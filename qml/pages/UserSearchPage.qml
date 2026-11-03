import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/social.js" as Social

// Find people to befriend by username, like the web's search: at most 20,
// never friends or anyone blocked. A tap sends a friend request (or
// accepts theirs, if they asked first).
Page {
    id: page

    property var results: []
    property var sent: ({})
    property bool loading: false
    property bool searched: false
    property string errorText: ""

    function search(text) {
        var term = text.trim()
        if (!term)
            return
        loading = true
        api.request("GET", "social/users/?search=" + encodeURIComponent(term), null, function(ok, status, data, error) {
            loading = false
            searched = true
            errorText = ok ? "" : error
            results = ok ? data || [] : []
        })
    }

    function request(user) {
        api.request("POST", "social/friend-requests/", { user: user.id }, function(ok, status, data, error) {
            errorText = ok ? "" : error
            if (ok) {
                var done = {}
                for (var id in sent)
                    done[id] = sent[id]
                done[user.id] = true
                sent = done
                Social.changed = true
            }
        })
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: page.results
        currentIndex: -1

        header: Column {
            width: list.width
            PageHeader {
                title: qsTr("Add a friend")
            }
            ErrorBanner {
                text: page.errorText
            }
            SearchField {
                width: parent.width
                placeholderText: qsTr("Username")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                EnterKey.iconSource: "image://theme/icon-m-search"
                EnterKey.onClicked: {
                    focus = false
                    page.search(text)
                }
            }
        }

        delegate: ListItem {
            contentHeight: Theme.itemSizeSmall
            enabled: !page.sent[modelData.id]
            onClicked: page.request(modelData)
            Label {
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin - stateLabel.width
                truncationMode: TruncationMode.Fade
                text: modelData.username
            }
            Label {
                id: stateLabel
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                color: Theme.highlightColor
                text: page.sent[modelData.id] ? qsTr("Request sent") : qsTr("Send request")
            }
        }

        ViewPlaceholder {
            enabled: page.searched && !page.loading && page.results.length === 0 && page.errorText === ""
            text: qsTr("Nobody found")
            hintText: qsTr("Friends and people who allow friend requests are found by their username.")
        }

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: page.loading
        }
    }
}
