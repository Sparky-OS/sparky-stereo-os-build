// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: root

    readonly property var kinds: [
        { id: "none", text: i18nc("@option:radio", "None"), help: i18nc("@info", "Typical colour vision: nothing is changed.") },
        { id: "protan", text: i18nc("@option:radio", "Protan"), help: i18nc("@info", "Reds look darker, and red and green are hard to tell apart.") },
        { id: "deutan", text: i18nc("@option:radio", "Deutan"), help: i18nc("@info", "Red and green are hard to tell apart.") },
        { id: "tritan", text: i18nc("@option:radio", "Tritan"), help: i18nc("@info", "Blue and yellow, and blue and green, are hard to tell apart.") },
        { id: "mono", text: i18nc("@option:radio", "Monochromacy"), help: i18nc("@info", "No colours, only light and dark.") }
    ]

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: kcm.helperError.length > 0
            type: Kirigami.MessageType.Error
            text: kcm.helperError
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: i18nc("@info", "Choose your kind of colour vision. The desktop then keeps apart the colours that carry meaning: errors and successes, links, a terminal's prompt.")
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC2.ButtonGroup { id: kindGroup }

            Repeater {
                model: root.kinds
                delegate: ColumnLayout {
                    required property var modelData
                    required property int index
                    Kirigami.FormData.label: index === 0 ? i18nc("@label", "Colour vision:") : ""
                    spacing: 0
                    QQC2.RadioButton {
                        QQC2.ButtonGroup.group: kindGroup
                        text: modelData.text
                        checked: kcm.kind === modelData.id
                        onToggled: kcm.kind = modelData.id
                    }
                    QQC2.Label {
                        Layout.leftMargin: Kirigami.Units.gridUnit * 1.5
                        Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                        wrapMode: Text.WordWrap
                        font: Kirigami.Theme.smallFont
                        text: modelData.help
                    }
                }
            }

            QQC2.CheckBox {
                Kirigami.FormData.label: i18nc("@label", "Terminals:")
                text: i18nc("@option:check", "Also change the colours of Konsole, nano and the text console")
                checked: kcm.terminals
                enabled: kcm.kind !== "none"
                onToggled: kcm.terminals = checked
            }
        }

        Kirigami.Heading {
            level: 3
            text: i18nc("@title:group", "What is set now")
        }

        Repeater {
            model: kcm.surfaces
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: Kirigami.Units.iconSizes.small
                    implicitHeight: Kirigami.Units.iconSizes.small
                    source: modelData.icon
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: modelData.text
                }
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            // what red-cyan glasses show each kind, no output ranked (red-cyan is a first-class output; tritan: not measured, no hint)
            visible: kcm.kind === "protan" || kcm.kind === "deutan" || kcm.kind === "mono"
            type: Kirigami.MessageType.Information
            text: kcm.kind === "mono"
                ? i18nc("@info red-cyan glasses for monochromacy", "With red-cyan glasses you see 3D pictures with all their depth, as anyone does: each eye gets its own picture through its lens, and the colours play no part.")
                : i18nc("@info red-cyan glasses for protan and deutan colour vision", "With red-cyan glasses, 3D pictures keep all their depth for you, and fewer of their colours stay apart: the glasses rebuild the colours from red and cyan, and red and green already run together for you. A 3D television or another of the screen's 3D outputs keeps every colour.")
            actions: [
                Kirigami.Action {
                    icon.name: "preferences-desktop-display"
                    text: i18nc("@action:button", "Open Display Settings")
                    onTriggered: KCM.KCMLauncher.openSystemSettings("kcm_kscreen")
                }
            ]
        }

        RowLayout {
            Layout.fillWidth: true
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18nc("@info", "The strength of the screen correction is set on the Accessibility page, which shows this same choice.")
            }
            QQC2.Button {
                icon.name: "preferences-desktop-accessibility"
                text: i18nc("@action:button", "Open Accessibility")
                onClicked: KCM.KCMLauncher.openSystemSettings("kcm_access")
            }
        }
    }
}
