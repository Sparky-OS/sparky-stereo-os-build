// SPDX-License-Identifier: GPL-3.0-only
// Kubabbar Glass login screen: one window with a striped title bar, in plain Qt Quick (no SDDM components needed).
import QtQuick
import QtQuick.Controls.Basic

Rectangle {
    id: root
    width: 1280
    height: 800
    color: "#7e8f86"

    property string failure: ""

    Connections {
        target: sddm
        function onLoginFailed() {
            root.failure = textConstants.loginFailed
            password.text = ""
            password.forceActiveFocus()
        }
    }

    Image {
        anchors.fill: parent
        source: Qt.resolvedUrl("background.png")
        fillMode: Image.Tile
    }

    Rectangle {
        id: panel
        width: 440
        height: 330
        anchors.centerIn: parent
        color: "#d8d9d5"
        opacity: 0.91
        border.color: "#414740"
    }

    Item {
        anchors.fill: panel

        Rectangle {
            x: 1; y: 1
            width: parent.width - 2
            height: 28
            color: "#d8d9d5"
            Repeater {
                model: 6
                Rectangle { y: 6 + index * 3; width: parent.width; height: 1; color: "#abb0a8" }
            }
            Rectangle {
                anchors.centerIn: parent
                width: title.width + 16
                height: 20
                color: "#d8d9d5"
                Text {
                    id: title
                    anchors.centerIn: parent
                    text: "Kubabbar Glass"
                    color: "#1b2119"
                    font.pixelSize: 14
                }
            }
        }

        Column {
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 36; topMargin: 56 }
            spacing: 10

            Text { text: textConstants.userName; color: "#1b2119"; font.pixelSize: 13 }
            TextField {
                id: user
                width: parent.width
                text: userModel.lastUser
                color: "#1b2119"
                selectionColor: "#42572f"
                background: Rectangle { color: "#f9faf6"; border.color: user.activeFocus ? "#42572f" : "#7f8a76"; radius: 3 }
                KeyNavigation.tab: password
                onAccepted: password.forceActiveFocus()
            }
            Text { text: textConstants.password; color: "#1b2119"; font.pixelSize: 13 }
            TextField {
                id: password
                width: parent.width
                echoMode: TextInput.Password
                color: "#1b2119"
                selectionColor: "#42572f"
                focus: true
                background: Rectangle { color: "#f9faf6"; border.color: password.activeFocus ? "#42572f" : "#7f8a76"; radius: 3 }
                onAccepted: sddm.login(user.text, password.text, sessionBox.currentIndex)
            }
            Text { text: root.failure; color: "#9b2323"; font.pixelSize: 12; height: 14 }
            ComboBox {
                id: sessionBox
                width: parent.width
                model: sessionModel
                textRole: "name"
                currentIndex: sessionModel.lastIndex
                background: Rectangle { color: "#f3f5ee"; border.color: "#7f8a76"; radius: 3 }
                contentItem: Text { leftPadding: 8; text: sessionBox.displayText; color: "#1b2119"; verticalAlignment: Text.AlignVCenter }
            }
        }

        Row {
            anchors { right: parent.right; bottom: parent.bottom; margins: 24 }
            spacing: 8
            Button {
                text: textConstants.shutdown
                onClicked: sddm.powerOff()
                background: Rectangle { color: parent.down ? "#b9c1b5" : "#e8ebe1"; border.color: "#424a3e"; radius: 3 }
                contentItem: Text { text: parent.text; color: "#1b2119"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            }
            Button {
                text: textConstants.reboot
                onClicked: sddm.reboot()
                background: Rectangle { color: parent.down ? "#b9c1b5" : "#e8ebe1"; border.color: "#424a3e"; radius: 3 }
                contentItem: Text { text: parent.text; color: "#1b2119"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            }
            Button {
                text: textConstants.login
                onClicked: sddm.login(user.text, password.text, sessionBox.currentIndex)
                background: Rectangle { color: parent.down ? "#2f4121" : "#42572f"; border.color: "#2b3526"; radius: 3 }
                contentItem: Text { text: parent.text; color: "#fffffa"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            }
        }
    }
}
