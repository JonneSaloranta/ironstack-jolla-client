import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"

// The AI assistant, like the web's: what turning it on means for your data
// (shown before you do), then your conversations. It reads your data only
// while answering and never changes anything - a plan it suggests is made
// only if you choose. Its own Anthropic key is set on the IronStack web.
// Needs an API key with the "AI assistant" area.
Page {
    id: page

    // assistant/: on, available, why not, model, today's allowance.
    property var info: null
    property var conversations: []
    property bool loading: false
    property string errorText: ""

    readonly property bool enabled: info !== null && info.enabled

    function load(keepError) {
        loading = true
        var pending = 2
        var failure = keepError || ""
        function settle(ok, error) {
            if (!ok && error)
                failure = error
            if (--pending === 0) {
                loading = false
                errorText = failure
            }
        }
        api.request("GET", "assistant/", null, function(ok, status, data, error) {
            if (ok)
                page.info = data
            settle(ok, error)
        })
        api.request("GET", "assistant/conversations/", null, function(ok, status, data, error) {
            if (ok)
                conversations = data || []
            settle(ok, error)
        })
    }

    function act(path) {
        loading = true
        api.request("POST", path, null, function(ok, status, data, error) {
            load(ok ? "" : error)
        })
    }

    Component.onCompleted: load()
    onStatusChanged: {
        if (status === PageStatus.Active && conversationsChanged) {
            conversationsChanged = false
            load()
        }
    }
    // A conversation was started or deleted on its page.
    property bool conversationsChanged: false

    RemorsePopup {
        id: remorse
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: page.enabled ? page.conversations : []

        PullDownMenu {
            busy: page.loading
            MenuItem {
                visible: page.enabled
                text: qsTr("Turn off")
                onClicked: remorse.execute(qsTr("Turning off the assistant"), function() { page.act("assistant/disable/") })
            }
            MenuItem {
                visible: page.info !== null
                text: qsTr("Assistant settings")
                onClicked: pageStack.push(Qt.resolvedUrl("AssistantSettingsPage.qml"), { info: page.info })
            }
            MenuItem {
                visible: page.enabled && page.info.available
                text: qsTr("New conversation")
                onClicked: pageStack.push(Qt.resolvedUrl("AssistantChatPage.qml"), { listPage: page })
            }
        }

        header: Column {
            width: list.width
            PageHeader {
                title: qsTr("AI assistant")
                description: page.info && page.info.model ? page.info.model : ""
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }

            // Not available: why (no model for this account, say).
            Label {
                visible: page.info !== null && !page.info.available
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                color: Theme.highlightColor
                text: page.info ? page.info.reason + " " + qsTr("Your own key is added on the IronStack web, under Profile > AI assistant.") : ""
            }

            // Before it's on: what that means, then the switch.
            Column {
                visible: page.info !== null && !page.enabled
                width: parent.width
                spacing: Theme.paddingSmall
                SectionHeader {
                    text: qsTr("Before you turn it on")
                }
                Repeater {
                    model: [
                        page.info && page.info.provider === "ollama"
                        ? qsTr("Your messages, and the training and nutrition data the assistant looks up to answer them, are sent to an AI model this instance runs on its own server.")
                        : qsTr("Your messages, and the training and nutrition data the assistant looks up to answer them, are sent to Anthropic (the maker of Claude) to generate replies."),
                        qsTr("It only reads your own data, and only while it's answering you. It can't change anything: plans it suggests are created only if you choose to."),
                        qsTr("You choose what it may read - body measurements, food diary and more - on its settings page."),
                        qsTr("Replies can be wrong. It isn't a doctor or a dietitian - check anything important with a professional."),
                        qsTr("You can turn it off, and delete your conversations, at any time.")
                    ]
                    delegate: Label {
                        x: Theme.horizontalPageMargin
                        width: page.width - 2 * Theme.horizontalPageMargin
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryHighlightColor
                        text: "• " + modelData
                    }
                }
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    enabled: !page.loading
                    text: qsTr("Turn on")
                    onClicked: page.act("assistant/enable/")
                }
            }

            DetailItem {
                // Null - no limit - arrives as undefined.
                visible: page.enabled && page.info.daily_limit > 0
                label: qsTr("Left today")
                value: visible
                       ? qsTr("%1 of %2 tokens").arg(page.info.tokens_remaining).arg(page.info.daily_limit) : ""
            }
            SectionHeader {
                visible: page.enabled
                text: qsTr("Conversations")
            }
        }

        delegate: ListItem {
            id: item
            contentHeight: Math.max(Theme.itemSizeSmall, textColumn.height + 2 * Theme.paddingSmall)
            onClicked: pageStack.push(Qt.resolvedUrl("AssistantChatPage.qml"),
                                      { conversationId: modelData.id, title: modelData.title, listPage: page })
            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Delete")
                    onClicked: {
                        var id = modelData.id
                        item.remorseDelete(function() {
                            api.request("DELETE", "assistant/conversations/" + id + "/", null,
                                        function(ok, status, data, error) { page.load(ok ? "" : error) })
                        })
                    }
                }
            }
            Column {
                id: textColumn
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    text: modelData.title || qsTr("Conversation")
                }
                Label {
                    width: parent.width
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    text: Format.formatDate(new Date(modelData.updated_at), Formatter.TimepointRelative)
                }
            }
        }

        ViewPlaceholder {
            enabled: page.enabled && !page.loading && page.conversations.length === 0 && page.errorText === ""
            text: qsTr("No conversations yet")
            hintText: page.info && page.info.available ? qsTr("Pull down to ask something") : ""
        }

        VerticalScrollDecorator {}
    }
}
