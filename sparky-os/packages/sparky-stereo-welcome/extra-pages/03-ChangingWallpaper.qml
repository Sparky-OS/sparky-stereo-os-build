/*
 *  SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
 *
 *  SPDX-License-Identifier: GPL-3.0-or-later
 */

// Stereo Variety, written only from what the published package does (variety 0.9.2-1+stereo3d1+lc1, read 2026-11-25):
// - it changes the wallpaper every 300 s while it runs (data/config/variety.conf: change_enabled, change_interval) and
//   starts only when it is opened; its first start shows its welcome and its privacy question (internet features), then
//   writes its own autostart entry (VarietyWindow.first_run, create_autostart_entry) and opens its Preferences;
// - its sources at first are folders of the computer (Favorites, Fetched, /usr/share/backgrounds); every online source
//   it knows is added unticked (Options.py); it has no rule for a metered connection;
// - "Change wallpaper every" and "Start Variety when the computer starts" are in its Preferences, the window the button
//   opens (variety --preferences). Its own words are quoted as its catalogues have them in each language.
// The page's condition: shown only where Variety is installed (sparky-stereo-welcome-variety.sh sets the flag).

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

import org.kde.plasma.welcome as Welcome

Welcome.Page {
    id: root

    show: Welcome.Distro.flag("Variety")

    heading: i18ndc("sparky-stereo-welcome", "@title:window", "A Wallpaper That Changes by Itself")
    description: xi18ndc("sparky-stereo-welcome", "@info:usagetip",
                         "Stereo Variety changes the wallpaper by itself while it runs, every five minutes. Open it with the button below: the first time, it greets you and asks whether it may use the internet, and from then on it starts at every login.<nl/><nl/>It shows the pictures of the sources ticked in its Preferences. At first only folders on this computer are ticked; an online source downloads only once you tick it. Variety does not tell a metered connection from any other, so on a metered connection keep the online sources unticked.<nl/><nl/>To keep the picture you have, untick “Change wallpaper every” in its Preferences. To stop Variety, untick “Start Variety when the computer starts” there too: it does not start again at the next login.")

    topContent: [
        ColumnLayout {
            Layout.topMargin: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            Kirigami.InlineMessage {
                id: failed
                objectName: "failed"
                Layout.fillWidth: true
                type: Kirigami.MessageType.Error
                showCloseButton: true
            }
            QQC2.Button {
                objectName: "openVarietyPreferences"
                icon.name: "variety"
                text: i18ndc("sparky-stereo-welcome", "@action:button", "Open Variety's Preferences")
                onClicked: Welcome.Utils.runCommand("variety --preferences", (status, message) => {
                    if (status !== 0) {
                        failed.text = message;
                        failed.visible = true;
                    }
                })
            }
        }
    ]
}
