import QtQuick 2.0

// Follows the sync queue for one endpoint a page logs to (`writes`, e.g.
// "measurements/"): synced() once a queued write reaches the server, so the
// page reloads, and failed(error) when the server rejected one.
Connections {
    property string writes
    signal synced(var data)
    signal failed(string error)

    target: syncQueue
    onItemSynced: {
        if (path === writes)
            synced(data)
    }
    onItemFailed: {
        if (path === writes)
            failed(error)
    }
}
