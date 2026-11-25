// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ScrollView {
    id: page
    contentWidth: availableWidth
    clip: true

    ButtonGroup { id: periods }

    ColumnLayout {
        width: page.availableWidth
        spacing: 8

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("Choose when to clean the ticked items for this computer and the account you are creating. You can change this later in System Settings.")
        }

        Repeater {
            model: [
                {
                    value: "manual",
                    label: qsTr("Manually"),
                    help: qsTr("Review and confirm the items whenever you want to clean up.")
                },
                {
                    value: "weekly",
                    label: qsTr("Weekly"),
                    help: qsTr("Cleans the ticked items every week without asking again.")
                },
                {
                    value: "fortnightly",
                    label: qsTr("Every two weeks"),
                    help: qsTr("Cleans the ticked items every two weeks without asking again.")
                },
                {
                    value: "monthly",
                    label: qsTr("Monthly"),
                    help: qsTr("Cleans the ticked items every month without asking again.")
                }
            ]

            ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 0

                RadioButton {
                    Layout.fillWidth: true
                    text: modelData.label
                    Accessible.description: modelData.help
                    ButtonGroup.group: periods
                    checked: config.packageChoice === modelData.value
                    onClicked: config.packageChoice = modelData.value
                }

                Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: 26
                    text: modelData.help
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
