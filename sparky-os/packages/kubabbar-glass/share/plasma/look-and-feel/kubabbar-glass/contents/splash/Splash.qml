// SPDX-License-Identifier: GPL-3.0-only
// Kubabbar Glass splash: a window with a striped title bar and a row of boxes that fill as the session starts.
import QtQuick

Rectangle {
    id: root
    color: "#7e8f86"

    property int stage

    onStageChanged: {
        if (stage >= 1) {
            introAnimation.running = true
        }
    }

    Image {
        anchors.fill: parent
        source: "images/background.png"
        fillMode: Image.Tile
    }

    Rectangle {
        id: panel
        width: 520
        height: 280
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height
        color: "#d8d9d5"
        opacity: 0.91
        border.color: "#414740"
        border.width: 1

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

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 78
            text: "Kubabbar Glass"
            color: "#1b2119"
            font.pixelSize: 40
            font.bold: true
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 134
            text: "Sparky Stereo OS"
            color: "#3e5231"
            font.pixelSize: 18
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 208
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
