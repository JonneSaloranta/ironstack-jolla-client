import QtQuick 2.0
import Sailfish.Silica 1.0

ApplicationWindow {
    id: appWindow

    initialPage: settings.configured ? Qt.resolvedUrl("pages/DashboardPage.qml")
                                     : Qt.resolvedUrl("pages/LoginPage.qml")
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations

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
}
