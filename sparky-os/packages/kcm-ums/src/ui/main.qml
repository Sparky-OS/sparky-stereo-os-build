/*
    SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts

import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    Kirigami.FormLayout {
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Error
            text: kcm.errorMessage
            visible: kcm.errorMessage.length > 0
        }

        QQC2.Switch {
            id: serverSwitch
            Kirigami.FormData.label: i18n("Media server:")
            text: i18n("Share with the TVs and devices on the network")
            checked: kcm.serverEnabled
            onToggled: kcm.serverEnabled = checked
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: kcm.serverEnabled
                ? i18n("The server is on. The folders below are visible to every device on your network.")
                : i18n("The server is off. Nothing is shared.")
        }

        QQC2.TextField {
            Kirigami.FormData.label: i18n("Server name:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 20
            placeholderText: "Universal Media Server"
            text: kcm.serverName
            onTextEdited: kcm.serverName = text
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
        }

        ColumnLayout {
            Kirigami.FormData.label: i18n("Shared folders:")
            Kirigami.FormData.labelAlignment: Qt.AlignTop

            Repeater {
                model: kcm.folders

                RowLayout {
                    required property int index
                    required property string modelData

                    QQC2.Label {
                        Layout.fillWidth: true
                        text: modelData
                        elide: Text.ElideMiddle
                    }
                    QQC2.ToolButton {
                        icon.name: "list-remove"
                        text: i18n("Remove")
                        display: QQC2.AbstractButton.IconOnly
                        QQC2.ToolTip.text: text
                        QQC2.ToolTip.visible: hovered
                        onClicked: kcm.removeFolder(index)
                    }
                }
            }

            QQC2.Label {
                visible: kcm.folders.length === 0
                text: i18n("No folders are shared.")
                opacity: 0.7
            }

            RowLayout {
                QQC2.Button {
                    icon.name: "folder-add"
                    text: i18n("Add Folder…")
                    onClicked: folderDialog.open()
                }
                QQC2.Button {
                    icon.name: "edit-undo"
                    text: i18n("Restore Default Folders")
                    onClicked: kcm.restoreDefaultFolders()
                }
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
        }

        QQC2.Button {
            icon.name: "internet-services"
            text: i18n("Open Web Interface")
            onClicked: kcm.openWebInterface()
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            opacity: 0.7
            text: i18n("Devices, transcoding and everything else are set in the web interface.")
        }
    }

    FolderDialog {
        id: folderDialog
        title: i18n("Choose a Folder to Share")
        onAccepted: kcm.addFolder(selectedFolder)
    }
}
