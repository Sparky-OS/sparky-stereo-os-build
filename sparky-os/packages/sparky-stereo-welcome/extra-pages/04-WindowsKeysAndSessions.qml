/*
 *  SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
 *
 *  SPDX-License-Identifier: GPL-3.0-or-later
 */

// Keys and sessions as on Windows, written only from what the published packages ship (read 2026-11-25):
// - Ctrl+Alt+Del, Ctrl+Shift+Esc and Ctrl+Esc open System Monitor (sparky-stereo-look's kglobalaccel entry
//   org.sparkystereo.systemmonitor.desktop); Ctrl+Alt+Esc shows the logout screen (plasma-workspace +stereo3d6 and later);
//   Daniel, 2026-11-02: "so we keep the windows behaviour in the linux";
// - each login starts with an empty desktop and logging out does not ask (sparky-stereo-look's /etc/xdg/ksmserverrc:
//   loginMode=emptySession, confirmLogout=false); Daniel, 2026-11-17: "new session instead of continuing the last (in case
//   something is messing with the session) and don't ask for confirmation".
// The key names are the ones Qt shows in each language (de Strg, Entf, Umschalt; fr Suppr, Maj; es Supr, Mayús).

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

import org.kde.plasma.welcome as Welcome

Welcome.Page {
    id: root

    heading: i18ndc("sparky-stereo-welcome", "@title:window", "Keys and Sessions You Know from Windows")
    description: xi18ndc("sparky-stereo-welcome", "@info:usagetip",
                         "Ctrl+Alt+Del opens System Monitor, where you see what is running and can end a program that does not answer, as the Task Manager does on Windows; Ctrl+Shift+Esc and Ctrl+Esc open it too. Ctrl+Alt+Esc shows the logout screen, to log out, restart or shut down.<nl/><nl/>Each login starts with an empty desktop: the programs that were open when you logged out do not come back by themselves. Logging out, restarting and shutting down do not ask you to confirm.<nl/><nl/>Why: your hands already know these keys, and a fresh desktop at each login means a program that went wrong does not come back with it.<nl/><nl/>To change a key, open Shortcuts. To have the programs of your last session come back, or to be asked before logging out, open Desktop Session.")

    topContent: [
        RowLayout {
            Layout.topMargin: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing
            QQC2.Button {
                objectName: "openShortcuts"
                icon.name: "preferences-desktop-keyboard-shortcut"
                text: i18ndc("sparky-stereo-welcome", "@action:button", "Open Shortcuts")
                onClicked: Welcome.Utils.launchApp("kcm_keys")
            }
            QQC2.Button {
                objectName: "openDesktopSession"
                icon.name: "system-switch-user"
                text: i18ndc("sparky-stereo-welcome", "@action:button", "Open Desktop Session")
                onClicked: Welcome.Utils.launchApp("kcm_smserver")
            }
        }
    ]
}
