/*
 *  SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
 *
 *  SPDX-License-Identifier: GPL-3.0-or-later
 */

// Touch and tablet mode, written only from what the edition ships and what was measured (ORDER 63/720 milestone 2):
// - a tap opens a file or folder in Dolphin and on the desktop with KDE's double-click setting, where a mouse click only
//   selects it (Dolphin's KItemListController::onRelease(), the desktop's FolderView.qml; measured with a fake touch
//   screen beside the fake pointer); the task bar activates a window on a tap as on a click, and a long touch opens
//   its menu (plasma-desktop's Task.qml);
// - on a computer with a touch screen of its own, Plasma Keyboard is the on-screen keyboard in the session's language
//   (sparky-stereo-hardware's has-tablet-mode) and shows in tablet mode (Stereo KWin's InputMethodTabletOnly);
// - in tablet mode the panels hide and come back as they were (plasma-workspace, plasmarc [TabletMode] HidePanels).
// The page's condition: `show: true` shows it on every computer; `show: Welcome.Distro.flag("TouchScreen")` shows it only
// where the hardware layer found a touch screen of the computer's own (sparky-stereo-welcome-touch.sh sets the flag).

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

import org.kde.plasma.welcome as Welcome

Welcome.Page {
    id: root

    show: true

    heading: i18ndc("sparky-stereo-welcome", "@title:window", "Touch and Tablet Mode")
    description: xi18ndc("sparky-stereo-welcome", "@info:usagetip",
                         "On a touch screen a tap opens a file or folder in Dolphin and on the desktop, while the mouse keeps its own setting: a double click, or one click if you choose that in General Behavior. In the task bar, touch and hold a button for its menu.<nl/><nl/>On a computer with a touch screen of its own, the on-screen keyboard is Plasma Keyboard, in your language. It opens when you touch a text field in tablet mode, and in tablet mode the panels hide by themselves and come back as they were when you leave it.")

    topContent: [
        RowLayout {
            Layout.topMargin: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing
            QQC2.Button {
                objectName: "openGeneralBehavior"
                icon.name: "preferences-desktop"
                text: i18ndc("sparky-stereo-welcome", "@action:button", "Open General Behavior")
                onClicked: Welcome.Utils.launchApp("kcm_workspace")
            }
            QQC2.Button {
                objectName: "openVirtualKeyboard"
                icon.name: "input-keyboard-virtual"
                text: i18ndc("sparky-stereo-welcome", "@action:button", "Open Virtual Keyboard")
                onClicked: Welcome.Utils.launchApp("kcm_virtualkeyboard")
            }
        }
    ]

    // a tablet, its on-screen keyboard at the bottom, no panel
    Rectangle {
        anchors.centerIn: parent
        width: Kirigami.Units.gridUnit * 18
        height: Kirigami.Units.gridUnit * 11
        radius: Kirigami.Units.gridUnit
        color: "#2b3036"
        border.color: "#7a8592"
        border.width: 3

        Rectangle {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.gridUnit * 0.8
            color: "#e8edf2"

            Rectangle {
                x: parent.width * 0.08; y: parent.height * 0.12
                width: parent.width * 0.6; height: parent.height * 0.14
                color: "#ffffff"; border.color: "#3a6fa8"; border.width: 2
            }
            Grid {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: parent.height * 0.06
                columns: 10
                spacing: 3
                Repeater {
                    model: 30
                    Rectangle { width: Kirigami.Units.gridUnit * 1.2; height: Kirigami.Units.gridUnit * 0.9; radius: 2; color: "#7a8592" }
                }
            }
        }
    }
}
