import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"

// The assistant's settings, like the web's: what it may read about you,
// what it should know about you, and - with your own Anthropic key - its
// model and how much it thinks. Saved as they're changed. The key itself
// is a credential and is only set on the web.
Page {
    id: page

    // assistant/ as the list read it: whether there's an own key.
    property var info: null
    property var settings_: null
    property bool loading: false
    property string errorText: ""

    readonly property var scopes: [
        ["reads_workouts", qsTr("Workout history, records and progression")],
        ["reads_body", qsTr("Body measurements and weight trend")],
        ["reads_food", qsTr("Food diary")],
        ["reads_activities", qsTr("Activities")],
        ["reads_stretching", qsTr("Stretching")],
        ["reads_profile", qsTr("Personal details (height, age, sex, activity level)")]
    ]
    readonly property var models: [
        ["", qsTr("The instance's default")],
        ["claude-opus-5-5", qsTr("Claude Opus 5.5 - best plans ($4 / $20)")],
        ["claude-sonnet-5-5", qsTr("Claude Sonnet 5.5 - good and half the price ($2 / $10)")],
        ["claude-haiku-4-5", qsTr("Claude Haiku 4.5 - fastest and cheapest, weaker plans ($1 / $5)")],
        ["claude-fable-5-1", qsTr("Claude Fable 5.1 - most capable, most expensive ($10 / $50)")]
    ]
    readonly property var efforts: [
        ["", qsTr("Default")],
        ["low", qsTr("Low - quickest and cheapest; fine for everyday questions")],
        ["medium", qsTr("Medium - balanced")],
        ["high", qsTr("High - more thorough plans, more tokens")],
        ["xhigh", qsTr("Extra high - for demanding planning")],
        ["max", qsTr("Maximum - the most thorough and the most expensive")]
    ]

    function indexOf(list, value) {
        for (var i = 0; i < list.length; i++) {
            if (list[i][0] === (value || ""))
                return i
        }
        return 0
    }

    function load() {
        loading = true
        api.request("GET", "assistant/settings/", null, function(ok, status, data, error) {
            loading = false
            errorText = ok ? "" : error
            if (ok)
                settings_ = data
        })
    }

    function save(changes) {
        api.request("PATCH", "assistant/settings/", changes, function(ok, status, data, error) {
            errorText = ok ? "" : error
            if (ok)
                settings_ = data
            else
                load()
        })
    }

    Component.onCompleted: load()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            PageHeader {
                title: qsTr("Assistant settings")
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }

            Column {
                visible: page.settings_ !== null
                width: parent.width

                SectionHeader {
                    text: qsTr("What it may read")
                }
                Repeater {
                    model: page.scopes
                    delegate: TextSwitch {
                        text: modelData[1]
                        checked: page.settings_ ? page.settings_[modelData[0]] : false
                        automaticCheck: false
                        onClicked: {
                            var change = {}
                            change[modelData[0]] = !checked
                            page.save(change)
                        }
                    }
                }

                SectionHeader {
                    text: qsTr("About you")
                }
                TextArea {
                    id: aboutField
                    width: parent.width
                    label: qsTr("What the assistant should know about you, e.g. injuries or equipment at home")
                    placeholderText: qsTr("About you")
                    text: page.settings_ ? page.settings_.about_me : ""
                    onActiveFocusChanged: {
                        if (!activeFocus && page.settings_ && text !== page.settings_.about_me)
                            page.save({ about_me: text })
                    }
                }

                SectionHeader {
                    visible: page.info !== null && page.info.has_own_key
                    text: qsTr("Your own key") + (page.info && page.info.own_key_hint ? " " + page.info.own_key_hint : "")
                }
                ComboBox {
                    visible: page.info !== null && page.info.has_own_key
                    label: qsTr("Model")
                    currentIndex: page.settings_ ? page.indexOf(page.models, page.settings_.own_key_model) : 0
                    menu: ContextMenu {
                        Repeater {
                            model: page.models
                            MenuItem {
                                text: modelData[1]
                                onClicked: page.save({ own_key_model: modelData[0] })
                            }
                        }
                    }
                }
                ComboBox {
                    visible: page.info !== null && page.info.has_own_key
                    label: qsTr("Thinking")
                    currentIndex: page.settings_ ? page.indexOf(page.efforts, page.settings_.own_key_effort) : 0
                    menu: ContextMenu {
                        Repeater {
                            model: page.efforts
                            MenuItem {
                                text: modelData[1]
                                onClicked: page.save({ own_key_effort: modelData[0] })
                            }
                        }
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
