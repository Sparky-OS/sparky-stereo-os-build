import QtQuick
import QtQuick.Window
import QtMultimedia

// The same window without any of the stereo properties: runs on Debian's Qt Multimedia as well as ours.
// arguments: clip
Window {
    id: win
    width: 1280; height: 800; visible: true; visibility: Window.FullScreen
    color: "#2a2a2a"
    readonly property var args: Qt.application.arguments.slice(Qt.application.arguments.indexOf("--") + 1)
    Rectangle { anchors.fill: parent; color: "#2a3a2a" }
    MediaPlayer {
        id: player
        source: "file://" + win.args[0]
        videoOutput: video
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput {}
        Component.onCompleted: play()
    }
    VideoOutput { id: video; anchors.fill: parent }
    Rectangle {
        x: 40; y: parent.height - 90; width: parent.width - 80; height: 60
        color: "#101820"; border.color: "white"; border.width: 2
        Text { anchors.centerIn: parent; color: "white"; font.pixelSize: 28; text: "CONTROLS 00:00 ====o=====" }
    }
    Text { x: 10; y: 10; color: "white"; font.pixelSize: 20; text: "plain" }
}
