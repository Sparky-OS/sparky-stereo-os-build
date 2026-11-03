// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: root

    header: Kirigami.InlineMessage {
        visible: kcm.errorText.length > 0
        type: Kirigami.MessageType.Error
        text: kcm.errorText
        position: Kirigami.InlineMessage.Position.Header
    }

    Kirigami.FormLayout {
        QQC2.ButtonGroup {
            id: zramGroup
        }

        QQC2.RadioButton {
            Kirigami.FormData.label: i18nc("@label", "Compressed RAM swap (zram):")
            text: i18nc("@option:radio zram", "Automatic")
            checked: kcm.zramMode === 0
            onToggled: kcm.zramMode = 0
            QQC2.ButtonGroup.group: zramGroup
        }
        QQC2.RadioButton {
            text: i18nc("@option:radio zram", "On")
            checked: kcm.zramMode === 1
            onToggled: kcm.zramMode = 1
            QQC2.ButtonGroup.group: zramGroup
        }
        QQC2.RadioButton {
            text: i18nc("@option:radio zram", "Off")
            checked: kcm.zramMode === 2
            onToggled: kcm.zramMode = 2
            QQC2.ButtonGroup.group: zramGroup
        }
        QQC2.Label {
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.minimumWidth: 0
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            objectName: "automaticExplanation"
            text: kcm.autoDecisionText
        }
        QQC2.Label {
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.minimumWidth: 0
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: (kcm.zramActive ? i18nc("@info", "In use now.") : i18nc("@info", "Not in use now."))
                + " " + i18nc("@info", "A change applies at the next start.")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18nc("@label", "Cushion Swap File:")
            text: i18nc("@option:check", "Switch the swap area on only under memory pressure")
            checked: kcm.cushionEnabled
            onToggled: kcm.cushionEnabled = checked
        }
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: true
            type: kcm.cushionStatus === 0 ? Kirigami.MessageType.Positive
                : kcm.cushionStatus === 1 ? Kirigami.MessageType.Warning : Kirigami.MessageType.Error
            text: {
                switch (kcm.cushionStatus) {
                case 0: return i18nc("@info protection", "Memory protected");
                case 1: return i18nc("@info protection", "Memory protected, with a kept problem");
                case 2: return i18nc("@info protection", "Memory not protected");
                case 3: return i18nc("@info protection", "Cushion Swap is not running");
                default: return i18nc("@info protection", "Memory protection status could not be read");
                }
            }
        }
        QQC2.Label {
            visible: kcm.cushionStatusError.length > 0
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.minimumWidth: 0
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: kcm.cushionStatusError
        }
        QQC2.Label {
            objectName: "daemonReason"
            Kirigami.FormData.label: i18nc("@label", "Daemon’s own words:")
            visible: kcm.cushionReason.length > 0
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.minimumWidth: 0
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: kcm.cushionReason
        }
        QQC2.Label {
            Kirigami.FormData.label: i18nc("@label", "State:")
            text: {
                switch (kcm.cushionState) {
                case "off": return i18nc("@info cushion state", "Off");
                case "deployed": return i18nc("@info cushion state", "Deployed");
                case "retracting": return i18nc("@info cushion state", "Retracting");
                case "disabled": return i18nc("@info cushion state", "Switched off");
                case "no-area": return i18nc("@info cushion state", "No swap area configured");
                case "stopped": return i18nc("@info cushion state", "Not running");
                default: return i18nc("@info cushion state", "Unknown");
                }
            }
        }
        QQC2.Label {
            Kirigami.FormData.label: i18nc("@label", "Wake-up:")
            visible: kcm.cushionMode.length > 0
            text: kcm.cushionMode === "psi"
                ? i18nc("@info", "Pressure stall information (PSI): the kernel wakes it when memory stalls")
                : i18nc("@info", "Compatibility mode: no PSI, it checks memory every few seconds")
        }
        QQC2.Label {
            Kirigami.FormData.label: i18nc("@label", "Swap area:")
            visible: kcm.cushionArea.length > 0
            textFormat: Text.PlainText
            text: kcm.cushionArea
        }
        ColumnLayout {
            objectName: "problemActions"
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.minimumWidth: 0
            Repeater {
                model: kcm.cushionProblems
                delegate: ColumnLayout {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 24
                    Layout.minimumWidth: 0
                    QQC2.Label {
                        Layout.fillWidth: true
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
                        Layout.minimumWidth: 0
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        text: modelData.text
                    }
                    QQC2.Button {
                        objectName: "repairProblem"
                        visible: modelData.repair.length > 0
                        enabled: !kcm.repairing
                        text: i18nc("@action:button", "Repair")
                        onClicked: kcm.repairProblem(index)
                    }
                }
            }
            QQC2.Label {
                visible: kcm.cushionProblemsError.length > 0
                Layout.fillWidth: true
                Layout.preferredWidth: Kirigami.Units.gridUnit * 24
                Layout.minimumWidth: 0
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: kcm.cushionProblemsError
            }
            QQC2.Button {
                objectName: "refreshStatus"
                text: i18nc("@action:button", "Refresh status")
                enabled: !kcm.repairing
                onClicked: kcm.refreshStatus()
            }
        }
    }
}
