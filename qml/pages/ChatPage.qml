import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store
import "../js/social.js" as Social

// A conversation with a friend or a group, like the web's: the last 100
// messages, oldest first, and a field to write. Opening it marks it read.
// New messages are asked for every 10 seconds while it's on screen
// (`?after=`), as the API has no push.
Page {
    id: page

    // "friend" or "group"
    property string kind: "friend"
    property int targetId
    property string title: ""

    property var messages: []
    property bool loading: false
    property bool sending: false
    property string errorText: ""

    readonly property string path: kind === "group" ? "social/groups/" + targetId + "/messages/"
                                                    : "social/messages/" + targetId + "/"

    function atEnd() {
        return list.atYEnd || list.contentHeight <= list.height
    }

    function show(newer, scroll) {
        var follow = scroll || atEnd()
        var before = messages.length
        messages = Social.mergeMessages(messages, newer)
        if (follow && messages.length !== before)
            scrollTimer.restart()
    }

    function load() {
        loading = true
        Social.ensureMe(api, function() {
            api.request("GET", path, null, function(ok, status, data, error) {
                loading = false
                errorText = ok ? "" : error
                if (ok) {
                    show(data || [], true)
                    Social.changed = true
                }
            })
        })
    }

    function poll() {
        var after = Social.lastId(messages)
        api.request("GET", path + (after !== null ? "?after=" + after : ""), null, function(ok, status, data) {
            if (ok)
                show(data || [], false)
        })
    }

    function send() {
        var body = input.text.trim()
        if (!body || sending)
            return
        sending = true
        api.request("POST", path, { body: body }, function(ok, status, data, error) {
            sending = false
            errorText = ok ? "" : error
            if (ok) {
                input.text = ""
                show([data], true)
            }
        })
    }

    Component.onCompleted: load()

    // To the newest message once the list has laid out the new ones.
    Timer {
        id: scrollTimer
        interval: 0
        onTriggered: list.positionViewAtEnd()
    }

    Timer {
        interval: 10000
        repeat: true
        running: page.status === PageStatus.Active && Qt.application.active
        onTriggered: page.poll()
    }

    SilicaListView {
        id: list
        anchors.top: parent.top
        anchors.bottom: inputRow.top
        width: parent.width
        clip: true
        model: page.messages
        currentIndex: -1

        PullDownMenu {
            busy: page.loading
            MenuItem {
                visible: page.kind === "group"
                text: qsTr("Group info")
                onClicked: pageStack.push(Qt.resolvedUrl("GroupPage.qml"), { groupId: page.targetId })
            }
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.poll()
            }
        }

        header: Column {
            width: list.width
            PageHeader {
                title: page.title
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }
        }

        delegate: Column {
            id: bubble
            readonly property bool mine: modelData.sender && modelData.sender.username === Social.me
            width: list.width
            bottomPadding: Theme.paddingMedium

            Label {
                visible: Social.startsDay(page.messages, index)
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                topPadding: Theme.paddingMedium
                bottomPadding: Theme.paddingSmall
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: visible ? Format.formatDate(new Date(modelData.created_at), Formatter.DateMedium) : ""
            }
            Label {
                x: bubble.mine ? parent.width - width - Theme.horizontalPageMargin : Theme.horizontalPageMargin
                width: Math.min(implicitWidth, parent.width * 0.8)
                wrapMode: Text.Wrap
                color: bubble.mine ? Theme.highlightColor : Theme.primaryColor
                text: modelData.body
            }
            Label {
                x: bubble.mine ? parent.width - width - Theme.horizontalPageMargin : Theme.horizontalPageMargin
                font.pixelSize: Theme.fontSizeTiny
                color: Theme.secondaryColor
                text: (page.kind === "group" && !bubble.mine ? modelData.sender.username + " · " : "")
                      + Format.formatDate(new Date(modelData.created_at), Formatter.TimeValue)
            }
        }

        ViewPlaceholder {
            enabled: !page.loading && page.messages.length === 0 && page.errorText === ""
            text: qsTr("No messages yet")
            hintText: qsTr("Say hello below")
        }

        VerticalScrollDecorator {}
    }

    Row {
        id: inputRow
        anchors.bottom: parent.bottom
        width: parent.width
        TextArea {
            id: input
            width: parent.width - sendButton.width - Theme.horizontalPageMargin
            placeholderText: qsTr("Message")
            label: placeholderText
        }
        IconButton {
            id: sendButton
            anchors.verticalCenter: parent.verticalCenter
            enabled: input.text.trim() !== "" && !page.sending
            icon.source: "image://theme/icon-m-send"
            onClicked: page.send()
        }
    }
}
