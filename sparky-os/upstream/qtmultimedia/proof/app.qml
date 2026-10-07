import QtQuick
import QtQuick.Window
import QtMultimedia

// Test player: a window with a background, a VideoOutput, and "controls" over the video.
// arguments: clip [input] [swap 0/1] [view] [scaling] [surface] [shape 0/1]
Window {
    id: win
    width: 1280; height: 800; visible: true; visibility: Window.FullScreen
    color: "#2a2a2a"
    readonly property var args: Qt.application.arguments.slice(Qt.application.arguments.indexOf("--") + 1)

    Rectangle { anchors.fill: parent; color: "#2a3a2a" }   // the app's own background, behind the video

    MediaPlayer {
        id: player
        source: "file://" + win.args[0]
        videoOutput: video
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput {}
        Component.onCompleted: play()
    }
    VideoOutput {
        id: video
        anchors.fill: parent
        stereoInput: win.args.length > 1 ? Number(win.args[1]) : VideoOutput.StereoAutomatic
        stereoSwapEyes: win.args.length > 2 && win.args[2] === "1"
        // what the build defaults to is left alone unless an argument is given ("-" is none)
        Component.onCompleted: {
            console.log("defaults: shapeFallback", stereoShapeFallback, "view", stereoView, "scaling", stereoScaling, "surface", stereoSurface)
            if (win.args.length > 3 && win.args[3] !== "-") stereoView = Number(win.args[3])
            if (win.args.length > 4 && win.args[4] !== "-") stereoScaling = Number(win.args[4])
            if (win.args.length > 5 && win.args[5] !== "-") stereoSurface = Number(win.args[5])
            if (win.args.length > 6 && win.args[6] !== "-") stereoShapeFallback = win.args[6] === "1"
        }
        onStereoVideoChanged: console.log("stereoVideo", stereoVideo, "packing", stereoPacking)
        onStereoLayerActiveChanged: console.log("stereoLayerActive", stereoLayerActive)
    }
    // tests of what the layer does when the item changes: resized after 4 s, hidden after 4 s
    Timer {
        interval: 4000; running: win.args.length > 7 && win.args[7] !== "-"
        onTriggered: {
            if (win.args[7] === "shrink") { video.anchors.margins = 100 }
            else if (win.args[7] === "hide") { video.visible = false }
            else if (win.args[7] === "showagain") { video.visible = false; showTimer.start() }
        }
    }
    Timer { id: showTimer; interval: 1500; onTriggered: video.visible = true }
    // the controls, over the video
    Rectangle {
        id: bar
        x: 40; y: parent.height - 90; width: parent.width - 80; height: 60
        color: "#101820"; border.color: "white"; border.width: 2
        Text { anchors.centerIn: parent; color: "white"; font.pixelSize: 28; text: "CONTROLS 00:00 ====o=====" }
    }
    Text { x: 10; y: 10; color: "white"; font.pixelSize: 20; text: "layer " + video.stereoLayerActive + " " + video.stereoPacking }
}
