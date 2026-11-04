import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../js/assistant.js" as Assistant
import "../js/nutrition.js" as Nutrition

// One conversation with the AI assistant, like the web's: your messages
// and its replies, which are written on the server - the page asks every
// 1.5 s how far a reply has got and what it's doing. A diet plan,
// program or recipe it suggests is a card: "Create" makes it (a plan or
// program inactive, to review like any other), "Dismiss" doesn't.
Page {
    id: page

    // -1 for a new conversation, started by the first message.
    property int conversationId: -1
    property string title: ""
    // The conversation list, told when one is started or a plan created.
    property var listPage: null

    property var messages: []
    property bool loading: false
    property bool sending: false
    property string errorText: ""

    readonly property var working: Assistant.workingMessage(messages)

    function load() {
        if (conversationId < 0)
            return
        loading = true
        api.request("GET", "assistant/conversations/" + conversationId + "/", null, function(ok, status, data, error) {
            loading = false
            errorText = ok ? "" : error
            if (ok) {
                title = data.title || title
                messages = data.messages || []
                scrollTimer.restart()
            }
        })
    }

    function poll() {
        var message = working
        if (!message)
            return
        api.request("GET", "assistant/messages/" + message.id + "/", null, function(ok, status, data) {
            if (ok) {
                var atEnd = list.atYEnd
                messages = Assistant.replaceMessage(messages, data)
                if (atEnd)
                    scrollTimer.restart()
            }
        })
    }

    function send() {
        var text = input.text.trim()
        if (!text || sending || working)
            return
        sending = true
        errorText = ""
        if (conversationId < 0) {
            api.request("POST", "assistant/conversations/", { text: text }, function(ok, status, data, error) {
                sending = false
                if (!ok)
                    return errorText = error
                input.text = ""
                conversationId = data.id
                title = data.title || ""
                messages = data.messages || []
                if (listPage)
                    listPage.conversationsChanged = true
                scrollTimer.restart()
            })
            return
        }
        api.request("POST", "assistant/conversations/" + conversationId + "/messages/", { text: text },
                    function(ok, status, data, error) {
            sending = false
            if (!ok)
                return errorText = error
            input.text = ""
            // The reply bubble; the question is in the conversation.
            load()
        })
    }

    function proposal(id, action) {
        api.request("POST", "assistant/proposals/" + id + "/" + action + "/", null, function(ok, status, data, error) {
            errorText = ok ? "" : error
            load()
            if (!ok || action !== "accept")
                return
            if (data.kind === "program") {
                pageStack.push(Qt.resolvedUrl("ProgramPage.qml"), { programId: data.created_id })
            } else if (data.kind === "recipe") {
                // New foods may have come with it.
                Nutrition.changed = true
                pageStack.push(Qt.resolvedUrl("RecipePage.qml"), { recipeId: data.created_id })
            } else {
                pageStack.push(Qt.resolvedUrl("DietPlanPage.qml"), { planId: data.created_id })
            }
        })
    }

    function kindText(kind) {
        return kind === "program" ? qsTr("Program") : kind === "recipe" ? qsTr("Recipe") : qsTr("Diet plan")
    }

    function recipeText(payload) {
        if (!payload || !payload.per_serving)
            return ""
        var per = payload.per_serving
        return qsTr("Makes %n serving(s)", "", payload.servings) + "\n"
                + qsTr("Per serving about %1 kcal · protein %2 g · carbs %3 g · fat %4 g")
                  .arg(per.calories).arg(Math.round(per.protein_grams)).arg(Math.round(per.carbohydrate_grams))
                  .arg(Math.round(per.fat_grams))
    }

    function activityText(m) {
        if (m.activity)
            return m.activity
        return m.status === "pending" ? qsTr("Waiting...") : qsTr("Writing...")
    }

    Component.onCompleted: load()

    Timer {
        id: scrollTimer
        interval: 0
        onTriggered: list.positionViewAtEnd()
    }

    Timer {
        interval: 1500
        repeat: true
        running: page.working !== null && Qt.application.active
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
            visible: page.conversationId >= 0
            busy: page.loading || page.working !== null
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.load()
            }
        }

        header: Column {
            width: list.width
            PageHeader {
                title: page.title || qsTr("New conversation")
            }
            ErrorBanner {
                text: page.errorText
            }
        }

        delegate: Column {
            id: bubble
            readonly property bool mine: modelData.role === "user"
            width: list.width
            bottomPadding: Theme.paddingLarge
            spacing: Theme.paddingSmall

            Label {
                visible: text !== ""
                x: bubble.mine ? Theme.horizontalPageMargin * 3 : Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 4
                horizontalAlignment: bubble.mine ? Text.AlignRight : Text.AlignLeft
                wrapMode: Text.Wrap
                textFormat: bubble.mine ? Text.PlainText : Text.StyledText
                color: bubble.mine ? Theme.highlightColor : Theme.primaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: bubble.mine ? modelData.text : Assistant.styled(modelData.text)
            }
            // What it's doing while it writes, or why it failed.
            Label {
                visible: Assistant.isWorking(modelData) || modelData.status === "error"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: modelData.status === "error" ? Theme.errorColor : Theme.secondaryHighlightColor
                text: modelData.status === "error" ? (modelData.error || qsTr("The reply failed."))
                                                   : page.activityText(modelData)
            }
            Repeater {
                model: modelData.proposals || []
                delegate: Column {
                    x: Theme.horizontalPageMargin
                    width: bubble.width - 2 * Theme.horizontalPageMargin
                    spacing: Theme.paddingSmall
                    Label {
                        width: parent.width
                        wrapMode: Text.Wrap
                        color: Theme.highlightColor
                        text: page.kindText(modelData.kind) + ": " + modelData.title
                    }
                    // A recipe's servings and calories, as on the web's card.
                    Label {
                        visible: modelData.kind === "recipe" && text.length > 0
                        width: parent.width
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryHighlightColor
                        text: page.recipeText(modelData.payload)
                    }
                    Label {
                        visible: !Assistant.isOpen(modelData)
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryColor
                        text: modelData.status === "accepted" ? qsTr("Created") : qsTr("Dismissed")
                    }
                    ButtonLayout {
                        visible: Assistant.isOpen(modelData)
                        Button {
                            text: qsTr("Create")
                            onClicked: page.proposal(modelData.id, "accept")
                        }
                        Button {
                            text: qsTr("Dismiss")
                            onClicked: page.proposal(modelData.id, "dismiss")
                        }
                    }
                }
            }
        }

        ViewPlaceholder {
            enabled: page.conversationId < 0 && page.messages.length === 0
            text: qsTr("Ask about your training or food")
            hintText: qsTr("For example: make me a 3-day program, or how is my weight trending?")
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
            placeholderText: page.working ? qsTr("Wait for the reply") : qsTr("Message")
            label: qsTr("Message")
        }
        IconButton {
            id: sendButton
            anchors.verticalCenter: parent.verticalCenter
            enabled: input.text.trim() !== "" && !page.sending && page.working === null
            icon.source: "image://theme/icon-m-send"
            onClicked: page.send()
        }
    }
}
