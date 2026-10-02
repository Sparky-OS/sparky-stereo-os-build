/*
 *   Copyright 2014 David Edmundson <davidedmundson@kde.org>
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU Library General Public License as
 *   published by the Free Software Foundation; either version 2 or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details
 *
 *   You should have received a copy of the GNU Library General Public
 *   License along with this program; if not, write to the
 *   Free Software Foundation, Inc.,
 *   51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

// Qt 6 port 2026: Daniel Ramos (Capitain Jack), same licence

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator

import SddmComponents

import "./components"

Image {
    id: root
    width: 1000
    height: 1000

    Repeater {
        model: screenModel
        Background {
            x: geometry.x; y: geometry.y; width: geometry.width; height:geometry.height
            source: Qt.resolvedUrl(config.background)
            fillMode: Image.PreserveAspectCrop
            onStatusChanged: {
                if (status == Image.Error && source != Qt.resolvedUrl("components/artwork/background.png")) {
                    source = Qt.resolvedUrl("components/artwork/background.png")
                }
            }
        }
    }

    property bool debug: false

    KeyboardIndicator.KeyState {
        id: capsLockState
        key: Qt.Key_CapsLock
    }

    Rectangle {
        id: debug3
        color: "green"
        visible: debug
        width: 3
        height: parent.height
        anchors.horizontalCenter: root.horizontalCenter
    }

    Controls.StackView {
        id: stackView

        //Display the loginpromt only in the primary screen
        readonly property rect geometry: screenModel.geometry(screenModel.primary)
        width: geometry.width
        x: geometry.x
        height: Kirigami.Units.largeSpacing*14
        //Display the BreezeBlock in the middle of each screen
        y: geometry.y + (geometry.height / 2) - (height / 2)

        initialItem: BreezeBlock {
            id: loginPrompt

            //Enable clipping whilst animating, otherwise the items would be shifted to other screens in multiscreen setups
            //As there are only 2 items (loginPrompt and logoutScreenComponent), it's sufficient to do it only in this component
            //Remember to enable clipping whilst animating when creating additional items for the StackView!
            Controls.StackView.onStatusChanged: {
                if(Controls.StackView.status === Controls.StackView.Activating || Controls.StackView.status === Controls.StackView.Deactivating){
                    stackView.clip = true;
                }else if(Controls.StackView.status === Controls.StackView.Active || Controls.StackView.status === Controls.StackView.Inactive){
                    stackView.clip = false;
                }
            }

            main: UserSelect {
                id: usersSelection
                model: userModel
                selectedIndex: userModel.lastIndex

                Connections {
                    target: sddm
                    function onLoginFailed() {
                        usersSelection.notification = i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Login Failed")
                    }
                }

            }

            controls: Item {
                height: childrenRect.height

                property alias password: passwordInput.text
                property alias sessionIndex: sessionCombo.currentIndex

                ColumnLayout {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 0
                    RowLayout {
                        //NOTE password is deliberately the first child so it gets focus
                        //be careful when re-ordering

                        Layout.alignment: Qt.AlignHCenter
                        PlasmaComponents.TextField {
                            id: passwordInput
                            placeholderText: i18nd("plasma_lookandfeel_org.kde.lookandfeel","Password")
                            echoMode: TextInput.Password
                            onAccepted: {
                                enabled = false
                                loginPrompt.startLogin()
                            }
                            focus: true

                            //focus works in qmlscene
                            //but this seems to be needed when loaded from SDDM
                            //I don't understand why, but we have seen this before in the old lock screen
                            Timer {
                                interval: 200
                                running: true
                                repeat: false
                                onTriggered: passwordInput.forceActiveFocus()
                            }
                            //end hack

                            Keys.onEscapePressed: {
                                //nextItemInFocusChain(false) is previous Item
                                nextItemInFocusChain(false).forceActiveFocus();
                            }

                            //if empty and left or right is pressed change selection in user switch
                            //this cannot be in keys.onLeftPressed as then it doesn't reach the password box
                            Keys.onPressed: (event) => {
                                if (event.key == Qt.Key_Left && !text) {
                                    loginPrompt.mainItem.decrementCurrentIndex();
                                    event.accepted = true
                                }
                                if (event.key == Qt.Key_Right && !text) {
                                    loginPrompt.mainItem.incrementCurrentIndex();
                                    event.accepted = true
                                }
                            }

                        }

                        PlasmaComponents.Button {
                            //this keeps the buttons the same width and thus line up evenly around the centre
                            Layout.minimumWidth: passwordInput.width
                            text: i18nd("plasma_lookandfeel_org.kde.lookandfeel","Login")
                            onClicked: loginPrompt.startLogin();
                        }
                    }

                    BreezeLabel {
                        id: capsLockWarning
                        text: i18nd("plasma_lookandfeel_org.kde.lookandfeel","Caps Lock is on")
                        visible: capsLockState.locked

                        Layout.alignment: Qt.AlignHCenter
                        font.weight: Font.Bold
                    }
                }

                PlasmaComponents.ComboBox {
                    id: sessionCombo
                    model: sessionModel
                    currentIndex: sessionModel.lastIndex

                    width: 200
                    textRole: "name"

                    anchors.left: parent.left
                }

                LogoutOptions {
                    mode: ""
                    canShutdown: true
                    canReboot: true
                    canLogout: false
                    exclusive: false

                    anchors {
                        right: parent.right
                    }

                    onModeChanged: {
                        if (mode) {
                            stackView.push(logoutScreenComponent, {"mode": mode})
                        }
                    }
                    onVisibleChanged: if(visible) {
                                          mode = ""
                                      }
                }

                Connections {
                    target: sddm
                    function onLoginFailed() {
                        passwordInput.enabled = true
                        passwordInput.selectAll()
                        passwordInput.forceActiveFocus()
                    }
                }

            }

            function startLogin () {
                sddm.login(mainItem.selectedUser, controlsItem.password, controlsItem.sessionIndex)
            }

            Component {
                id: logoutScreenComponent
                LogoutScreen {
                    onCancel: {
                        stackView.pop()
                    }

                    onShutdownRequested: {
                        sddm.powerOff()
                    }

                    onRebootRequested: {
                        sddm.reboot()
                    }
                }
            }
        }

    }
}
