import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store
import "../js/social.js" as Social

// Friends and groups, like the web's: friend requests and group invites
// to answer, then every friend and group with its unread messages. A tap
// opens the conversation; a friend's menu mutes, removes or blocks them.
// Add a friend, start or join a group, and see who's blocked from the
// pull-down. Needs an API key with the "Friends and groups" area.
Page {
    id: page
    objectName: "socialPage"

    property var friends: []
    property var groups: []
    property var incoming: []
    property var outgoing: []
    property var invites: []
    property bool loading: false
    property string errorText: ""

    function load(keepError) {
        loading = true
        var pending = 5
        var failure = keepError || ""
        var found = { conversations: null, friends: [], requests: [], invites: [] }
        function settle(ok, error) {
            if (!ok && error)
                failure = error
            if (--pending > 0)
                return
            loading = false
            errorText = failure
            if (!found.conversations)
                return
            // conversations/ has the unread counts, friends/ the mute.
            var muted = {}
            found.friends.forEach(function(f) { muted[f.id] = f.muted })
            friends = (found.conversations.friends || []).map(function(f) {
                return { id: f.id, username: f.username, unread: f.unread || 0, muted: !!muted[f.id] }
            }).sort(function(a, b) { return b.unread - a.unread || a.username.localeCompare(b.username) })
            groups = (found.conversations.groups || []).slice().sort(function(a, b) {
                return (b.unread || 0) - (a.unread || 0) || a.name.localeCompare(b.name)
            })
            var split = Social.requestsFor(found.requests, Social.me)
            incoming = split.incoming
            outgoing = split.outgoing
            invites = found.invites
        }
        Social.me = ""
        Social.ensureMe(api, function(ok, error) {
            settle(ok, error)
            api.request("GET", "social/friend-requests/", null, function(ok2, status, data, error2) {
                if (ok2)
                    found.requests = data || []
                settle(ok2, error2)
            })
        })
        api.request("GET", "social/conversations/", null, function(ok, status, data, error) {
            if (ok)
                found.conversations = data
            settle(ok, error)
        })
        api.request("GET", "social/friends/", null, function(ok, status, data, error) {
            if (ok)
                found.friends = data || []
            settle(ok, error)
        })
        api.request("GET", "social/group-invites/", null, function(ok, status, data, error) {
            if (ok)
                found.invites = data || []
            settle(ok, error)
        })
    }

    // A write, then everything again; the server's message on a broken rule.
    function act(method, path, body) {
        loading = true
        api.request(method, path, body, function(ok, status, data, error) {
            load(ok ? "" : error)
        })
    }

    function openChat(kind, id, title) {
        pageStack.push(Qt.resolvedUrl("ChatPage.qml"), { kind: kind, targetId: id, title: title })
    }

    Component.onCompleted: load()
    onStatusChanged: {
        if (status === PageStatus.Active && Social.changed) {
            Social.changed = false
            load()
        }
    }

    RemorsePopup {
        id: remorse
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            busy: page.loading
            MenuItem {
                text: qsTr("Blocked users")
                onClicked: pageStack.push(Qt.resolvedUrl("BlockedUsersPage.qml"))
            }
            MenuItem {
                text: qsTr("Join a group")
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("NameDialog.qml"),
                                                { title: qsTr("Join a group"), label: qsTr("Invite code") })
                    dialog.accepted.connect(function() {
                        page.act("POST", "social/groups/join/", { code: dialog.name })
                    })
                }
            }
            MenuItem {
                text: qsTr("New group")
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("GroupEditDialog.qml"))
                    dialog.accepted.connect(function() {
                        page.act("POST", "social/groups/", dialog.body())
                    })
                }
            }
            MenuItem {
                text: qsTr("Add a friend")
                onClicked: pageStack.push(Qt.resolvedUrl("UserSearchPage.qml"))
            }
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.load()
            }
        }

        Column {
            id: column
            width: parent.width

            PageHeader {
                title: qsTr("Friends and groups")
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }

            SectionHeader {
                visible: page.incoming.length > 0 || page.invites.length > 0
                text: qsTr("Waiting for your answer")
            }
            Repeater {
                model: page.incoming
                delegate: ListItem {
                    id: requestItem
                    contentHeight: Theme.itemSizeSmall
                    onClicked: openMenu()
                    menu: ContextMenu {
                        MenuItem {
                            text: qsTr("Accept")
                            onClicked: page.act("POST", "social/friend-requests/" + modelData.id + "/accept/", null)
                        }
                        MenuItem {
                            text: qsTr("Decline")
                            onClicked: page.act("POST", "social/friend-requests/" + modelData.id + "/decline/", null)
                        }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        truncationMode: TruncationMode.Fade
                        color: Theme.highlightColor
                        text: qsTr("%1 wants to be friends").arg(modelData.from_user.username)
                    }
                }
            }
            Repeater {
                model: page.invites
                delegate: ListItem {
                    contentHeight: Theme.itemSizeSmall
                    onClicked: openMenu()
                    menu: ContextMenu {
                        MenuItem {
                            text: qsTr("Join")
                            onClicked: page.act("POST", "social/group-invites/" + modelData.id + "/accept/", null)
                        }
                        MenuItem {
                            text: qsTr("Decline")
                            onClicked: page.act("POST", "social/group-invites/" + modelData.id + "/decline/", null)
                        }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        truncationMode: TruncationMode.Fade
                        color: Theme.highlightColor
                        text: qsTr("%1 invites you to %2").arg(modelData.invited_by.username).arg(modelData.group.name)
                    }
                }
            }

            SectionHeader {
                text: qsTr("Friends")
            }
            Repeater {
                model: page.friends
                delegate: ListItem {
                    id: friendItem
                    contentHeight: Theme.itemSizeSmall
                    onClicked: page.openChat("friend", modelData.id, modelData.username)
                    menu: ContextMenu {
                        MenuItem {
                            text: modelData.muted ? qsTr("Unmute notifications") : qsTr("Mute notifications")
                            onClicked: page.act("POST", "social/friends/" + modelData.id
                                                + (modelData.muted ? "/unmute/" : "/mute/"), null)
                        }
                        MenuItem {
                            text: qsTr("Remove friend")
                            onClicked: {
                                var id = modelData.id
                                friendItem.remorseAction(qsTr("Removing friend"), function() {
                                    page.act("DELETE", "social/friends/" + id + "/", null)
                                })
                            }
                        }
                        MenuItem {
                            text: qsTr("Block")
                            onClicked: {
                                var id = modelData.id
                                friendItem.remorseAction(qsTr("Blocking"), function() {
                                    page.act("POST", "social/blocks/", { user: id })
                                })
                            }
                        }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin - unreadLabel.width
                        truncationMode: TruncationMode.Fade
                        text: modelData.username + (modelData.muted ? " · " + qsTr("muted") : "")
                    }
                    Label {
                        id: unreadLabel
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.horizontalPageMargin
                        color: Theme.highlightColor
                        text: modelData.unread ? qsTr("%n new", "", modelData.unread) : ""
                    }
                }
            }
            Label {
                visible: !page.loading && page.friends.length === 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                text: qsTr("No friends yet. Pull down to add one by their username.")
            }
            Repeater {
                model: page.outgoing
                delegate: Label {
                    x: Theme.horizontalPageMargin
                    width: page.width - 2 * Theme.horizontalPageMargin
                    topPadding: Theme.paddingSmall
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                    text: qsTr("Request sent to %1").arg(modelData.to_user.username)
                }
            }

            SectionHeader {
                text: qsTr("Groups")
            }
            Repeater {
                model: page.groups
                delegate: ListItem {
                    contentHeight: Theme.itemSizeSmall
                    onClicked: page.openChat("group", modelData.id, modelData.name)
                    menu: ContextMenu {
                        MenuItem {
                            text: qsTr("Group info")
                            onClicked: pageStack.push(Qt.resolvedUrl("GroupPage.qml"), { groupId: modelData.id })
                        }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin - groupUnread.width
                        truncationMode: TruncationMode.Fade
                        text: modelData.name
                    }
                    Label {
                        id: groupUnread
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.horizontalPageMargin
                        color: Theme.highlightColor
                        text: modelData.unread ? qsTr("%n new", "", modelData.unread) : ""
                    }
                }
            }
            Label {
                visible: !page.loading && page.groups.length === 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                text: qsTr("No groups yet. Pull down to start one or join with an invite code.")
            }
        }

        VerticalScrollDecorator {}
    }
}
