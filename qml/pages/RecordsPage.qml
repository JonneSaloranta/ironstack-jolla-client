import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

Page {
    id: page

    property string nextUrl: "records/"
    property bool loading: false
    property string errorText: ""
    property var records: []

    function reload() {
        records = []
        nextUrl = "records/"
        loadMore()
    }

    function loadMore() {
        if (loading || !nextUrl)
            return
        loading = true
        api.request("GET", nextUrl, null, function(ok, status, data, error) {
            if (!ok) {
                loading = false
                page.errorText = error
                return
            }
            page.errorText = ""
            page.nextUrl = data.next || ""
            var results = data.results || []
            Store.ensureExercises(api, results.map(function(r) { return r.exercise }), function() {
                loading = false
                page.records = page.records.concat(results)
            })
        })
    }

    Component.onCompleted: reload()

    SilicaListView {
        id: list
        anchors.fill: parent
        model: page.records

        header: Column {
            width: parent.width
            PageHeader {
                title: qsTr("Personal records")
            }
            ErrorBanner {
                text: page.errorText
            }
        }

        PullDownMenu {
            busy: page.loading
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.reload()
            }
        }

        onAtYEndChanged: if (atYEnd && count > 0) page.loadMore()

        delegate: RecordItem {
            record: modelData
        }

        ViewPlaceholder {
            enabled: !page.loading && page.records.length === 0 && page.errorText === ""
            text: qsTr("No records yet")
            hintText: qsTr("Records are detected automatically from the sets you log")
        }

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: page.loading && page.records.length === 0
        }

        VerticalScrollDecorator {}
    }
}
