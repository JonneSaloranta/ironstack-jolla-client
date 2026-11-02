import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/store.js" as Store

// A new exercise of your own, or changes to one (`exercise` set) - the
// same fields as the web's exercise form. Images can only be added on the
// web (the API takes no uploads).
Dialog {
    id: dialog

    property var exercise: null

    property var primary: exercise ? exercise.primary_muscle_groups.slice() : []
    property var secondary: exercise ? exercise.secondary_muscle_groups.slice() : []
    property var equipmentId: exercise && Store.present(exercise.equipment) ? exercise.equipment : null
    property bool lookupsLoaded: false

    readonly property var movementTypes: ["compound", "isolation"]
    readonly property var weightModes: ["total", "per_hand"]

    function toggle(list, id) {
        var copy = list.slice()
        var at = copy.indexOf(id)
        if (at >= 0)
            copy.splice(at, 1)
        else
            copy.push(id)
        return copy
    }

    // The request body for exercises/ - the page that opened the dialog
    // sends it and shows any error, like LogSetDialog.
    function body() {
        return {
            name: nameField.text.trim(),
            description: descriptionArea.text,
            instructions: instructionsArea.text,
            movement_type: movementTypes[movementBox.currentIndex],
            weight_input_mode: weightModes[weightModeBox.currentIndex],
            equipment: equipmentId,
            primary_muscle_groups: primary,
            secondary_muscle_groups: secondary
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
                title: dialog.exercise ? qsTr("Edit exercise") : qsTr("New exercise")
            }

            TextField {
                id: nameField
                width: parent.width
                label: qsTr("Name")
                placeholderText: label
                text: dialog.exercise ? dialog.exercise.name : ""
            }
            ComboBox {
                id: movementBox
                label: qsTr("Movement type")
                currentIndex: dialog.exercise ? Math.max(0, dialog.movementTypes.indexOf(dialog.exercise.movement_type)) : 0
                menu: ContextMenu {
                    MenuItem { text: qsTr("Compound") }
                    MenuItem { text: qsTr("Isolation") }
                }
            }
            ComboBox {
                id: weightModeBox
                label: qsTr("Weight logging")
                currentIndex: dialog.exercise ? Math.max(0, dialog.weightModes.indexOf(dialog.exercise.weight_input_mode)) : 0
                menu: ContextMenu {
                    MenuItem { text: qsTr("Total load") }
                    MenuItem { text: qsTr("Per hand / dumbbell") }
                }
            }
            ComboBox {
                label: qsTr("Equipment")
                value: Store.present(dialog.equipmentId) ? Store.equipmentName(dialog.equipmentId) : qsTr("None")
                menu: ContextMenu {
                    MenuItem {
                        text: qsTr("None")
                        onClicked: dialog.equipmentId = null
                    }
                    Repeater {
                        model: Store.lookupList("equipment", dialog.lookupsLoaded)
                        MenuItem {
                            text: modelData.name
                            onClicked: dialog.equipmentId = modelData.id
                        }
                    }
                }
            }
            TextArea {
                id: descriptionArea
                width: parent.width
                label: qsTr("Description")
                placeholderText: label
                text: dialog.exercise ? dialog.exercise.description : ""
            }
            TextArea {
                id: instructionsArea
                width: parent.width
                label: qsTr("Instructions")
                placeholderText: label
                text: dialog.exercise ? dialog.exercise.instructions : ""
            }

            SectionHeader {
                text: qsTr("Primary muscles")
            }
            Repeater {
                model: Store.lookupList("muscleGroups", dialog.lookupsLoaded)
                TextSwitch {
                    text: modelData.name
                    checked: dialog.primary.indexOf(modelData.id) >= 0
                    automaticCheck: false
                    onClicked: dialog.primary = dialog.toggle(dialog.primary, modelData.id)
                }
            }
            SectionHeader {
                text: qsTr("Secondary muscles")
            }
            Repeater {
                model: Store.lookupList("muscleGroups", dialog.lookupsLoaded)
                TextSwitch {
                    text: modelData.name
                    checked: dialog.secondary.indexOf(modelData.id) >= 0
                    automaticCheck: false
                    onClicked: dialog.secondary = dialog.toggle(dialog.secondary, modelData.id)
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
