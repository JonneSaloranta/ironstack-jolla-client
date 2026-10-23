import QtQuick 2.6
import Sailfish.Silica 1.0
import "../js/store.js" as Store

Page {
    id: page

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            PageHeader {
                title: qsTr("Settings")
            }

            SectionHeader {
                text: qsTr("Training")
            }

            Slider {
                width: parent.width
                minimumValue: 0
                maximumValue: 300
                stepSize: 15
                value: settings.restSeconds
                label: qsTr("Rest timer after a set")
                valueText: value === 0 ? qsTr("Off") : Store.formatDuration(value)
                onReleased: settings.restSeconds = value
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Starts when you log a working set. You get a notification when the rest is over, "
                           + "also with the screen off.")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                topPadding: Theme.paddingLarge
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Weights are shown in %1, following the unit setting of your IronStack profile.")
                      .arg(Store.weightUnit(settings.unitSystem))
            }

            SectionHeader {
                text: qsTr("Server")
            }

            DetailItem {
                label: qsTr("Address")
                value: settings.baseUrl
            }

            ButtonLayout {
                Button {
                    text: qsTr("Change server or key")
                    onClicked: pageStack.push(Qt.resolvedUrl("LoginPage.qml"))
                }
                Button {
                    text: qsTr("Log out")
                    onClicked: {
                        remorse.execute(syncQueue.count > 0
                                        ? qsTr("Logging out, %n unsynced change(s) lost", "", syncQueue.count)
                                        : qsTr("Logging out"), function() {
                            syncQueue.clear()
                            settings.logout()
                            pageStack.replaceAbove(null, Qt.resolvedUrl("LoginPage.qml"))
                        })
                    }
                }
            }

            SectionHeader {
                text: qsTr("About")
            }

            DetailItem {
                label: qsTr("Version")
                value: Qt.application.version
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: qsTr("IronStack for Sailfish OS is free software under the GNU AGPL v3.")
            }
        }

        VerticalScrollDecorator {}
    }

    RemorsePopup {
        id: remorse
    }
}
