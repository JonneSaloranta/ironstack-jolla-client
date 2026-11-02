import QtQuick 2.0
import Sailfish.Silica 1.0

// A recipe's name, servings and instructions - the web's recipe form. The
// page that opened it saves body().
Dialog {
    id: dialog

    property var recipe: null

    function body() {
        return {
            name: nameField.text.trim(),
            servings: parseInt(servingsField.text, 10) || 1,
            instructions: instructionsArea.text
        }
    }

    canAccept: nameField.text.trim() !== "" && parseInt(servingsField.text, 10) > 0

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            DialogHeader {
                acceptText: qsTr("Save")
                title: dialog.recipe ? qsTr("Edit recipe") : qsTr("New recipe")
            }
            TextField {
                id: nameField
                width: parent.width
                label: qsTr("Name")
                placeholderText: label
                text: dialog.recipe ? dialog.recipe.name : ""
            }
            TextField {
                id: servingsField
                width: parent.width
                label: qsTr("Servings")
                placeholderText: label
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 1; top: 999 }
                text: dialog.recipe ? String(dialog.recipe.servings) : "1"
            }
            TextArea {
                id: instructionsArea
                width: parent.width
                label: qsTr("Instructions")
                placeholderText: label
                text: dialog.recipe ? dialog.recipe.instructions || "" : ""
            }
        }

        VerticalScrollDecorator {}
    }
}
