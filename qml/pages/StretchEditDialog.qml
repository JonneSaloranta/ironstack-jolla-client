import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/store.js" as Store

// A stretch of your own, or changes to one (`stretch` set) - the web's
// stretch form. The page that opened it saves body().
Dialog {
    id: dialog

    property var stretch: null
    property var muscles: stretch ? stretch.muscle_groups.slice() : []
    property bool lookupsLoaded: false

    function toggle(id) {
        var copy = muscles.slice()
        var at = copy.indexOf(id)
        if (at >= 0)
            copy.splice(at, 1)
        else
            copy.push(id)
        muscles = copy
    }

    function body() {
        return {
            name: nameField.text.trim(),
            kind: kindBox.currentIndex === 1 ? "dynamic" : "static",
            per_side: perSideSwitch.checked,
            default_hold_seconds: parseInt(holdField.text, 10) || 30,
            muscle_groups: muscles,
            instructions: instructionsArea.text
        }
    }

    canAccept: nameField.text.trim() !== ""

    Component.onCompleted: Store.ensureLookups(api, function() { lookupsLoaded = true })

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            DialogHeader {
                acceptText: qsTr("Save")
                title: dialog.stretch ? qsTr("Edit stretch") : qsTr("New stretch")
            }
            TextField {
                id: nameField
                width: parent.width
                label: qsTr("Name")
                placeholderText: label
                text: dialog.stretch ? dialog.stretch.name : ""
            }
            ComboBox {
                id: kindBox
                label: qsTr("Type")
                currentIndex: dialog.stretch && dialog.stretch.kind === "dynamic" ? 1 : 0
                menu: ContextMenu {
                    MenuItem { text: qsTr("Static") }
                    MenuItem { text: qsTr("Dynamic") }
                }
            }
            TextSwitch {
                id: perSideSwitch
                text: qsTr("per side")
                checked: dialog.stretch ? dialog.stretch.per_side : false
            }
            TextField {
                id: holdField
                width: parent.width
                label: qsTr("Default hold")
                placeholderText: label
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 1; top: 3600 }
                text: dialog.stretch ? String(dialog.stretch.default_hold_seconds) : "30"
            }
            TextArea {
                id: instructionsArea
                width: parent.width
                label: qsTr("How to do it")
                placeholderText: label
                text: dialog.stretch ? dialog.stretch.instructions || "" : ""
            }
            SectionHeader {
                text: qsTr("Muscle groups")
            }
            Repeater {
                model: Store.lookupList("muscleGroups", dialog.lookupsLoaded)
                TextSwitch {
                    text: modelData.name
                    checked: dialog.muscles.indexOf(modelData.id) >= 0
                    automaticCheck: false
                    onClicked: dialog.toggle(modelData.id)
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
