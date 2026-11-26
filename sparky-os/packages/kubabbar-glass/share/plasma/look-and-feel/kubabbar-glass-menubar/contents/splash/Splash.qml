// SPDX-License-Identifier: GPL-3.0-only
// Kubabbar Glass, menu bar and dock: the clean boot background (the one the boot splash draws, without its logo), a
// menu bar strip with the launcher star above, and in the middle, one under the other: the Sparky logo when the system
// has it, the theme's name, the system's name and version from os-release and a bevelled progress bar.
// A distribution without the Sparky logo shows the theme's name in its place; the theme never carries the logo.
// On a 3D screen the background and the strip (it touches the screen's edges) stay at the screen and the middle stands
// at the person's popped limit (StereoDepth of org.sparky.stereo); on a 2D screen it is the same picture, plain.
import QtQuick
import org.kde.coreaddons
import org.sparky.stereo

Rectangle {
    id: root
    color: "#000000"

    property int stage

    // The edition's swirl, installed by its artwork package (sparkyos-artwork): white on clear, as it is drawn on the
    // dark background.
    readonly property url logoSource: "file:///usr/share/pixmaps/sparkyos.png"
    // KOSRelease gives os-release's own defaults (Linux, linux) when neither /etc/os-release nor /usr/lib/os-release
    // can be read; then only the theme's name is shown.
    readonly property bool osRead: !(KOSRelease.name === "Linux" && KOSRelease.id === "linux"
                                     && KOSRelease.prettyName === "Linux" && KOSRelease.version === ""
                                     && KOSRelease.versionId === "")
    readonly property string osName: osRead ? (KOSRelease.version !== "" ? KOSRelease.name + " " + KOSRelease.version
                                                                         : KOSRelease.name) : ""

    onStageChanged: {
        if (stage >= 1) {
            introAnimation.running = true
        }
    }

    Image {
        anchors.fill: parent
        source: "images/background.png"
        fillMode: Image.PreserveAspectCrop
        smooth: true
    }

    Rectangle {
        id: bar
        width: parent.width
        height: 24
        color: "#d8d9d5"
        opacity: 0.91
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: "#414740"
        }
        Image {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            height: 18
            source: "images/logo.svg"
            sourceSize: Qt.size(36, 36)
        }
    }

    Column {
        id: content
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height
        spacing: 18
        StereoDepth.depth: StereoDepth.Popped
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 96
            height: 96
            visible: status === Image.Ready
            source: root.logoSource
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Kubabbar Glass"
            color: "#f3f5ee"
            font.pixelSize: 34
            font.bold: true
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.osName !== ""
            text: root.osName
            color: "#f3f5ee"
            font.pixelSize: 16
        }
        Rectangle {
            id: track
            anchors.horizontalCenter: parent.horizontalCenter
            width: 280
            height: 14
            color: "#f3f5ee"
            border.color: "#424a3e"
            Rectangle {
                x: 2; y: 2
                height: parent.height - 4
                width: Math.max(0, Math.min(1, (root.stage - 1) / 5)) * (parent.width - 4)
                color: "#42572f"
                Behavior on width { NumberAnimation { duration: 300 } }
            }
        }
    }

    SequentialAnimation {
        id: introAnimation
        running: false
        PropertyAnimation {
            target: content
            property: "y"
            to: (root.height - content.height) / 2
            duration: 800
            easing.type: Easing.OutCubic
        }
    }
}
