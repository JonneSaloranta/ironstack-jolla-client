import QtQuick 2.6
import Sailfish.Silica 1.0
import "../js/store.js" as Store

// One exercise in training mode: what to do, big steppers for weight and
// reps prefilled with the best guess, and a single tap to log the set.
// RPE/RIR and warm-up/failure are folded away under "More".
Item {
    id: panel

    property var pe: null
    property int index_: 0
    property int count: 0
    property var previous: null
    property var suggestion: null
    property var prefillValues: null
    property bool inProgress: true
    property bool allDone: false

    signal logSet(var values)
    signal previous_()
    signal next_()
    signal finish()

    readonly property string unitSystem: settings.unitSystem
    readonly property real stepKg: pe && pe.weight_increment ? parseFloat(pe.weight_increment) : 2.5
    readonly property real stepDisplay: Store.isImperial(unitSystem) ? 5 : stepKg
    readonly property bool done: pe !== null && Store.isExerciseComplete(pe)
    readonly property int nextSetNumber: pe ? pe.sets.length + 1 : 1
    readonly property bool canLog: inProgress && weightField.acceptableInput && repsField.acceptableInput
                                   && parseInt(repsField.text, 10) > 0
    property bool showMore: false
    // Inputs are refilled when a set is logged or the best guess changes
    // (last time's sets arrive after the session itself) - not on every
    // refresh, and never under the user's fingers.
    property string filledFor: ""

    function refill() {
        if (!pe || !prefillValues)
            return
        var key = pe.sets.length + ":" + prefillValues.source
        if (key === filledFor || weightField.activeFocus || repsField.activeFocus)
            return
        filledFor = key
        var p = prefillValues
        weightField.text = p.weightKg !== null && p.weightKg !== undefined
                ? Store.formatNumber(Store.kgToDisplay(p.weightKg, unitSystem)) : ""
        repsField.text = p.reps !== null && p.reps !== undefined ? String(p.reps) : ""
        rpeField.text = ""
        rirField.text = ""
        warmupSwitch.checked = false
        failureSwitch.checked = false
    }

    onPeChanged: refill()
    onPrefillValuesChanged: refill()

    function step(field, delta, minimum) {
        var current = parseFloat(field.text.replace(",", ".")) || 0
        field.text = Store.formatNumber(Math.max(minimum, current + delta))
    }

    function submit() {
        if (!canLog)
            return
        logSet({
            weightKg: Store.displayToKg(weightField.text, unitSystem),
            reps: parseInt(repsField.text, 10),
            rpe: rpeField.text === "" ? null : parseFloat(rpeField.text.replace(",", ".")),
            rir: rirField.text === "" ? null : parseInt(rirField.text, 10),
            isWarmup: warmupSwitch.checked,
            isFailure: failureSwitch.checked
        })
        weightField.focus = false
        repsField.focus = false
        showMore = false
    }

    function hintText() {
        var lines = []
        if (previous)
            lines.push(qsTr("Last time: %1").arg(Store.summarizeSets(previous.sets, unitSystem)))
        var p = prefillValues
        if (p && p.source === "target")
            lines.push(qsTr("From the program target"))
        else if (p && !p.weightKg && pe.sets.length === 0 && !previous)
            lines.push(qsTr("No earlier sets - enter the weight you start with"))
        return lines.join("\n")
    }

    // What to do, and what's been done, at the top...
    Column {
        id: info
        width: parent.width
        spacing: Theme.paddingSmall

        Item {
            width: parent.width
            height: Math.max(nameLabel.height, Theme.itemSizeSmall)

            IconButton {
                id: prevButton
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                icon.source: "image://theme/icon-m-left"
                enabled: panel.index_ > 0
                opacity: enabled ? 1.0 : 0.0
                onClicked: panel.previous_()
            }
            Label {
                id: nameLabel
                anchors.left: prevButton.right
                anchors.right: nextButton.left
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                font.pixelSize: Theme.fontSizeLarge
                color: Theme.highlightColor
                text: panel.pe ? Store.contentName(panel.pe.exercise_name) : ""
            }
            IconButton {
                id: nextButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                icon.source: "image://theme/icon-m-right"
                enabled: panel.index_ < panel.count - 1
                opacity: enabled ? 1.0 : 0.0
                onClicked: panel.next_()
            }
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Theme.fontSizeSmall
            color: panel.done ? Theme.highlightColor : Theme.secondaryHighlightColor
            text: {
                if (!panel.pe)
                    return ""
                var target = Store.targetText(panel.pe, panel.unitSystem)
                var progress = panel.pe.set_count
                        ? qsTr("%1/%2 done").arg(Store.workingSetCount(panel.pe)).arg(panel.pe.set_count)
                        : qsTr("%n set(s)", "", panel.pe.sets.length)
                return (target ? target + "  -  " : "") + progress
            }
        }

        SuggestionLabel {
            suggestion: panel.suggestion
            pe: panel.pe
        }

        Label {
            visible: text.length > 0
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
            text: panel.hintText()
        }

        Label {
            visible: panel.allDone && panel.inProgress
            width: parent.width
            topPadding: Theme.paddingSmall
            horizontalAlignment: Text.AlignHCenter
            color: Theme.highlightColor
            text: qsTr("All exercises done")
        }

        Flow {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            topPadding: Theme.paddingMedium
            spacing: Theme.paddingLarge
            visible: panel.pe !== null && panel.pe.sets.length > 0
            Repeater {
                model: panel.pe ? panel.pe.sets : []
                delegate: Row {
                    spacing: Theme.paddingSmall
                    Label {
                        anchors.baseline: setLabel.baseline
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryColor
                        text: modelData.is_warmup ? "W" : modelData.set_number
                    }
                    Label {
                        id: setLabel
                        font.pixelSize: Theme.fontSizeMedium
                        opacity: modelData.pending ? Theme.opacityHigh : 1.0
                        text: Store.formatWeight(modelData.weight, panel.unitSystem) + " x " + modelData.reps
                    }
                    Icon {
                        visible: modelData.pending === true
                        anchors.verticalCenter: parent.verticalCenter
                        source: "image://theme/icon-s-sync"
                    }
                }
            }
        }
    }

    // ...and the controls at the bottom, where a thumb reaches.
    Column {
        id: controls
        width: parent.width
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.paddingLarge
        spacing: Theme.paddingSmall

        Button {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: panel.allDone && panel.inProgress
            text: qsTr("Finish workout")
            onClicked: panel.finish()
        }

        Stepper {
            id: weightStepper
            width: parent.width
            field: weightField
            onDecrease: panel.step(weightField, -panel.stepDisplay, 0)
            onIncrease: panel.step(weightField, panel.stepDisplay, 0)

            TextField {
                id: weightField
                width: parent.width
                horizontalAlignment: TextInput.AlignHCenter
                font.pixelSize: Theme.fontSizeExtraLarge
                label: Store.weightUnit(panel.unitSystem)
                placeholderText: Store.weightUnit(panel.unitSystem)
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                validator: RegExpValidator { regExp: /^\d{1,4}([.,]\d{0,2})?$/ }
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: repsField.focus = true
            }
        }

        Stepper {
            width: parent.width
            field: repsField
            onDecrease: panel.step(repsField, -1, 0)
            onIncrease: panel.step(repsField, 1, 0)

            TextField {
                id: repsField
                width: parent.width
                horizontalAlignment: TextInput.AlignHCenter
                font.pixelSize: Theme.fontSizeExtraLarge
                label: qsTr("reps")
                placeholderText: qsTr("reps")
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 0; top: 999 }
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: panel.submit()
            }
        }

        Button {
            anchors.horizontalCenter: parent.horizontalCenter
            preferredWidth: Theme.buttonWidthLarge
            enabled: panel.canLog
            visible: panel.inProgress
            text: qsTr("Log set %1").arg(panel.nextSetNumber)
            onClicked: panel.submit()
        }

        // --- extras, folded away -----------------------------------------------

        BackgroundItem {
            visible: panel.inProgress
            width: parent.width
            height: Theme.itemSizeExtraSmall
            onClicked: panel.showMore = !panel.showMore
            Label {
                anchors.centerIn: parent
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: panel.showMore ? qsTr("Fewer options") : qsTr("RPE, RIR, warm-up, failure")
            }
        }

        Column {
            width: parent.width
            visible: panel.showMore && panel.inProgress

            Row {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                TextField {
                    id: rpeField
                    width: parent.width / 2
                    label: qsTr("RPE (optional)")
                    placeholderText: label
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    validator: RegExpValidator { regExp: /^\d{1,2}([.,]\d)?$/ }
                }
                TextField {
                    id: rirField
                    width: parent.width / 2
                    label: qsTr("RIR (optional)")
                    placeholderText: label
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator { bottom: 0; top: 20 }
                }
            }
            TextSwitch {
                id: warmupSwitch
                text: qsTr("Warm-up set")
                description: qsTr("Not counted for records, progression or analytics")
            }
            TextSwitch {
                id: failureSwitch
                text: qsTr("Taken to failure")
            }
        }

    }
}
