import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page
    objectName: "loginPage"

    property string errorText: ""
    property bool testing: false

    function connect() {
        errorText = ""
        testing = true
        api.requestWith(urlField.text, keyField.text, "GET", "profile/", null,
                        function(ok, status, data, error) {
            testing = false
            if (!ok) {
                page.errorText = error
                return
            }
            settings.baseUrl = urlField.text
            settings.apiKey = keyField.text
            settings.unitSystem = data.unit_system || "metric"
            pageStack.replaceAbove(null, Qt.resolvedUrl("DashboardPage.qml"))
        })
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: qsTr("Connect to IronStack")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
                text: qsTr("Create an API key in your IronStack instance under Profile > API keys. "
                           + "It needs read access to profile, exercises, programs, records and analytics, "
                           + "and create, read, update and delete access to workouts.")
            }

            TextField {
                id: urlField
                width: parent.width
                label: qsTr("Server address")
                placeholderText: "https://ironstack.example.com"
                text: settings.baseUrl
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: keyField.focus = true
            }

            PasswordField {
                id: keyField
                width: parent.width
                label: qsTr("API key")
                placeholderText: "isk_..."
                text: settings.apiKey
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                EnterKey.enabled: urlField.text.length > 0 && text.length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: page.connect()
            }

            ErrorBanner {
                text: page.errorText
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.testing ? qsTr("Connecting...") : qsTr("Connect")
                enabled: !page.testing && urlField.text.length > 0 && keyField.text.length > 0
                onClicked: page.connect()
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: page.testing
                size: BusyIndicatorSize.Medium
            }
        }
    }
}
