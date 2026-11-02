import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

Page {
    id: page

    property string errorText: ""
    property bool loading: true

    ListModel {
        id: programsModel
    }

    function load() {
        loading = true
        errorText = ""
        programsModel.clear()
        var own = []
        var templates = []
        Store.fetchAll(api, "programs/", function(results) {
            for (var i = 0; i < results.length; i++) {
                var group = Store.programGroup(results[i])
                if (group === "template")
                    templates.push(results[i])
                else if (group === "own")
                    own.push(results[i])
            }
        }, function(ok, error) {
            loading = false
            if (!ok) {
                errorText = error
                return
            }
            own.forEach(function(p) { append(p, qsTr("My programs")) })
            templates.forEach(function(p) { append(p, qsTr("Templates")) })
        })
    }

    function append(program, section) {
        programsModel.append({
            programId: program.id,
            name: Store.contentName(program.name),
            description: program.description || "",
            workoutCount: (program.workouts || []).length,
            section: section,
            // ListModel cannot hold nested JS arrays reliably; keep JSON.
            json: JSON.stringify(program)
        })
    }

    Component.onCompleted: load()

    SilicaListView {
        anchors.fill: parent
        model: programsModel

        header: Column {
            width: parent.width
            PageHeader {
                title: qsTr("Programs")
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }
        }

        section.property: "section"
        section.delegate: SectionHeader {
            text: section
        }

        PullDownMenu {
            busy: page.loading
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.load()
            }
        }

        delegate: ListItem {
            // Grows with the text size setting instead of clipping it.
            contentHeight: Math.max(Theme.itemSizeMedium, textColumn.height + 2 * Theme.paddingMedium)
            onClicked: pageStack.push(Qt.resolvedUrl("ProgramPage.qml"), {
                program: JSON.parse(model.json)
            })

            Column {
                id: textColumn
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    text: model.name
                }
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    text: qsTr("%n workout(s)", "", model.workoutCount)
                          + (model.description ? " - " + model.description : "")
                }
            }
        }

        ViewPlaceholder {
            enabled: !page.loading && programsModel.count === 0 && page.errorText === ""
            text: qsTr("No programs")
            hintText: qsTr("Create a program in the IronStack web app")
        }

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: page.loading
        }

        VerticalScrollDecorator {}
    }
}
