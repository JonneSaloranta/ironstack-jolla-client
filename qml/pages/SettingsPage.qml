import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

Page {
    id: page

    // profile/ as last loaded; changes are saved as they're made.
    property var profile: null
    property string errorText: ""
    property bool loading: false

    readonly property var languages: [["en", "English"], ["fi", "Suomi"], ["sv", "Svenska"],
                                      ["ru", "Русский"], ["it", "Italiano"], ["et", "Eesti"]]

    function load() {
        loading = true
        api.request("GET", "profile/", null, function(ok, status, data, error) {
            loading = false
            if (!ok) {
                errorText = error
                return
            }
            errorText = ""
            profile = data
        })
    }

    function save(changes) {
        api.request("PATCH", "profile/", changes, function(ok, status, data, error) {
            if (!ok) {
                errorText = error
                load()
                return
            }
            errorText = ""
            profile = data
            settings.unitSystem = data.unit_system || "metric"
        })
    }

    function languageIndex(code) {
        for (var i = 0; i < languages.length; i++) {
            if (languages[i][0] === code)
                return i
        }
        return 0
    }

    Component.onCompleted: load()

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

            TextSwitch {
                text: qsTr("Stretching timer sound")
                description: qsTr("A chime when a hold starts, when other steps end and when the session is done.")
                checked: settings.timerSound
                automaticCheck: false
                onClicked: settings.timerSound = !checked
            }

            // The IronStack profile, the same settings as the web's
            // Profile page; units apply here too.
            SectionHeader {
                text: qsTr("IronStack profile")
            }

            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }

            Column {
                width: parent.width
                visible: page.profile !== null
                enabled: !page.loading

                ComboBox {
                    label: qsTr("Units")
                    currentIndex: page.profile && page.profile.unit_system === "imperial" ? 1 : 0
                    menu: ContextMenu {
                        MenuItem {
                            text: qsTr("Metric (kg, km)")
                            onClicked: page.save({ unit_system: "metric" })
                        }
                        MenuItem {
                            text: qsTr("Imperial (lb, mi)")
                            onClicked: page.save({ unit_system: "imperial" })
                        }
                    }
                }
                ComboBox {
                    label: qsTr("Language")
                    description: qsTr("For the IronStack web and texts from the server, like suggestions")
                    currentIndex: page.profile ? page.languageIndex(page.profile.language) : 0
                    menu: ContextMenu {
                        Repeater {
                            model: page.languages
                            MenuItem {
                                text: modelData[1]
                                onClicked: page.save({ language: modelData[0] })
                            }
                        }
                    }
                }
                TextField {
                    id: timezoneField
                    width: parent.width
                    label: qsTr("Timezone")
                    placeholderText: "Europe/Helsinki"
                    text: page.profile ? page.profile.timezone : ""
                    EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                    EnterKey.onClicked: {
                        focus = false
                        if (page.profile && text.trim() !== page.profile.timezone)
                            page.save({ timezone: text.trim() })
                    }
                }
                TextField {
                    width: parent.width
                    label: Store.isImperial(settings.unitSystem) ? qsTr("Height (in)") : qsTr("Height (cm)")
                    placeholderText: label
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    validator: RegExpValidator { regExp: /^(\d{1,3}([.,]\d{0,1})?)?$/ }
                    text: page.profile && Store.present(page.profile.height)
                          ? Store.formatNumber(Store.measurementToDisplay(page.profile.height, "length", settings.unitSystem))
                          : ""
                    EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                    EnterKey.onClicked: {
                        focus = false
                        page.save({ height: text === "" ? null
                                                        : Store.displayToMeasurement(text, "length", settings.unitSystem) })
                    }
                }
                TextSwitch {
                    text: qsTr("Body tracking reminder")
                    description: qsTr("Shows a reminder on the home page when you haven't logged a body measurement "
                                      + "in 14 days.")
                    checked: page.profile ? page.profile.body_tracking_reminders_enabled : false
                    automaticCheck: false
                    onClicked: page.save({ body_tracking_reminders_enabled: !checked })
                }
                TextSwitch {
                    text: qsTr("Guided tours on the web")
                    description: qsTr("A short tour the first time you open each part of the IronStack web. The same "
                                      + "tours can be read in the app's Guide.")
                    checked: page.profile ? page.profile.tutorials_enabled : false
                    automaticCheck: false
                    onClicked: page.save({ tutorials_enabled: !checked })
                }
                TextSwitch {
                    text: qsTr("Show BMI")
                    description: qsTr("Turns off the BMI card and its category ranges entirely.")
                    checked: page.profile ? page.profile.show_bmi : false
                    automaticCheck: false
                    onClicked: page.save({ show_bmi: !checked })
                }
                TextSwitch {
                    text: qsTr("Share my activity")
                    description: qsTr("Lets everyone using this instance see your longest streak, "
                                      + "workout count, PRs, total weight lifted, and when you last "
                                      + "trained, in the dashboard's achievements carousel and "
                                      + "\"Recently active\" list. Turn off to keep your own "
                                      + "activity private - you'll still see everyone else's.")
                    checked: page.profile ? page.profile.show_achievements : false
                    automaticCheck: false
                    onClicked: page.save({ show_achievements: !checked })
                }
                TextSwitch {
                    text: qsTr("Allow friend requests")
                    checked: page.profile ? page.profile.allow_friend_requests : false
                    automaticCheck: false
                    onClicked: page.save({ allow_friend_requests: !checked })
                }
                TextSwitch {
                    text: qsTr("Allow group invites")
                    checked: page.profile ? page.profile.allow_group_invites : false
                    automaticCheck: false
                    onClicked: page.save({ allow_group_invites: !checked })
                }
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
                text: qsTr("Troubleshooting")
            }

            // Listed from least to most; settings.logLevel is 3 (errors)
            // down to 0 (debug).
            ComboBox {
                label: qsTr("App log")
                description: qsTr("What the app writes in its log. More detail helps find a problem; it never "
                                  + "includes your API key or what you've logged.")
                currentIndex: 3 - settings.logLevel
                menu: ContextMenu {
                    MenuItem { text: qsTr("Errors only") }
                    MenuItem { text: qsTr("Warnings") }
                    MenuItem { text: qsTr("Info") }
                    MenuItem { text: qsTr("Debug") }
                }
                onCurrentIndexChanged: settings.logLevel = 3 - currentIndex
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Show app log")
                onClicked: pageStack.push(Qt.resolvedUrl("LogPage.qml"))
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
