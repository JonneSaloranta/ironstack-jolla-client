import QtQuick 2.0
import Sailfish.Silica 1.0

// Every part of the app in one list, grouped like IronStack's own menu.
Page {
    id: page

    ListModel {
        id: sections
        ListElement { section: "training"; title: "Exercises"; icon: "image://theme/icon-m-levels"; target: "ExercisePickerPage.qml" }
        ListElement { section: "training"; title: "Programs"; icon: "image://theme/icon-m-note"; target: "ProgramsPage.qml" }
        ListElement { section: "training"; title: "History"; icon: "image://theme/icon-m-history"; target: "HistoryPage.qml" }
        ListElement { section: "training"; title: "Personal records"; icon: "image://theme/icon-m-favorite"; target: "RecordsPage.qml" }
        ListElement { section: "body"; title: "Body tracking"; icon: "image://theme/icon-m-person"; target: "MeasurementsPage.qml" }
        ListElement { section: "body"; title: "Activities"; icon: "image://theme/icon-m-location"; target: "ActivitiesPage.qml" }
        ListElement { section: "body"; title: "Stretching"; icon: "image://theme/icon-m-gesture"; target: "StretchingPage.qml" }
        ListElement { section: "app"; title: "Settings"; icon: "image://theme/icon-m-setting"; target: "SettingsPage.qml" }
    }

    // ListElement can't hold qsTr(); the titles are translated here.
    function titleText(title) {
        switch (title) {
        case "Exercises": return qsTr("Exercises")
        case "Programs": return qsTr("Programs")
        case "History": return qsTr("History")
        case "Personal records": return qsTr("Personal records")
        case "Settings": return qsTr("Settings")
        case "Body tracking": return qsTr("Body tracking")
        case "Activities": return qsTr("Activities")
        case "Stretching": return qsTr("Stretching")
        }
        return title
    }

    function sectionText(section) {
        if (section === "training")
            return qsTr("Training")
        if (section === "body")
            return qsTr("Body and activity")
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
            contentHeight: Theme.itemSizeSmall
            onClicked: pageStack.push(Qt.resolvedUrl(model.target))
            Icon {
                id: icon
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                source: model.icon
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: icon.right
                anchors.leftMargin: Theme.paddingMedium
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                truncationMode: TruncationMode.Fade
                text: page.titleText(model.title)
            }
        }

        VerticalScrollDecorator {}
    }
}
