/***************************************************************************
 *   Copyright (C) 2014 by Aleix Pol Gonzalez <aleixpol@blue-systems.com>  *
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This program is distributed in the hope that it will be useful,       *
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
 *   GNU General Public License for more details.                          *
 *                                                                         *
 *   You should have received a copy of the GNU General Public License     *
 *   along with this program; if not, write to the                         *
 *   Free Software Foundation, Inc.,                                       *
 *   51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA .        *
 ***************************************************************************/

// Qt 6 port 2026: Daniel Ramos (Capitain Jack), same licence

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

BreezeBlock {
    id: root
    property string mode: "shutdown"
    property var currentAction
    property real timeout: 30
    property real remainingTime: root.timeout
    property bool canReboot
    property bool canLogout
    property bool canShutdown
    onModeChanged: remainingTime = root.timeout

    signal cancel()
    signal shutdownRequested()
    signal rebootRequested()

    Shortcut {
        sequence: "Escape"
        onActivated: root.cancel()
    }

    onRemainingTimeChanged: {
        if(remainingTime<0)
            root.currentAction()
    }
    Timer {
        running: true
        repeat: true
        interval: 1000
        onTriggered: remainingTime--
    }

    main: ColumnLayout {
        spacing: 0
        BreezeHeading {
            id: actionLabel
            Layout.alignment: Qt.AlignHCenter
        }

        Item { height: Kirigami.Units.largeSpacing }

        Kirigami.Icon {
            id: actionIcon
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: true
            Layout.minimumWidth: height
            Layout.maximumWidth: height
            opacity: actionIconMouse.containsMouse ? 1 : 0.7
            MouseArea {
                id: actionIconMouse
                hoverEnabled: true
                anchors.fill: parent
                onClicked: root.currentAction();
            }
        }

        PlasmaComponents.ProgressBar {
            id: progressBar
            Layout.alignment: Qt.AlignHCenter

            //wanted to use actionIcon.paintedWidth but it doesn't work well when the image changes
            Layout.preferredWidth: Kirigami.Units.largeSpacing*7
            from: 0
            to: root.timeout
            value: root.remainingTime
        }

        BreezeLabel {
            Layout.alignment: Qt.AlignHCenter
            text: i18ndp("plasma_lookandfeel_org.kde.lookandfeel", "in 1 second", "in %1 seconds", root.remainingTime);
        }

        state: mode
        states: [
            State {
                name: "shutdown"
                PropertyChanges { target: root; currentAction: shutdownRequested }
                PropertyChanges { target: actionLabel; text: i18nd("plasma_lookandfeel_org.kde.lookandfeel","Shutting down") }
                PropertyChanges { target: actionIcon; source: "system-shutdown" }
            },
            State {
                name: "logout"
                PropertyChanges { target: root; currentAction: logoutRequested }
                PropertyChanges { target: actionLabel; text: i18nd("plasma_lookandfeel_org.kde.lookandfeel","Logging out") }
                PropertyChanges { target: actionIcon; source: "system-log-out" }
            },
            State {
                name: "reboot"
                PropertyChanges { target: root; currentAction: rebootRequested }
                PropertyChanges { target: actionLabel; text: i18nd("plasma_lookandfeel_org.kde.lookandfeel","Rebooting") }
                PropertyChanges { target: actionIcon; source: "system-reboot" }
            }
        ]
    }

    controls: Item {
        Layout.fillWidth: true
        height: buttons.height

        RowLayout {
            id: buttons
            anchors.centerIn: parent

            PlasmaComponents.Button {
                text: i18nd("plasma_lookandfeel_org.kde.lookandfeel","Cancel")
                onClicked: root.cancel()
            }

            PlasmaComponents.Button {
                id: commitButton
                onClicked: root.currentAction()
                focus: true

                function trigger() {
                    if (commitButton.activeFocus) {
                        root.currentAction()
                    }
                }

                Shortcut {
                    sequence: "Return"
                    onActivated: commitButton.trigger()
                }
                Shortcut {
                    sequence: "Enter" // on numpad
                    onActivated: commitButton.trigger()
                }
            }
        }

        LogoutOptions {
            id: logoutOptions
            anchors.right: parent.right
            anchors.rightMargin: 5
            canReboot: root.canReboot
            canLogout: root.canLogout
            canShutdown: root.canShutdown
            onModeChanged: root.mode = mode

            exclusive: true
            Component.onCompleted: mode = root.mode;
        }

        state: mode
        states: [
            State {
                name: "shutdown"
                PropertyChanges { target: commitButton; text: i18nd("plasma_lookandfeel_org.kde.lookandfeel","Shut down") }
            },
            State {
                name: "logout"
                PropertyChanges { target: commitButton; text: i18nd("plasma_lookandfeel_org.kde.lookandfeel","Log out") }
            },
            State {
                name: "reboot"
                PropertyChanges { target: commitButton; text: i18nd("plasma_lookandfeel_org.kde.lookandfeel","Reboot") }
            }
        ]
    }
}
