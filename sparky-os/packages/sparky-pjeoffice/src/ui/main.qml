// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: root

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: kcm.installedVersion.length === 0
            type: Kirigami.MessageType.Warning
            text: i18n("PJeOffice Pro is not installed. Install it from the app center.")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: kcm.installedVersion.length > 0 && !kcm.signerAnswers
            type: Kirigami.MessageType.Information
            text: i18n("The signer does not answer on this computer. Open it with the button below.")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: kcm.restartPending
            type: Kirigami.MessageType.Information
            text: i18n("The system's certificate list changed. Restart the signer to use it.")
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC2.CheckBox {
                Kirigami.FormData.label: i18n("At login:")
                text: i18n("Start PJeOffice Pro when I log in")
                checked: kcm.autostart
                onToggled: kcm.autostart = checked
            }

            QQC2.Label {
                Kirigami.FormData.label: i18n("Installed version:")
                text: kcm.installedVersion.length > 0 ? kcm.installedVersion : i18n("none")
            }

            QQC2.Label {
                Kirigami.FormData.label: i18n("Reviewed version:")
                text: kcm.reviewedVersion
            }

            QQC2.Label {
                Kirigami.FormData.label: i18n("Previous version kept:")
                visible: kcm.previousVersion.length > 0
                text: kcm.previousVersion
            }

            QQC2.Label {
                Kirigami.FormData.label: i18n("Update:")
                Layout.maximumWidth: Kirigami.Units.gridUnit * 30
                wrapMode: Text.WordWrap
                text: kcm.updateText
            }

            QQC2.Label {
                Kirigami.FormData.label: i18n("CNJ's address:")
                Layout.maximumWidth: Kirigami.Units.gridUnit * 30
                wrapMode: Text.WordWrap
                text: kcm.upstreamText
            }

            RowLayout {
                Kirigami.FormData.label: ""
                QQC2.Button {
                    icon.name: "view-refresh"
                    text: i18n("Check CNJ's update address")
                    onClicked: kcm.checkUpstream()
                }
            }

            RowLayout {
                Kirigami.FormData.label: ""
                QQC2.Button {
                    icon.name: "application-certificate"
                    text: i18n("Open the signer")
                    enabled: kcm.installedVersion.length > 0
                    onClicked: kcm.openSigner()
                }
                QQC2.Button {
                    icon.name: "preferences-desktop-user-password"
                    text: i18n("Open the certificate manager")
                    enabled: kcm.certificateToolInstalled
                    onClicked: kcm.openCertificateTool()
                }
            }

            QQC2.Label {
                Kirigami.FormData.label: ""
                visible: !kcm.certificateToolInstalled
                Layout.maximumWidth: Kirigami.Units.gridUnit * 30
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: i18n("The certificate manager (Kleopatra) is not installed.")
            }

            QQC2.Label {
                Kirigami.FormData.label: ""
                Layout.maximumWidth: Kirigami.Units.gridUnit * 30
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: i18n("Certificates, token drivers and PINs are set in the signer's own window. What the system trusts for secure connections is Sparky CA's.")
            }
        }
    }
}
