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
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: kcm.autoZramOn
                ? i18nc("@info %1 is the reason", "Automatic means on for this computer: %1.", kcm.autoReason)
                : i18nc("@info %1 is the reason", "Automatic means off for this computer: %1.", kcm.autoReason)
        }
        QQC2.Label {
            Layout.fillWidth: true
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
        QQC2.Label {
            Kirigami.FormData.label: i18nc("@label", "State:")
            text: {
                switch (kcm.cushionState) {
                case "off": return i18nc("@info cushion state", "Off, ready");
                case "deployed": return i18nc("@info cushion state", "Deployed");
                case "retracting": return i18nc("@info cushion state", "Retracting");
                case "disabled": return i18nc("@info cushion state", "Switched off");
                case "no-area": return i18nc("@info cushion state", "No swap area configured");
                default: return i18nc("@info cushion state", "Not running");
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
            text: kcm.cushionArea
        }
    }
}
