import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.KeepAlive 1.2
import Nemo.Notifications 1.0
import "js/store.js" as Store

ApplicationWindow {
    id: appWindow

    initialPage: settings.configured ? Qt.resolvedUrl("pages/DashboardPage.qml")
                                     : Qt.resolvedUrl("pages/LoginPage.qml")
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations
    // Silica pages are portrait-only unless told otherwise.
    _defaultPageOrientations: defaultAllowedOrientations

    Connections {
        target: api
        onUnauthorized: {
            if (pageStack.currentPage && pageStack.currentPage.objectName === "loginPage")
                return
            settings.clearActiveSession()
            pageStack.clear()
            pageStack.push(Qt.resolvedUrl("pages/LoginPage.qml"), {
                errorText: qsTr("The API key was not accepted. It may have been revoked.")
            }, PageStackAction.Immediate)
        }
    }

    // --- new personal records ---------------------------------------
    // The web shows a toast when a logged set makes a record; the set's
    // response lists them as `new_records` once it reaches the server.

    Connections {
        target: syncQueue
        onItemSynced: {
            if (method !== "POST" || path !== "sets/" || !data || !(data.new_records || []).length)
                return
            var made = data.new_records
            prNotification.summary = qsTr("New PR") + " - " + Store.contentName(made[0].exercise_name)
            prNotification.body = made.map(function(r) {
                return Store.recordLabel(r, qsTr("%1RM")) + ": "
                        + Store.recordValueText(r, settings.unitSystem, "%1 " + qsTr("reps"))
            }).join("\n")
            prNotification.replacesId = 0
            prNotification.publish()
        }
    }

    Notification {
        id: prNotification
        appName: "IronStack"
        appIcon: "harbour-ironstack"
        previewSummary: summary
        previewBody: body
        isTransient: true
        urgency: Notification.Normal
    }

    // --- rest timer ---------------------------------------------------
    // The session page starts a rest period by setting settings.restEndsAt;
    // this window (alive for the app's whole lifetime) ends it and tells
    // the user, even with the screen off.

    Timer {
        id: restTimer
        repeat: false
        onTriggered: {
            settings.restEndsAt = 0
            if (Qt.application.state !== Qt.ApplicationActive)
                restOverNotification.publish()
        }
    }

    Connections {
        target: settings
        onRestEndsAtChanged: {
            restTimer.stop()
            restOverNotification.close()
            if (settings.restEndsAt > 0) {
                restTimer.interval = Math.max(1, settings.restEndsAt - Date.now())
                restTimer.start()
            }
        }
    }

    // Without this the device may suspend during a rest with the screen
    // off, and the timer would only fire on the next wake-up.
    KeepAlive {
        enabled: settings.restEndsAt > 0
    }

    Notification {
        id: restOverNotification
        appName: "IronStack"
        appIcon: "harbour-ironstack"
        summary: qsTr("Rest is over")
        body: qsTr("Time for the next set")
        previewSummary: summary
        previewBody: body
        isTransient: true
        urgency: Notification.Normal
    }
}
