import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/features.js" as Features

// What a dimmed part of the app does with an IronStack server, opened in
// standalone mode instead of the part itself (docs/STANDALONE.md).
Page {
    id: page

    property string feature
    property string title

    function description() {
        switch (feature) {
        case "social":
            return qsTr("Add friends on your IronStack server, message them and form groups to train together.")
        case "coaching":
            return qsTr("Ask a personal trainer to coach you, take the programs and diet plans they share - or "
                        + "coach others yourself.")
        case "assistant":
            return qsTr("Ask the AI assistant about your training and food. It can make you a program, a diet "
                        + "plan or a recipe.")
        case "guide":
            return qsTr("The guided tours of IronStack's web pages.")
        case "recently_active":
            return qsTr("See who else on your IronStack server has been training lately.")
        case "food_search":
            return qsTr("Find foods in Open Food Facts by name or barcode, with their nutrition.")
        case "body":
            return qsTr("Body measurements with their trends, activities like running or cycling, and guided "
                        + "stretching.")
        case "nutrition":
            return qsTr("A food diary, your foods and recipes, calorie and macro goals, diet plans and "
                        + "statistics.")
        }
        return ""
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: page.title
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.highlightColor
                text: page.description()
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: Features.comingLater(page.feature)
                      ? qsTr("This part isn't in the app's offline mode yet; it comes in a later version. It works "
                             + "now when the app is connected to an IronStack server.")
                      : qsTr("This needs an IronStack server: it's about other people, or done on the server. "
                             + "Moving the data on this phone to a server comes in a later version.")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: qsTr("To hide what needs a server, turn off \"Show what needs a server\" in Settings.")
            }
        }
    }
}
