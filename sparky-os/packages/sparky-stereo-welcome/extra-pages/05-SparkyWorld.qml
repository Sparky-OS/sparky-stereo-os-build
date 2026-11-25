/*
 *  SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
 *
 *  SPDX-License-Identifier: GPL-3.0-or-later
 */

// Every element of SparkyLinux's own welcome window (Sparky Welcome 20250824~sparky9~0, by Paweł "pavroo"
// Pijanowski) in the Welcome Center, with the same address or command as its page and its handler: six pages, four
// programs (AppCenter, Upgrade, About, System info), nine community links and the news feed. Upgrade goes through
// sparky-stereo-welcome-upgrade, which does what the handler does: the upgrade, and on its first use the languages too.
// Sparky Welcome itself stays installed and in the menu as Welcome.
// A program that is missing or fails is said on the page, in the words Plasma Welcome gives (Utils.runCommand).

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

import org.kde.plasma.welcome as Welcome

Welcome.Page {
    id: root

    heading: i18ndc("sparky-stereo-welcome", "@title:window", "Welcome to the Sparky World!")
    description: xi18ndc("sparky-stereo-welcome", "@info:usagetip",
                         "Sparky Stereo OS is built on SparkyLinux, by Paweł “pavroo” Pijanowski. Everything SparkyLinux's own welcome window offers is here, and that window stays in the menu as Welcome.")

    readonly property var links: [
        [i18ndc("sparky-stereo-welcome", "@action:button", "Home page"), "https://sparkylinux.org/"],
        [i18ndc("sparky-stereo-welcome", "@action:button", "Forums"), "https://forum.sparkylinux.org/"],
        [i18ndc("sparky-stereo-welcome", "@action:button", "Wiki"), "https://wiki.sparkylinux.org/"],
        [i18ndc("sparky-stereo-welcome", "@action:button", "Git repo"), "https://github.com/sparkylinux"],
        [i18ndc("sparky-stereo-welcome", "@action:button", "Donate"), "https://sparkylinux.org/donate/"],
        [i18ndc("sparky-stereo-welcome", "@action:button", "Sponsors"), "https://sparkylinux.org/sponsoring/"]
    ]
    readonly property var programs: [
        [i18ndc("sparky-stereo-welcome", "@action:button", "AppCenter"), "system-software-install", "remsu /usr/bin/sparky-aptus-appcenter"],
        [i18ndc("sparky-stereo-welcome", "@action:button", "Upgrade"), "system-software-update", "/usr/bin/sparky-stereo-welcome-upgrade"],
        [i18ndc("sparky-stereo-welcome", "@action:button", "About"), "help-about", "/usr/bin/sparky-about"],
        [i18ndc("sparky-stereo-welcome", "@action:button", "System info"), "computer", "/usr/bin/sparky-system"]
    ]
    readonly property var community: [
        ["Facebook", "https://www.facebook.com/groups/SparkyLinux/"],
        ["X", "https://x.com/SparkyLinux"],
        ["MeWe", "https://mewe.com/join/sparkylinux"],
        ["Telegram", "https://t.me/sparkylinux"],
        ["Reddit", "https://www.reddit.com/r/SparkyLinuxOrg"],
        ["Patreon", "https://www.patreon.com/sparkylinux"],
        ["Mastodon", "https://mastodon.social/@SparkyLinux"],
        ["Signal", "https://signal.group/#CjQKIJTIFdCzG2za1ZC8TE8dxOkeMB_Q03oPTpddsEiVXtHdEhBZs7BP9ItOowNXF6J7GF4A"],
        ["Wikipedia", "https://en.wikipedia.org/wiki/SparkyLinux"],
        [i18ndc("sparky-stereo-welcome", "@action:button the news feed", "RSS"), "https://sparkylinux.org/feed/"]
    ]

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width, Kirigami.Units.gridUnit * 30)
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            id: failed
            objectName: "failed"
            Layout.fillWidth: true
            type: Kirigami.MessageType.Error
            showCloseButton: true
        }

        GridLayout {
            Layout.alignment: Qt.AlignHCenter
            columns: 2
            rowSpacing: Kirigami.Units.smallSpacing
            columnSpacing: Kirigami.Units.largeSpacing

            Repeater {
                model: root.links.length
                delegate: QQC2.Button {
                    required property int index
                    objectName: "link" + index
                    Layout.fillWidth: true
                    text: root.links[index][0]
                    icon.name: "internet-web-browser"
                    onClicked: Qt.openUrlExternally(root.links[index][1])
                }
            }
            Repeater {
                model: root.programs.length
                delegate: QQC2.Button {
                    required property int index
                    objectName: "program" + index
                    Layout.fillWidth: true
                    text: root.programs[index][0]
                    icon.name: root.programs[index][1]
                    onClicked: Welcome.Utils.runCommand(root.programs[index][2], (status, message) => {
                        if (status !== 0) {
                            failed.text = message;
                            failed.visible = true;
                        }
                    })
                }
            }
        }

        QQC2.Label {
            Layout.alignment: Qt.AlignHCenter
            text: i18ndc("sparky-stereo-welcome", "@title:group", "Keep in touch with Sparky community:")
        }

        Flow {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing
            Repeater {
                model: root.community.length
                delegate: Kirigami.UrlButton {
                    required property int index
                    objectName: "community" + index
                    text: root.community[index][0]
                    url: root.community[index][1]
                }
            }
        }
    }
}
