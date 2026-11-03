import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../js/social.js" as Social

// A group, like the web's group page: its description, members and their
// roles, and what your role allows - invite a friend, the invite code
// (owner and admins), change roles, hand over ownership and delete it
// (owner). Anyone can mute its notifications or leave. Every rule is the
// server's; a broken one shows its message.
Page {
    id: page

    property int groupId
    property var group: null
    property var members: []
    property var friends: []
    property bool loading: false
    property string errorText: ""

    readonly property string role: group ? group.role : ""
    readonly property bool manager: Social.canManage(role)
    readonly property bool owner: role === "owner"

    function roleText(r) {
        if (r === "owner")
            return qsTr("Owner")
        if (r === "admin")
            return qsTr("Admin")
        return qsTr("Member")
    }

    function load(keepError) {
        loading = true
        var pending = 3
        var failure = keepError || ""
        function settle(ok, error) {
            if (!ok && error)
                failure = error
            if (--pending === 0) {
                loading = false
                errorText = failure
            }
        }
        Social.ensureMe(api, function() {})
        api.request("GET", "social/groups/" + groupId + "/", null, function(ok, status, data, error) {
            if (ok)
                group = data
            settle(ok, error)
        })
        api.request("GET", "social/groups/" + groupId + "/members/", null, function(ok, status, data, error) {
            if (ok)
                members = data || []
            settle(ok, error)
        })
        api.request("GET", "social/friends/", null, function(ok, status, data, error) {
            if (ok)
                friends = data || []
            settle(ok, error)
        })
    }

    function act(method, path, body, after) {
        loading = true
        api.request(method, path, body, function(ok, status, data, error) {
            Social.changed = true
            if (ok && after)
                return after(data)
            load(ok ? "" : error)
        })
    }

    // Friends who aren't members yet, to invite.
    function invitable() {
        var inGroup = {}
        members.forEach(function(m) { inGroup[m.user.id] = true })
        return friends.filter(function(f) { return !inGroup[f.id] })
    }

    function invite() {
        var dialog = pageStack.push(Qt.resolvedUrl("FriendPickerDialog.qml"), {
            title: qsTr("Invite a friend"), friends: invitable()
        })
        dialog.accepted.connect(function() {
            act("POST", "social/groups/" + groupId + "/invites/", { user: dialog.picked.id }, function() {
                load(qsTr("Invited %1.").arg(dialog.picked.username))
            })
        })
    }

    function transfer() {
        var others = members.filter(function(m) { return m.role !== "owner" }).map(function(m) { return m.user })
        var dialog = pageStack.push(Qt.resolvedUrl("FriendPickerDialog.qml"), {
            title: qsTr("New owner"), friends: others
        })
        dialog.accepted.connect(function() {
            act("POST", "social/groups/" + groupId + "/transfer/", { user: dialog.picked.id })
        })
    }

    Component.onCompleted: load()

    RemorsePopup {
        id: remorse
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: page.members

        PullDownMenu {
            busy: page.loading
            MenuItem {
                visible: page.owner
                text: qsTr("Delete group")
                onClicked: remorse.execute(qsTr("Deleting group"), function() {
                    page.act("DELETE", "social/groups/" + page.groupId + "/", null, function() {
                        pageStack.pop(pageStack.find(function(p) { return p.objectName === "socialPage" }) || null)
                    })
                })
            }
            MenuItem {
                visible: !page.owner && page.group !== null
                text: qsTr("Leave group")
                onClicked: remorse.execute(qsTr("Leaving group"), function() {
                    page.act("POST", "social/groups/" + page.groupId + "/leave/", null, function() {
                        pageStack.pop(pageStack.find(function(p) { return p.objectName === "socialPage" }) || null)
                    })
                })
            }
            MenuItem {
                visible: page.owner && page.members.length > 1
                text: qsTr("Hand over ownership")
                onClicked: page.transfer()
            }
            MenuItem {
                visible: page.manager
                text: qsTr("Edit")
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("GroupEditDialog.qml"), { group: page.group })
                    dialog.accepted.connect(function() {
                        page.act("PATCH", "social/groups/" + page.groupId + "/", dialog.body())
                    })
                }
            }
            MenuItem {
                visible: page.group !== null
                text: page.group && page.group.notifications_muted ? qsTr("Unmute notifications")
                                                                    : qsTr("Mute notifications")
                onClicked: page.act("POST", "social/groups/" + page.groupId + "/mute/",
                                    { muted: !page.group.notifications_muted })
            }
            MenuItem {
                visible: page.group !== null
                enabled: page.invitable().length > 0
                text: qsTr("Invite a friend")
                onClicked: page.invite()
            }
        }

        header: Column {
            width: list.width
            PageHeader {
                title: page.group ? page.group.name : ""
                description: page.group ? page.roleText(page.role) + " · "
                                          + qsTr("%n member(s)", "", page.group.member_count) : ""
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }
            Label {
                visible: text !== ""
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                color: Theme.highlightColor
                text: page.group ? page.group.description || "" : ""
            }

            // The invite code: anyone with it can join, while it's on.
            SectionHeader {
                visible: page.manager
                text: qsTr("Invite code")
            }
            TextSwitch {
                visible: page.manager
                text: qsTr("Anyone with the code can join")
                checked: page.group ? page.group.invite_enabled : false
                automaticCheck: false
                onClicked: page.act("POST", "social/groups/" + page.groupId + "/invite-link/", { enabled: !checked })
            }
            DetailItem {
                visible: page.manager && page.group !== null && page.group.invite_enabled && !!page.group.invite_code
                label: qsTr("Code")
                value: page.group && page.group.invite_code ? page.group.invite_code : ""
            }
            Button {
                visible: page.manager && page.group !== null && page.group.invite_enabled
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("New code")
                onClicked: page.act("POST", "social/groups/" + page.groupId + "/invite-link/", { regenerate: true })
            }

            SectionHeader {
                text: qsTr("Members")
            }
        }

        delegate: ListItem {
            id: memberItem
            readonly property bool self: modelData.user.username === Social.me
            // The owner manages everyone else; an admin plain members.
            readonly property bool manageable: !self && modelData.role !== "owner"
                                               && (page.owner || (page.manager && modelData.role === "member"))
            contentHeight: Theme.itemSizeSmall
            menu: manageable ? memberMenu : null
            onClicked: {
                if (manageable)
                    openMenu()
            }
            Component {
                id: memberMenu
                ContextMenu {
                    MenuItem {
                        visible: page.owner
                        text: modelData.role === "admin" ? qsTr("Make a member") : qsTr("Make an admin")
                        onClicked: page.act("PATCH", "social/groups/" + page.groupId + "/members/" + modelData.user.id + "/",
                                            { role: modelData.role === "admin" ? "member" : "admin" })
                    }
                    MenuItem {
                        text: qsTr("Remove from group")
                        onClicked: {
                            var id = modelData.user.id
                            memberItem.remorseAction(qsTr("Removing"), function() {
                                page.act("DELETE", "social/groups/" + page.groupId + "/members/" + id + "/", null)
                            })
                        }
                    }
                }
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin - roleLabel.width
                truncationMode: TruncationMode.Fade
                text: modelData.user.username + (memberItem.self ? " (" + qsTr("you") + ")" : "")
            }
            Label {
                id: roleLabel
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                color: Theme.secondaryHighlightColor
                text: page.roleText(modelData.role)
            }
        }

        VerticalScrollDecorator {}
    }
}
