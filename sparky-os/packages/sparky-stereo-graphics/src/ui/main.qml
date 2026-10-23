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

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Heading {
            level: 2
            text: i18nc("@title:group", "Graphics processors")
        }
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: kcm.gpuCount === 0
                ? i18nc("@info", "No graphics processor was found.")
                : (kcm.multiGpu
                    ? i18ncp("@info %1 is a number", "This computer has %1 graphics processor.", "This computer has %1 graphics processors.", kcm.gpuCount)
                    : i18nc("@info", "This computer has one graphics processor. Every program draws on it."))
        }

        Repeater {
            model: kcm.gpus
            delegate: Kirigami.AbstractCard {
                Layout.fillWidth: true
                contentItem: ColumnLayout {
                    spacing: Kirigami.Units.smallSpacing
                    RowLayout {
                        Kirigami.Icon {
                            source: "video-card"
                            implicitWidth: Kirigami.Units.iconSizes.medium
                            implicitHeight: Kirigami.Units.iconSizes.medium
                        }
                        Kirigami.Heading {
                            level: 3
                            Layout.fillWidth: true
                            text: modelData.name
                            elide: Text.ElideRight
                        }
                        Kirigami.Chip {
                            text: modelData.kindText
                            checkable: false
                            closable: false
                        }
                        Kirigami.Chip {
                            visible: modelData.drawsDesktop
                            text: i18nc("@label", "Draws the desktop")
                            checkable: false
                            closable: false
                        }
                    }
                    QQC2.Label {
                        text: modelData.driverText
                        font: Kirigami.Theme.smallFont
                        opacity: 0.8
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: modelData.screensText
                        font: Kirigami.Theme.smallFont
                        opacity: 0.8
                    }
                    QQC2.Label {
                        visible: modelData.usedText.length > 0
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: modelData.usedText
                        font: Kirigami.Theme.smallFont
                    }
                    QQC2.Label {
                        visible: !modelData.canRender
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: i18nc("@info", "This chip only shows a picture. It cannot draw 3D or decode video, so it is never offered below.")
                        font: Kirigami.Theme.smallFont
                    }
                }
            }
        }

        RowLayout {
            QQC2.Button {
                icon.name: "preferences-desktop-display"
                text: i18nc("@action:button", "Display && Monitor…")
                onClicked: kcm.openModule("kcm_kscreen")
            }
            QQC2.Button {
                icon.name: "preferences-system-power-management"
                text: i18nc("@action:button", "Power Management…")
                onClicked: kcm.openModule("kcm_powerdevilprofilesconfig")
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        Kirigami.Heading {
            level: 2
            text: i18nc("@title:group", "Main desktop GPU")
        }
        RowLayout {
            Layout.fillWidth: true
            QQC2.Label {
                text: i18nc("@label:listbox", "Draws the desktop:")
            }
            QQC2.ComboBox {
                id: mainBox
                Layout.fillWidth: true
                enabled: kcm.multiGpu
                model: kcm.mainOptions
                textRole: "text"
                valueRole: "value"
                currentIndex: Math.max(0, indexOfValue(kcm.mainChoice))
                onActivated: kcm.mainChoice = currentValue
            }
        }
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: kcm.multiGpu
                ? i18nc("@info", "The desktop and every window are put together on this GPU. A change applies at the next login.")
                : i18nc("@info", "There is only one GPU to draw the desktop on.")
        }
        QQC2.Label {
            visible: kcm.multiGpu
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: kcm.mainAppliesLater
                ? i18nc("@info %1 is a GPU name", "This session still draws on %1 until you log in again.", kcm.mainNowText)
                : i18nc("@info %1 is a GPU name", "This session draws on %1.", kcm.mainNowText)
        }
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: kcm.mainSetByHand
            type: Kirigami.MessageType.Warning
            text: i18nc("@info", "A KWIN_DRM_DEVICES line in your own folder ~/.config/plasma-workspace/env is used instead of this choice.")
        }

        Kirigami.Separator {
            Layout.fillWidth: true
            visible: kcm.multiGpu
        }

        Kirigami.Heading {
            level: 2
            visible: kcm.multiGpu
            text: i18nc("@title:group", "Where programs draw")
        }
        QQC2.Label {
            visible: kcm.multiGpu
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: kcm.profileText
        }
        Repeater {
            model: kcm.multiGpu ? kcm.categories : []
            delegate: RowLayout {
                Layout.fillWidth: true
                QQC2.Label {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                    text: modelData.label
                }
                QQC2.ComboBox {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                    model: modelData.options
                    textRole: "text"
                    valueRole: "value"
                    currentIndex: Math.max(0, indexOfValue(modelData.choice))
                    onActivated: kcm.setCategoryChoice(modelData.key, currentValue)
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font: Kirigami.Theme.smallFont
                    text: modelData.nowText
                }
            }
        }
        QQC2.Label {
            visible: kcm.multiGpu
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: i18nc("@info", "Players follow their choice from the next time they start. For a game in Steam, set its launch options to: sparky-stereo-gpu-run --category games %command%. For any single program, use the list below.")
        }

        Kirigami.Separator {
            Layout.fillWidth: true
            visible: kcm.multiGpu
        }

        Kirigami.Heading {
            level: 2
            visible: kcm.multiGpu
            text: i18nc("@title:group", "Programs")
        }
        QQC2.Label {
            visible: kcm.multiGpu
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: i18nc("@info", "This is the same setting as Run Using Dedicated Graphics in the application menu. The other GPU is the one that does not draw the desktop. A change applies the next time the program starts.")
        }
        Kirigami.SearchField {
            visible: kcm.multiGpu
            Layout.fillWidth: true
            onTextChanged: kcm.appFilter = text
        }
        ListView {
            id: appList
            visible: kcm.multiGpu
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 18
            clip: true
            model: kcm.multiGpu ? kcm.apps : []
            QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
            delegate: RowLayout {
                width: appList.width - Kirigami.Units.gridUnit
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    source: modelData.icon
                    implicitWidth: Kirigami.Units.iconSizes.smallMedium
                    implicitHeight: Kirigami.Units.iconSizes.smallMedium
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: modelData.name
                        elide: Text.ElideRight
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: modelData.systemPrefersOther && modelData.preference === 1
                            ? i18nc("@info %1 is a GPU name", "Now: %1. The program asks for this itself.", modelData.nowText)
                            : i18nc("@info %1 is a GPU name", "Now: %1", modelData.nowText)
                        elide: Text.ElideRight
                        font: Kirigami.Theme.smallFont
                        opacity: 0.8
                    }
                }
                QQC2.ComboBox {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                    model: kcm.appOptions
                    textRole: "text"
                    valueRole: "value"
                    currentIndex: Math.max(0, indexOfValue(modelData.preference))
                    onActivated: kcm.setAppPreference(modelData.id, currentValue)
                }
            }
        }
        QQC2.Label {
            visible: kcm.multiGpu && kcm.hiddenApps > 0
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: i18ncp("@info %1 is a number", "%1 more program is not shown. Type part of its name to find it.", "%1 more programs are not shown. Type part of their name to find them.", kcm.hiddenApps)
        }

        Kirigami.Separator {
            Layout.fillWidth: true
            visible: kcm.powerActions.length > 0
        }

        Kirigami.Heading {
            level: 2
            visible: kcm.powerActions.length > 0
            text: i18nc("@title:group", "GPU power")
        }
        QQC2.Label {
            visible: kcm.powerActions.length > 0
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: i18nc("@info", "These save power when the power profile asks for it. They work for the graphics chip in this computer, with one GPU or several.")
        }
        Repeater {
            model: kcm.powerActions
            delegate: QQC2.CheckBox {
                Layout.fillWidth: true
                text: modelData.description
                checked: modelData.enabled
                onToggled: kcm.setPowerAction(modelData.name, checked)
            }
        }
    }
}
