import QtQuick 2.6
import Sailfish.Silica 1.0
import QtMultimedia 5.6

// Scan a food package's barcode (EAN-13, EAN-8, UPC-E) with the camera.
// The viewfinder is grabbed a few times a second and read by
// BarcodeReader (src/barcode.cpp); a code read twice in a row is taken -
// scanned(code) fires and the page closes. The torch helps in a dim
// kitchen. Needs the sailjail Camera permission.
Page {
    id: page

    signal scanned(string code)

    property string lastRead: ""
    property bool done: false
    property bool grabbing: false
    property bool torch: false

    readonly property bool cameraReady: camera.cameraStatus === Camera.ActiveStatus
    readonly property bool cameraFailed: camera.availability !== Camera.Available
                                         || camera.errorCode !== Camera.NoError

    allowedOrientations: Orientation.Portrait

    function read() {
        if (done || grabbing || !cameraReady)
            return
        grabbing = true
        // A smaller grab is plenty for the reader and quick to make.
        viewfinder.grabToImage(function(result) {
            grabbing = false
            if (done)
                return
            var code = barcodeReader.decode(result.image)
            if (code && code === lastRead) {
                done = true
                timer.stop()
                page.scanned(code)
                pageStack.pop()
            }
            lastRead = code
        }, Qt.size(viewfinder.width, viewfinder.height))
    }

    Camera {
        id: camera
        captureMode: Camera.CaptureViewfinder
        focus.focusMode: Camera.FocusContinuous
        focus.focusPointMode: Camera.FocusPointCenter
        flash.mode: page.torch ? Camera.FlashVideoLight : Camera.FlashOff
        // Off whenever the page isn't on screen.
        cameraState: page.status === PageStatus.Active && Qt.application.active && !page.done
                     ? Camera.ActiveState : Camera.UnloadedState
    }

    VideoOutput {
        id: viewfinder
        anchors.fill: parent
        source: camera
        fillMode: VideoOutput.PreserveAspectCrop
        // No autoOrientation: Sailfish's camera already gives the picture
        // upright, as the system camera shows it; turning it again put it
        // 90 degrees off on the phone.
    }

    Timer {
        id: timer
        interval: 350
        repeat: true
        running: page.cameraReady && !page.done
        onTriggered: page.read()
    }

    // Where to hold the code.
    Rectangle {
        anchors.centerIn: parent
        width: parent.width * 0.8
        height: width * 0.45
        color: "transparent"
        border.color: Theme.highlightColor
        border.width: Math.max(2, Theme.paddingSmall / 2)
        radius: Theme.paddingSmall
        visible: !page.cameraFailed
    }

    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: header.height + hint.height + Theme.paddingLarge
        color: Theme.rgba("black", 0.5)
        PageHeader {
            id: header
            title: qsTr("Scan a barcode")
        }
        Label {
            id: hint
            anchors.top: header.bottom
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeSmall
            color: page.cameraFailed ? Theme.errorColor : Theme.highlightColor
            text: page.cameraFailed
                  ? qsTr("The camera can't be used. Check that IronStack may use it (Settings > Apps), or type the number instead.")
                  : qsTr("Hold the barcode inside the frame, about a hand's width away.")
        }
    }

    IconButton {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.paddingLarge * 2
        anchors.horizontalCenter: parent.horizontalCenter
        visible: !page.cameraFailed
        icon.source: page.torch ? "image://theme/icon-camera-flash-on" : "image://theme/icon-camera-flash-off"
        onClicked: page.torch = !page.torch
    }
}
