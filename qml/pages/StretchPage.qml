import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store
import "../js/texts.js" as Texts

// One stretch, like the web's: type, hold, muscles and how to do it
// (translated like the web). Your own stretches can be edited or
// deactivated.
Page {
    id: page

    property int stretchId
    property var stretch: Store.stretches ? Store.stretches[stretchId] || null : null
    property string errorText: ""
    property bool lookupsLoaded: false

    Component.onCompleted: Store.ensureLookups(api, function() { lookupsLoaded = true })

    function reload() {
        api.request("GET", "stretches/" + stretchId + "/", null, function(ok, status, data, error) {
            if (!ok) {
                errorText = error
                return
            }
            stretch = data
        })
    }

    RemorsePopup {
        id: remorse
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            visible: page.stretch !== null && page.stretch.is_custom
            MenuItem {
                text: qsTr("Deactivate")
                onClicked: remorse.execute(qsTr("Deactivating stretch"), function() {
                    api.request("DELETE", "stretches/" + page.stretchId + "/", null, function(ok, status, data, error) {
                        if (!ok) {
                            page.errorText = error
                            return
                        }
                        Store.stretchesChanged = true
                        pageStack.pop()
                    })
                })
            }
            MenuItem {
                text: qsTr("Edit")
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("StretchEditDialog.qml"), { stretch: page.stretch })
                    dialog.accepted.connect(function() {
                        api.request("PATCH", "stretches/" + page.stretchId + "/", dialog.body(),
                                    function(ok, status, data, error) {
                            if (!ok) {
                                page.errorText = error
                                return
                            }
                            Store.stretchesChanged = true
                            page.stretch = data
                        })
                    })
                }
            }
        }

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingSmall

            PageHeader {
                title: page.stretch ? Store.contentName(page.stretch.name) : ""
                description: page.stretch && page.stretch.is_custom ? qsTr("Custom") : ""
            }
            ErrorBanner {
                text: page.errorText
            }
            DetailItem {
                label: qsTr("Type")
                value: page.stretch ? (page.stretch.kind === "dynamic" ? qsTr("Dynamic") : qsTr("Static")) : ""
            }
            DetailItem {
                label: qsTr("Default hold")
                value: page.stretch ? page.stretch.default_hold_seconds + " s"
                                      + (page.stretch.per_side ? " " + qsTr("per side") : "") : ""
            }
            DetailItem {
                visible: page.stretch !== null && page.stretch.muscle_groups.length > 0
                label: qsTr("Muscle groups")
                value: page.stretch && page.lookupsLoaded
                       ? page.stretch.muscle_groups.map(Store.muscleGroupName).join(", ") : ""
            }
            SectionHeader {
                visible: howTo.text !== ""
                text: qsTr("How to do it")
            }
            Label {
                id: howTo
                visible: text !== ""
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                text: page.stretch ? Texts.contentText(page.stretch.instructions) : ""
            }
        }

        VerticalScrollDecorator {}
    }
}
