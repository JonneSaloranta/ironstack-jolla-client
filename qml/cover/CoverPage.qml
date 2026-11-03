import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/store.js" as Store
import "../js/nutrition.js" as Nutrition

CoverBackground {
    id: cover

    property bool hasSession: settings.activeSessionId >= 0
    property bool resting: settings.restEndsAt > 0
    property real elapsed: 0
    property real restRemaining: 0

    // Today's food when no workout is on: { calories, protein,
    // calorieTarget, proteinTarget }, or null when there's
    // nothing to show (no connection yet, no nutrition permission).
    property var today: null
    property string todayIso: ""
    property real fetchedAt: 0
    property int fetchedEdits: -1

    // Read when the cover comes into view (the app was just minimized,
    // perhaps after logging something): at most every 30 s, unless the
    // diary was changed in the app or it's a new day.
    function refreshToday() {
        if (!settings.configured || hasSession)
            return
        var iso = Store.isoDate(new Date())
        if (iso === todayIso && Nutrition.diaryEdits === fetchedEdits && Date.now() - fetchedAt < 30000)
            return
        fetchedAt = Date.now()
        fetchedEdits = Nutrition.diaryEdits
        var target = null
        var totals = null
        var pending = 2
        function done() {
            if (--pending > 0 || totals === null)
                return
            todayIso = iso
            today = Nutrition.daySummary(totals, target)
        }
        api.request("GET", "nutrition-targets/?page_size=100", null, function(ok, status, data) {
            if (ok)
                target = Nutrition.currentTarget(data.results)
            done()
        })
        api.request("GET", "nutrition/daily-totals/?date=" + iso, null, function(ok, status, data) {
            if (ok && data)
                totals = data.totals
            done()
        })
    }

    onStatusChanged: {
        if (status === Cover.Active)
            refreshToday()
    }

    // The food diary with a quick entry, over whatever the app shows.
    function openQuickEntry() {
        appWindow.activate()
        Store.whenIdle(pageStack, function() {
            var top = pageStack.currentPage
            var diary = top && top.objectName === "diaryPage" && top.isoDay === Store.isoDate(new Date())
                        ? top
                        : pageStack.push(Qt.resolvedUrl("../pages/DiaryPage.qml"), {}, PageStackAction.Immediate)
            Store.whenIdle(pageStack, function() { diary.quickEntry(null) })
        })
    }

    readonly property bool showToday: !hasSession && today !== null

    function tick() {
        elapsed = Store.elapsedSince(settings.activeSessionStarted)
        restRemaining = Math.max(0, (settings.restEndsAt - Date.now()) / 1000)
    }

    Timer {
        interval: 1000
        repeat: true
        running: cover.hasSession && cover.status === Cover.Active
        triggeredOnStart: true
        onTriggered: cover.tick()
    }

    Column {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.paddingLarge
        spacing: Theme.paddingSmall

        Label {
            visible: !cover.hasSession && !cover.showToday
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "IronStack"
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeLarge
        }

        Label {
            visible: cover.showToday
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryHighlightColor
            text: qsTr("Today")
        }
        Label {
            visible: cover.showToday
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Theme.fontSizeExtraLarge
            color: Theme.highlightColor
            text: cover.today ? cover.today.calories : ""
        }
        Label {
            visible: cover.showToday
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
            text: cover.today && cover.today.calorieTarget ? qsTr("/ %1 kcal").arg(cover.today.calorieTarget) : "kcal"
        }
        // Eaten against the target; full when over it.
        Rectangle {
            visible: cover.showToday && cover.today.calorieTarget > 0
            width: parent.width
            height: Math.max(2, Math.round(Theme.paddingSmall / 2))
            radius: height / 2
            color: Theme.rgba(Theme.secondaryColor, 0.3)
            Rectangle {
                height: parent.height
                radius: parent.radius
                width: cover.showToday && cover.today.calorieTarget > 0
                       ? parent.width * Math.min(1, cover.today.calories / cover.today.calorieTarget) : 0
                color: Theme.highlightColor
            }
        }
        Label {
            visible: cover.showToday
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
            text: cover.today ? (cover.today.proteinTarget
                                 ? qsTr("Protein %1 / %2 g").arg(cover.today.protein).arg(cover.today.proteinTarget)
                                 : qsTr("Protein %1 g").arg(cover.today.protein)) : ""
        }

        Label {
            visible: cover.hasSession
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeSmall
            text: settings.activeSessionName || qsTr("Workout")
        }

        Label {
            visible: cover.hasSession
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: cover.resting ? Theme.fontSizeMedium : Theme.fontSizeExtraLarge
            color: cover.resting ? Theme.secondaryColor : Theme.primaryColor
            text: Store.formatDuration(cover.elapsed)
        }

        Label {
            visible: cover.resting
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Theme.fontSizeExtraLarge
            color: Theme.highlightColor
            text: Store.formatDuration(Math.ceil(cover.restRemaining))
        }

        Label {
            visible: cover.resting
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryHighlightColor
            text: qsTr("rest")
        }

        Label {
            visible: !cover.hasSession && !cover.showToday
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Theme.secondaryColor
            text: qsTr("No workout in progress")
        }
    }

    CoverActionList {
        enabled: cover.showToday
        CoverAction {
            // quick entry to today's diary
            iconSource: "image://theme/icon-cover-new"
            onTriggered: cover.openQuickEntry()
        }
    }

    CoverActionList {
        enabled: cover.resting
        CoverAction {
            // +30 s
            iconSource: "image://theme/icon-cover-new"
            onTriggered: settings.restEndsAt = settings.restEndsAt + 30000
        }
        CoverAction {
            // skip
            iconSource: "image://theme/icon-cover-next"
            onTriggered: settings.restEndsAt = 0
        }
    }
}
