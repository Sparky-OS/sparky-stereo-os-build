// SPDX-License-Identifier: GPL-3.0-only
// Kubabbar Glass splash: the clean boot background (the one the boot splash draws, without its logo) and, on it, a
// window with a striped title bar and a row of boxes that fill as the session starts. Inside the window, one under the
// other: the Sparky logo when the system has it, the theme's name, and the system's name and version from os-release.
// A distribution without the Sparky logo shows the theme's name in its place; the theme never carries the logo.
// On a 3D screen the background stays at the screen, as at boot, and the window with everything in it stands at the
// person's popped limit (StereoDepth of org.sparky.stereo); on a 2D screen it is the same picture, plain.
import QtQuick
import QtQuick.Effects
import org.kde.coreaddons
import org.sparky.stereo

Rectangle {
    id: root
    color: "#000000"

    property int stage

    // The edition's swirl, installed by its artwork package (sparkyos-artwork): white on clear, drawn here in the
    // window's text colour so that it reads on the light glass.
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
        id: panel
        width: 520
        height: titleBar.height + 2 + content.implicitHeight + 2 * 22
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height
        color: "#d8d9d5"
        opacity: 0.91
        border.color: "#414740"
        border.width: 1
        StereoDepth.depth: StereoDepth.Popped

        Rectangle {
            id: titleBar
            x: 1; y: 1
            width: parent.width - 2
            height: 28
            color: "#d8d9d5"
            Repeater {
                model: 6
                Rectangle {
                    x: 0; y: 6 + index * 3
                    width: parent.width; height: 1
                    color: "#abb0a8"
                }
            }
            Rectangle {
                anchors.centerIn: parent
                width: titleText.width + 16
                height: 20
                color: "#d8d9d5"
                Text {
                    id: titleText
                    anchors.centerIn: parent
                    text: "Kubabbar Glass"
                    color: "#1b2119"
                    font.pixelSize: 14
                }
            }
            Rectangle {
                x: 9; y: 6
                width: 16; height: 16
                radius: 3
                color: "#e8ebe1"
                border.color: "#424a3e"
            }
        }

        Column {
            id: content
            anchors.horizontalCenter: parent.horizontalCenter
            y: titleBar.height + 1 + 22
            spacing: 10

            Item {
                id: logo
                anchors.horizontalCenter: parent.horizontalCenter
                width: 80
                height: 80
                visible: logoImage.status === Image.Ready
                Image {
                    id: logoImage
                    anchors.fill: parent
                    source: root.logoSource
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: logoImage
                    colorization: 1.0
                    colorizationColor: "#1b2119"
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Kubabbar Glass"
                color: "#1b2119"
                font.pixelSize: 32
                font.bold: true
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.osName !== ""
                text: root.osName
                color: "#2f3e25"
                font.pixelSize: 18
            }
            Item {
                width: 1
                height: 8
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                Repeater {
                    model: 8
                    Rectangle {
                        width: 28; height: 14
                        radius: 2
                        border.color: "#424a3e"
                        color: (index + 1) * 6 / 8 <= root.stage - 1 + 0.01 ? "#42572f" : "#f3f5ee"
                        Behavior on color { ColorAnimation { duration: 250 } }
                    }
                }
            }
        }
    }

    SequentialAnimation {
        id: introAnimation
        running: false
        PropertyAnimation {
            target: panel
            property: "y"
            to: (root.height - panel.height) / 2
            duration: 800
            easing.type: Easing.OutCubic
        }
    }
}
