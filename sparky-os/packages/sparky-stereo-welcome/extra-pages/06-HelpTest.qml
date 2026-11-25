/*
 *  SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
 *
 *  SPDX-License-Identifier: GPL-3.0-or-later
 */

// What the Welcome offers a tester, from what ships: stereo-display-info (sparky-stereo-info) prints what each display
// can do in stereo 3D and deep colour and what it is doing now, and the button copies it; the edition's tracker is the
// Bugs address of every package of the edition. A failure to run it is said on the page.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

import org.kde.plasma.welcome as Welcome

Welcome.Page {
    id: root

    heading: i18ndc("sparky-stereo-welcome", "@title:window", "Help Test Sparky Stereo OS")
    description: xi18ndc("sparky-stereo-welcome", "@info:usagetip",
                         "Tell us what works on your screens and what does not. Copy what your screens can do in 3D, then report it with what you saw.")

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width, Kirigami.Units.gridUnit * 30)
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            id: told
            objectName: "told"
            Layout.fillWidth: true
            showCloseButton: true
        }
        QQC2.Button {
            objectName: "copyScreens"
            Layout.alignment: Qt.AlignHCenter
            icon.name: "edit-copy"
            text: i18ndc("sparky-stereo-welcome", "@action:button", "Copy What My Screens Can Do")
            onClicked: Welcome.Utils.runCommand("stereo-display-info", (status, output) => {
                if (status === 0) {
                    Welcome.Utils.copyToClipboard(output);
                    told.type = Kirigami.MessageType.Positive;
                    told.text = i18ndc("sparky-stereo-welcome", "@info", "Copied: paste it into your report.");
                } else {
                    told.type = Kirigami.MessageType.Error;
                    told.text = output;
                }
                told.visible = true;
            })
        }
        Kirigami.UrlButton {
            objectName: "report"
            Layout.alignment: Qt.AlignHCenter
            text: i18ndc("sparky-stereo-welcome", "@action:button", "Report a problem")
            url: "https://github.com/Sparky-OS/sparky-stereo-os/issues"
        }
    }
}
