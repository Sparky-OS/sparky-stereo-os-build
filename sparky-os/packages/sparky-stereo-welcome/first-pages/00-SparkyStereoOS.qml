/*
 *  SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
 *
 *  SPDX-License-Identifier: GPL-3.0-or-later
 */

// Sparky Stereo OS: the first page of Plasma Welcome, the edition in one screen.
// The picture is a stereo pair of the SparkyOS artwork (the installer's "any screen" slide, the same rectangle cut
// from both eyes), shown through stereo-layer's StereoPicture: full side by side on a surface of its own on a 3D
// screen, its left view on a 2D screen. The words and the button are the window's own, the same in both eyes.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

import org.kde.plasma.welcome as Welcome
import org.sparky.stereo

Welcome.Page {
    id: root

    heading: i18ndc("sparky-stereo-welcome", "@title:window", "Welcome to Sparky Stereo OS")
    description: xi18ndc("sparky-stereo-welcome", "@info:usagetip",
                         "Your whole desktop in 3D, on the 3D screen you already have: a 3D TV or projector, a VR headset, a glasses-free 3D display, or any monitor with red-cyan glasses. On a 2D monitor it is the desktop you know.<nl/><nl/>Each screen is turned to 3D in System Settings, Display Configuration.<nl/><nl/>Sparky Stereo OS is Daniel Ramos's edition of SparkyLinux (by Paweł “pavroo” Pijanowski), with KDE Plasma.")

    topContent: [
        QQC2.Button {
            objectName: "openDisplaySettings"
            Layout.topMargin: Kirigami.Units.largeSpacing
            icon.name: "preferences-desktop-display"
            text: i18ndc("sparky-stereo-welcome", "@action:button", "Open Display Configuration")
            onClicked: Welcome.Utils.launchApp("kcm_kscreen")
        }
    ]

    StereoPicture {
        id: picture

        readonly property real fit: Math.min(1, root.width / 600, (root.height - root.header.height) / 470)

        anchors.centerIn: parent
        width: Math.round(512 * fit)
        height: Math.round(400 * fit)
        source: "file:///usr/share/sparky-stereo-welcome/pictures/any-screen.pns"

        Accessible.role: Accessible.Graphic
        Accessible.name: i18ndc("sparky-stereo-welcome", "@info:accessible", "A 3D TV, a 3D monitor with its glasses, a monitor with red-cyan glasses and a VR headset")
    }
}
