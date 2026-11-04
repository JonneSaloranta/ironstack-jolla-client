import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/features.js" as Features

// Every part of the app in one list, grouped like IronStack's own menu.
Page {
    id: page

    // Every part, with what it needs in standalone mode (Features).
    readonly property var parts: [
        { section: "training", title: "Exercises", icon: "image://theme/icon-m-levels", target: "ExercisePickerPage.qml", feature: "" },
        { section: "training", title: "Programs", icon: "image://theme/icon-m-note", target: "ProgramsPage.qml", feature: "" },
        { section: "training", title: "History", icon: "image://theme/icon-m-history", target: "HistoryPage.qml", feature: "" },
        { section: "training", title: "Progress", icon: "image://theme/icon-m-diagnostic", target: "ProgressPage.qml", feature: "" },
        { section: "training", title: "Personal records", icon: "image://theme/icon-m-favorite", target: "RecordsPage.qml", feature: "" },
        { section: "nutrition", title: "Nutrition", icon: "image://theme/icon-m-health", target: "NutritionPage.qml", feature: "nutrition" },
        { section: "nutrition", title: "Food diary", icon: "image://theme/icon-m-note", target: "DiaryPage.qml", feature: "nutrition" },
        { section: "body", title: "Body tracking", icon: "image://theme/icon-m-person", target: "MeasurementsPage.qml", feature: "body" },
        { section: "body", title: "Activities", icon: "image://theme/icon-m-location", target: "ActivitiesPage.qml", feature: "body" },
        { section: "body", title: "Stretching", icon: "image://theme/icon-m-gesture", target: "StretchingPage.qml", feature: "body" },
        { section: "people", title: "Friends and groups", icon: "image://theme/icon-m-chat", target: "SocialPage.qml", feature: "social" },
        { section: "people", title: "Coaching", icon: "image://theme/icon-m-users", target: "CoachingPage.qml", feature: "coaching" },
        { section: "people", title: "AI assistant", icon: "image://theme/icon-m-outline-chat", target: "AssistantPage.qml", feature: "assistant" },
        { section: "app", title: "Guide", icon: "image://theme/icon-m-question", target: "GuidePage.qml", feature: "guide" },
        { section: "app", title: "Settings", icon: "image://theme/icon-m-setting", target: "SettingsPage.qml", feature: "" }
    ]

    ListModel {
        id: sections
    }

    // The parts shown: a hidden one (standalone mode, server parts off)
    // leaves no row, and a section with none left no header.
    function fill() {
        sections.clear()
        parts.forEach(function(part) {
            var state = Features.state(settings, part.feature)
            if (state === "hidden")
                return
            var row = {}
            for (var key in part)
                row[key] = part[key]
            row.dimmed = state === "dimmed"
            sections.append(row)
        })
    }

    Component.onCompleted: fill()

    Connections {
        target: settings
        onStandaloneChanged: page.fill()
        onShowServerFeaturesChanged: page.fill()
    }

    // ListElement can't hold qsTr(); the titles are translated here.
    function titleText(title) {
        switch (title) {
        case "Exercises": return qsTr("Exercises")
        case "Programs": return qsTr("Programs")
        case "History": return qsTr("History")
        case "Progress": return qsTr("Progress")
        case "Personal records": return qsTr("Personal records")
        case "Settings": return qsTr("Settings")
        case "Body tracking": return qsTr("Body tracking")
        case "Activities": return qsTr("Activities")
        case "Stretching": return qsTr("Stretching")
        case "Nutrition": return qsTr("Nutrition")
        case "Food diary": return qsTr("Food diary")
        case "Friends and groups": return qsTr("Friends and groups")
        case "Coaching": return qsTr("Coaching")
        case "AI assistant": return qsTr("AI assistant")
        case "Guide": return qsTr("Guide")
        }
        return title
    }

    function sectionText(section) {
        if (section === "training")
            return qsTr("Training")
        if (section === "body")
            return qsTr("Body and activity")
        if (section === "nutrition")
            return qsTr("Nutrition")
        if (section === "people")
            return qsTr("People")
        return qsTr("App")
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: sections
        header: PageHeader { title: qsTr("IronStack") }
        section.property: "section"
        section.delegate: SectionHeader { text: page.sectionText(section) }

        delegate: ListItem {
            contentHeight: Math.max(Theme.itemSizeSmall, texts.height + 2 * Theme.paddingSmall)
            // A dimmed part opens what it would do with a server.
            onClicked: model.dimmed
                       ? pageStack.push(Qt.resolvedUrl("ServerFeaturePage.qml"),
                                        { feature: model.feature, title: page.titleText(model.title) })
                       : pageStack.push(Qt.resolvedUrl(model.target))
            Icon {
                id: icon
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                source: model.icon
                opacity: model.dimmed ? Theme.opacityLow : 1
            }
            Column {
                id: texts
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: icon.right
                anchors.leftMargin: Theme.paddingMedium
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    color: model.dimmed ? Theme.secondaryColor : Theme.primaryColor
                    text: page.titleText(model.title)
                }
                ServerFeatureLabel {
                    visible: model.dimmed
                    width: parent.width
                    feature: model.feature
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
