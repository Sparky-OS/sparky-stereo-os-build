/*
 *  SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
 *
 *  SPDX-License-Identifier: GPL-3.0-or-later
 */

// Sparky Stereo OS: the pointer decides which window takes the keys (focus follows the mouse, kwinrc [Windows] of
// sparky-stereo-look: FocusPolicy=FocusFollowsMouse, DelayFocusInterval=300, AutoRaise=true, AutoRaiseInterval=750,
// ClickRaise=true). The why is Daniel Ramos's: "less clicks, faster workflows, less health issues as a result";
// "mouse lasting more is also true". The button opens the setting's own page, Window Behavior (kcm_kwinoptions).
// The drawing of two windows already shows depth by its stacking; on a 3D screen it is drawn once per eye with
// stereo-layer's StereoDepth: the window under the pointer at the screen, the one behind it one layer back, the
// layer Stereo KWin gives the first window beneath the active one (a fifth of the person's sunk limit).

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Shapes

import org.kde.kirigami as Kirigami

import org.kde.plasma.welcome as Welcome
import org.sparky.stereo

Welcome.Page {
    id: root

    heading: i18ndc("sparky-stereo-welcome", "@title:window", "Point, Then Type")
    description: xi18ndc("sparky-stereo-welcome", "@info:usagetip",
                         "The window under the pointer is the one that gets your keys. Move the pointer onto a window and type: there is nothing to click. Leave the pointer there for a moment and the window comes to the front.<nl/><nl/>Why: fewer clicks and faster workflows, and fewer health problems as a result. Your mouse lasts longer too.<nl/><nl/>If what you type does not appear, look where the pointer is. To work another way, open Window Behavior in System Settings and choose how a window gets the focus.")

    topContent: [
        QQC2.Button {
            objectName: "openWindowBehavior"
            Layout.topMargin: Kirigami.Units.largeSpacing
            icon.name: "preferences-system-windows-behavior"
            text: i18ndc("sparky-stereo-welcome", "@action:button", "Open Window Behavior")
            onClicked: Welcome.Utils.launchApp("kcm_kwinoptions")
        }
    ]

    Item {
        id: drawing

        readonly property real fit: Math.min(1, root.width / 560, (root.height - root.header.height) / 340)

        anchors.centerIn: parent
        width: Math.round(480 * fit)
        height: Math.round(300 * fit)

        Accessible.role: Accessible.Graphic
        Accessible.name: i18ndc("sparky-stereo-welcome", "@info:accessible", "Two windows; the pointer rests on the front one, and the words typed appear there")

        // the window behind: one layer back on a 3D screen
        Rectangle {
            id: backWindow
            objectName: "backWindow"

            x: 0
            y: 0
            width: Math.round(drawing.width * 0.62)
            height: Math.round(drawing.height * 0.72)
            radius: 3
            color: "#5a6470"
            border.color: "#2b3036"
            StereoDepth.depth: -0.2

            Rectangle {
                x: 0
                y: 0
                width: parent.width
                height: Math.round(drawing.height * 0.09)
                radius: 3
                color: "#7a8592"
            }
            Repeater {
                model: 4
                Rectangle {
                    x: Math.round(drawing.width * 0.04)
                    y: Math.round(drawing.height * (0.17 + index * 0.1))
                    width: Math.round(backWindow.width * (index % 2 ? 0.55 : 0.75))
                    height: Math.round(drawing.height * 0.035)
                    radius: height / 2
                    color: "#77818d"
                }
            }
        }

        // the window under the pointer: at the screen, with the words typed
        Rectangle {
            id: frontWindow
            objectName: "frontWindow"

            x: Math.round(drawing.width * 0.34)
            y: Math.round(drawing.height * 0.26)
            width: Math.round(drawing.width * 0.64)
            height: Math.round(drawing.height * 0.72)
            radius: 3
            color: "#e8edf2"
            border.color: "#3a6fa8"
            StereoDepth.depth: StereoDepth.Screen

            Rectangle {
                x: 0
                y: 0
                width: parent.width
                height: Math.round(drawing.height * 0.09)
                radius: 3
                color: "#3a6fa8"
            }
            QQC2.Label {
                id: typed
                x: Math.round(drawing.width * 0.04)
                y: Math.round(drawing.height * 0.17)
                text: i18ndc("sparky-stereo-welcome", "@info drawn as words typed in a window", "Hello")
                color: "#1b1e21"
                font.pixelSize: Math.round(drawing.height * 0.08)
            }
            Rectangle {
                x: typed.x + typed.width + 2
                y: typed.y
                width: 2
                height: typed.height
                color: "#1b1e21"
            }
            // the pointer, resting on this window
            Shape {
                id: pointer

                x: Math.round(parent.width * 0.55)
                y: Math.round(parent.height * 0.45)
                width: Math.round(drawing.height * 0.14)
                height: width
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: "#ffffff"
                    strokeColor: "#1b1e21"
                    strokeWidth: 1.5
                    joinStyle: ShapePath.RoundJoin
                    startX: 0; startY: 0
                    PathLine { x: 0; y: pointer.height }
                    PathLine { x: pointer.width * 0.28; y: pointer.height * 0.74 }
                    PathLine { x: pointer.width * 0.48; y: pointer.height }
                    PathLine { x: pointer.width * 0.62; y: pointer.height * 0.92 }
                    PathLine { x: pointer.width * 0.42; y: pointer.height * 0.66 }
                    PathLine { x: pointer.width * 0.78; y: pointer.height * 0.66 }
                    PathLine { x: 0; y: 0 }
                }
            }
        }
    }
}
