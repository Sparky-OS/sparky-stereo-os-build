// SPDX-License-Identifier: GPL-3.0-only
// Kubabbar Glass, menu bar and dock: the launcher star on the quiet pattern, a menu bar strip above and a bevelled progress bar below.
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
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 160
            height: 160
            source: "images/logo.svg"
            sourceSize: Qt.size(320, 320)
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Kubabbar Glass"
            color: "#1b2119"
            font.pixelSize: 34
            font.bold: true
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Sparky Stereo OS"
            color: "#3e5231"
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
