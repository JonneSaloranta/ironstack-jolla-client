import QtQuick 2.0
import "../js/local/router.js" as Router

// Standalone mode's backend (docs/STANDALONE.md): registered with the
// ApiClient once, used whenever settings.standalone is on. The database
// is opened, and the built-in content brought in, on the first request.
QtObject {
    property bool initialized: false

    Component.onCompleted: {
        api.setLocalBackend(function(method, path, body) {
            if (!initialized) {
                Router.init(api.readData("seed.json"), api.dataUrl())
                initialized = true
            }
            return Router.handle(method, path, body)
        })
    }
}
