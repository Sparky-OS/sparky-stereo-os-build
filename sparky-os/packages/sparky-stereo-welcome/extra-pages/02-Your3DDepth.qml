/*
 *  SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
 *
 *  SPDX-License-Identifier: GPL-3.0-or-later
 */

// The person's depth, set in one place: the edition's contract (Daniel, 2026-11-19: one separation setting, centralized,
// tailored to the screen, not to the element size; the person's depth limits never change with the presenting resolution
// or with the size of a window, 3D area, picture, thumbnail or icon, and no program or layer rescales them). The one place
// is Stereo KWin's 3D Depth page (kcm_kwinstereodepth, kwinrc [StereoDepth] SunkLimit and PoppedLimit, under Display), for
// a display in one of its 3D modes. The why is the limits' own commit's: how much depth is a matter of taste.
// The drawing is the desktop's three levels, drawn once per eye on a 3D screen with stereo-layer's StereoDepth: the
// wallpaper at the person's sunk limit, the window at the screen, its menu at the popped limit; flat on a 2D screen.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

import org.kde.plasma.welcome as Welcome
import org.sparky.stereo

Welcome.Page {
    id: root

    heading: i18ndc("sparky-stereo-welcome", "@title:window", "Your 3D Depth, Set Once")
    description: xi18ndc("sparky-stereo-welcome", "@info:usagetip",
                         "How far the desktop reaches behind the screen and how far it comes out in front of it is your choice, made in one place: the 3D Depth page in System Settings.<nl/><nl/>Everything on the desktop stays inside those limits. They are set for your screen and stay the same whatever the size of a window, a picture or an icon, and whatever resolution a program draws at; no program changes them.<nl/><nl/>Why: how much depth is comfortable is a matter of taste, so you set it once and the whole desktop follows.<nl/><nl/>On a 2D screen the desktop is flat and nothing changes. Your limits are kept for a 3D screen: they apply when one is connected, or when a screen is switched to one of its 3D modes.")

    topContent: [
        QQC2.Button {
            objectName: "open3DDepth"
            Layout.topMargin: Kirigami.Units.largeSpacing
            icon.name: "preferences-desktop-display"
            text: i18ndc("sparky-stereo-welcome", "@action:button", "Open 3D Depth")
            onClicked: Welcome.Utils.launchApp("kcm_kwinstereodepth")
        }
    ]

    Item {
        id: drawing

        readonly property real fit: Math.min(1, root.width / 560, (root.height - root.header.height) / 300)

        anchors.centerIn: parent
        width: Math.round(440 * fit)
        height: Math.round(250 * fit)

        Accessible.role: Accessible.Graphic
        Accessible.name: i18ndc("sparky-stereo-welcome", "@info:accessible", "The desktop in depth: the wallpaper behind the screen, a window at the screen, its menu in front of it")

        // the wallpaper: at the person's sunk limit on a 3D screen
        Rectangle {
            objectName: "wallpaper"
            anchors.fill: parent
            radius: 3
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#3a6fa8" }
                GradientStop { position: 1.0; color: "#1b2a3a" }
            }
            StereoDepth.depth: StereoDepth.Sunk
        }

        // the window: at the screen
        Rectangle {
            id: window
            objectName: "window"

            x: Math.round(drawing.width * 0.14)
            y: Math.round(drawing.height * 0.16)
            width: Math.round(drawing.width * 0.56)
            height: Math.round(drawing.height * 0.68)
            radius: 3
            color: "#e8edf2"
            border.color: "#2b3036"
            StereoDepth.depth: StereoDepth.Screen

            Rectangle {
                width: parent.width
                height: Math.round(drawing.height * 0.1)
                radius: 3
                color: "#7a8592"
            }
            Repeater {
                model: 3
                Rectangle {
                    x: Math.round(drawing.width * 0.04)
                    y: Math.round(drawing.height * (0.18 + index * 0.1))
                    width: Math.round(window.width * (index % 2 ? 0.5 : 0.7))
                    height: Math.round(drawing.height * 0.035)
                    radius: height / 2
                    color: "#a9b2bc"
                }
            }
        }

        // its menu: at the person's popped limit
        Rectangle {
            objectName: "menu"

            x: Math.round(drawing.width * 0.5)
            y: Math.round(drawing.height * 0.38)
            width: Math.round(drawing.width * 0.3)
            height: Math.round(drawing.height * 0.4)
            radius: 3
            color: "#ffffff"
            border.color: "#3a6fa8"
            border.width: 2
            StereoDepth.depth: StereoDepth.Popped

            Repeater {
                model: 3
                Rectangle {
                    x: Math.round(drawing.width * 0.025)
                    y: Math.round(drawing.height * (0.06 + index * 0.11))
                    width: Math.round(drawing.width * 0.22)
                    height: Math.round(drawing.height * 0.05)
                    radius: 2
                    color: index === 1 ? "#3a6fa8" : "#c9d1d9"
                }
            }
        }
    }
}
