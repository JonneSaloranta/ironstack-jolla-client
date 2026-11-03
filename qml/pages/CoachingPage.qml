import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../js/social.js" as Social

// Coaching, like the web's: your coaches and the plans they've shared
// (import a copy to use it), requests waiting for an answer, and - for a
// personal trainer - their clients. Ask a trainer from the pull-down.
// Being a trainer is switched on in the IronStack web's profile. Needs an
// API key with the "Coaching" area.
Page {
    id: page

    property var coaches: []
    property var clients: []
    property var incoming: []
    property var outgoing: []
    property var sharedPrograms: []
    property var sharedPlans: []
    property bool loading: false
    property string errorText: ""

    function coachName(id) {
        var match = coaches.filter(function(r) { return r.coach.id === id })[0]
        return match ? match.coach.display_name || match.coach.username : ""
    }

    function load(keepError) {
        loading = true
        var pending = 5
        var failure = keepError || ""
        function settle(ok, error) {
            if (!ok && error)
                failure = error
            if (--pending === 0) {
                loading = false
                errorText = failure
            }
        }
        Social.ensureMe(api, function(ok, error) {
            api.request("GET", "coaching/requests/", null, function(ok2, status, data, error2) {
                if (ok2) {
                    var mine = data || []
                    incoming = mine.filter(function(r) { return r.coach.username === Social.me })
                    outgoing = mine.filter(function(r) { return r.coach.username !== Social.me })
                }
                settle(ok2, error2)
            })
        })
        api.request("GET", "coaching/coaches/", null, function(ok, status, data, error) {
            if (ok)
                coaches = data || []
            settle(ok, error)
        })
        api.request("GET", "coaching/clients/", null, function(ok, status, data, error) {
            if (ok)
                clients = data || []
            settle(ok, error)
        })
        api.request("GET", "coaching/shared/", null, function(ok, status, data, error) {
            if (ok) {
                sharedPrograms = (data && data.programs) || []
                sharedPlans = (data && data.diet_plans) || []
            }
            settle(ok, error)
        })
        settle(true, "")
    }

    function act(method, path, body) {
        loading = true
        api.request(method, path, body, function(ok, status, data, error) {
            load(ok ? "" : error)
        })
    }

    // A copy of a shared plan of your own, opened once it's made.
    function importPlan(kind, id) {
        loading = true
        api.request("POST", "coaching/shared/" + kind + "/" + id + "/import/", null, function(ok, status, data, error) {
            load(ok ? "" : error)
            if (!ok)
                return
            if (kind === "programs")
                pageStack.push(Qt.resolvedUrl("ProgramPage.qml"), { programId: data.id })
            else
                pageStack.push(Qt.resolvedUrl("DietPlanPage.qml"), { planId: data.id })
        })
    }

    Component.onCompleted: load()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            busy: page.loading
            MenuItem {
                text: qsTr("Ask a trainer")
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("NameDialog.qml"),
                                                { title: qsTr("Ask a trainer"), label: qsTr("Trainer's username") })
                    dialog.accepted.connect(function() {
                        page.act("POST", "coaching/requests/", { username: dialog.name })
                    })
                }
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
                title: qsTr("Coaching")
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }

            SectionHeader {
                visible: page.incoming.length > 0
                text: qsTr("Asking you to coach them")
            }
            Repeater {
                model: page.incoming
                delegate: ListItem {
                    contentHeight: Theme.itemSizeSmall
                    onClicked: openMenu()
                    menu: ContextMenu {
                        MenuItem {
                            text: qsTr("Accept")
                            onClicked: page.act("POST", "coaching/requests/" + modelData.id + "/accept/", null)
                        }
                        MenuItem {
                            text: qsTr("Decline")
                            onClicked: page.act("POST", "coaching/requests/" + modelData.id + "/decline/", null)
                        }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        truncationMode: TruncationMode.Fade
                        color: Theme.highlightColor
                        text: modelData.coachee.display_name || modelData.coachee.username
                    }
                }
            }

            SectionHeader {
                text: qsTr("Your coaches")
            }
            Repeater {
                model: page.coaches
                delegate: ListItem {
                    id: coachItem
                    contentHeight: Theme.itemSizeSmall
                    menu: ContextMenu {
                        MenuItem {
                            text: qsTr("End coaching")
                            onClicked: {
                                var id = modelData.id
                                coachItem.remorseAction(qsTr("Ending coaching"), function() {
                                    page.act("POST", "coaching/relationships/" + id + "/end/", null)
                                })
                            }
                        }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        truncationMode: TruncationMode.Fade
                        text: modelData.coach.display_name || modelData.coach.username
                    }
                }
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
                    text: qsTr("Waiting for %1 to answer").arg(modelData.coach.display_name || modelData.coach.username)
                }
            }
            Label {
                visible: !page.loading && page.coaches.length === 0 && page.outgoing.length === 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                text: qsTr("No coach yet. Pull down to ask a personal trainer by their username.")
            }

            SectionHeader {
                visible: page.sharedPrograms.length + page.sharedPlans.length > 0
                text: qsTr("Shared with you")
            }
            Repeater {
                model: page.sharedPrograms.map(function(p) { p.kind = "programs"; return p })
                       .concat(page.sharedPlans.map(function(p) { p.kind = "diet-plans"; return p }))
                delegate: ListItem {
                    contentHeight: Math.max(Theme.itemSizeSmall, sharedColumn.height + 2 * Theme.paddingSmall)
                    onClicked: openMenu()
                    menu: ContextMenu {
                        MenuItem {
                            text: modelData.imported ? qsTr("Import another copy") : qsTr("Import a copy")
                            onClicked: page.importPlan(modelData.kind, modelData.id)
                        }
                    }
                    Column {
                        id: sharedColumn
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        Label {
                            width: parent.width
                            truncationMode: TruncationMode.Fade
                            text: modelData.name
                        }
                        Label {
                            width: parent.width
                            truncationMode: TruncationMode.Fade
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: Theme.secondaryColor
                            text: [modelData.kind === "programs" ? qsTr("Program") : qsTr("Diet plan"),
                                   page.coachName(modelData.coach),
                                   modelData.imported ? qsTr("imported") : ""]
                                  .filter(function(p) { return p }).join(" · ")
                        }
                    }
                }
            }

            SectionHeader {
                visible: page.clients.length > 0
                text: qsTr("Your clients")
            }
            Repeater {
                model: page.clients
                delegate: ListItem {
                    id: clientItem
                    contentHeight: Theme.itemSizeSmall
                    onClicked: pageStack.push(Qt.resolvedUrl("ClientPage.qml"), { username: modelData.coachee.username })
                    menu: ContextMenu {
                        MenuItem {
                            text: qsTr("End coaching")
                            onClicked: {
                                var id = modelData.id
                                clientItem.remorseAction(qsTr("Ending coaching"), function() {
                                    page.act("POST", "coaching/relationships/" + id + "/end/", null)
                                })
                            }
                        }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        truncationMode: TruncationMode.Fade
                        text: modelData.coachee.display_name || modelData.coachee.username
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
