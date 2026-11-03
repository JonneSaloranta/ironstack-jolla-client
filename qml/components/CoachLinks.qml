import QtQuick 2.0
import Sailfish.Silica 1.0

// Coaching for one of your programs or diet plans, like the web's plan
// pages: a personal trainer shares it with clients, and a copy imported
// from a coach can take the coach's newer version. The page puts the menu
// items; this reads what's possible and does it. Quiet without the
// "Coaching" API area.
Item {
    id: links

    // "programs" or "diet-plans"
    property string kind: "programs"
    property int planId: -1
    // Only your own plans can be shared or updated.
    property bool own: false

    // Your active clients ({ id, username }); empty for a non-trainer.
    property var clients: []
    property bool updateAvailable: false
    property string updateDiff: ""

    signal updated()
    signal failed(string error)

    function load() {
        clients = []
        updateAvailable = false
        if (!own || planId < 0)
            return
        api.request("GET", "coaching/clients/", null, function(ok, status, data) {
            if (ok)
                clients = (data || []).map(function(r) { return r.coachee })
        })
        api.request("GET", "coaching/" + kind + "/" + planId + "/update/", null, function(ok, status, data) {
            updateAvailable = ok && data && data.available === true
            updateDiff = ok && data && data.diff ? data.diff : ""
        })
    }

    // Choose who it's shared with; the page pushes ClientsDialog.
    function share() {
        api.request("GET", "coaching/" + kind + "/" + planId + "/clients/", null, function(ok, status, data, error) {
            if (!ok)
                return failed(error)
            var dialog = pageStack.push(Qt.resolvedUrl("../pages/ClientsDialog.qml"), {
                clients: clients, chosen: (data && data.clients) || []
            })
            dialog.accepted.connect(function() {
                api.request("PUT", "coaching/" + kind + "/" + planId + "/clients/", { clients: dialog.chosen },
                            function(ok2, status2, data2, error2) {
                    if (!ok2)
                        failed(error2)
                })
            })
        })
    }

    function update() {
        api.request("POST", "coaching/" + kind + "/" + planId + "/update/", null, function(ok, status, data, error) {
            if (!ok)
                return failed(error)
            updateAvailable = false
            updated()
        })
    }

    onPlanIdChanged: load()
    onOwnChanged: load()
    visible: false
}
