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

        // Each saved choice that cannot be used, and each failed step of the package: what failed, why and what to do;
        // the GPUs that can draw now are offered as buttons, the person's explicit choice (Apply saves it)
        Repeater {
            model: kcm.problems
            delegate: ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: true
                    type: Kirigami.MessageType.Error
                    text: modelData.text
                }
                Flow {
                    id: problemActions
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    readonly property string problemPackage: modelData.package || ""
                    readonly property string problemKey: modelData.key
                    Repeater {
                        model: modelData.actions || []
                        delegate: QQC2.Button {
                            required property var modelData
                            text: modelData.text
                            onClicked: kcm.runProblemAction(problemActions.problemPackage, problemActions.problemKey, modelData.id)
                        }
                    }
                }
                Flow {
                    id: problemGpus
                    Layout.fillWidth: true
                    visible: modelData.gpus.length > 0
                    spacing: Kirigami.Units.smallSpacing
                    Repeater {
                        model: modelData.gpus
                        delegate: QQC2.Button {
                            required property var modelData
                            icon.name: "video-card"
                            text: modelData.text
                            onClicked: kcm.useGpu(problemGpus.problemKey, modelData.id)
                        }
                    }
                    readonly property string problemKey: modelData.key
                }
            }
        }

        QQC2.CheckBox {
            objectName: "vramProtectionSwitch"
            Layout.fillWidth: true
            text: i18nc("@option:check", "Protect the video memory of the program in front")
            checked: kcm.vramProtection
            onToggled: kcm.vramProtection = checked
        }
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: i18nc("@info", "Background programs give up video memory first, and the program in front gets a higher CPU priority; changes take effect after a restart.")
        }

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
                            visible: modelData.drawsDesktop || modelData.runningDesktop
                            text: modelData.drawsDesktop && modelData.runningDesktop
                                ? i18nc("@label", "Draws the desktop")
                                : (modelData.drawsDesktop
                                    ? i18nc("@label", "Draws the desktop after the next login")
                                    : i18nc("@label", "Draws this session until the next login"))
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
                        visible: modelData.canRender && !modelData.accessible
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: i18nc("@info", "Your account may not use this GPU. Add it to the render group to send programs here.")
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
                onClicked: KCM.KCMLauncher.openSystemSettings("kcm_kscreen")
            }
            QQC2.Button {
                icon.name: "preferences-system-power-management"
                text: i18nc("@action:button", "Power Management…")
                onClicked: KCM.KCMLauncher.openSystemSettings("kcm_powerdevilprofilesconfig")
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
                currentIndex: count > 0 ? Math.max(0, indexOfValue(kcm.mainChoice)) : -1
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
            text: kcm.measuredText
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
                    currentIndex: count > 0 ? Math.max(0, indexOfValue(modelData.choice)) : -1
                    onActivated: kcm.setCategoryChoice(modelData.key, currentValue)
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font: Kirigami.Theme.smallFont
                        text: modelData.nowText
                    }
                    QQC2.Label {
                        visible: modelData.stereoText.length > 0
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font: Kirigami.Theme.smallFont
                        opacity: 0.8
                        text: modelData.stereoText
                    }
                }
            }
        }
        QQC2.Label {
            visible: kcm.multiGpu
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: i18nc("@info", "Players follow their choice from the next time they start. For a game in Steam, set its launch options to: sparky-stereo-gpu-run --category games %command%, and add --3d for a game you play in 3D. For any single program, use the list below.")
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        // ORDER 518: how programs made with Qt Widgets paint their windows. The three ways stay the person's choice;
        // Automatic is what was measured for that kind of program on this computer, and the processor without a measurement
        Kirigami.Heading {
            level: 2
            text: i18nc("@title:group", "Paint windows")
        }
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: i18nc("@info", "Programs made with Qt Widgets, such as Konsole, Dolphin and Kate, paint their windows on the processor or on the graphics card. Processor use depends on the program and hardware. A change applies the next time a program starts.")
        }
        Kirigami.InlineMessage {
            objectName: "paintSessionWarning"
            Layout.fillWidth: true
            visible: kcm.paintSetInSession
            type: Kirigami.MessageType.Warning
            text: i18nc("@info", "QT_WIDGETS_GPU_PAINT is set in this session and is used instead of these choices.")
        }
        Repeater {
            model: kcm.paintKinds
            delegate: RowLayout {
                Layout.fillWidth: true
                QQC2.Label {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                    text: modelData.label
                }
                QQC2.ComboBox {
                    objectName: "paintKind" + modelData.key
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 16
                    model: kcm.paintOptions
                    textRole: "text"
                    valueRole: "value"
                    currentIndex: count > 0 ? Math.max(0, indexOfValue(modelData.choice)) : -1
                    onActivated: kcm.setPaintKind(modelData.key, currentValue)
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
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: i18nc("@info", "A program started from a terminal or from Steam follows these choices when it is started with sparky-stereo-gpu-run. For any single program, use the list below.")
        }

        Kirigami.Separator {
            Layout.fillWidth: true
            visible: kcm.multiGpu || kcm.canPaintOnGpu
        }

        Kirigami.Heading {
            level: 2
            visible: kcm.multiGpu || kcm.canPaintOnGpu
            text: i18nc("@title:group", "Programs")
        }
        QQC2.Label {
            visible: kcm.multiGpu
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: i18nc("@info", "This is the same setting as Run Using Dedicated Graphics in the application menu. The dedicated GPU is the discrete GPU; when the GPU the computer starts with is already discrete, the program stays on it. A change applies the next time the program starts.")
        }
        Kirigami.SearchField {
            visible: kcm.multiGpu || kcm.canPaintOnGpu
            Layout.fillWidth: true
            onTextChanged: kcm.appFilter = text
        }
        ListView {
            id: appList
            visible: kcm.multiGpu || kcm.canPaintOnGpu
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 18
            clip: true
            model: (kcm.multiGpu || kcm.canPaintOnGpu) ? kcm.apps : []
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
                        visible: kcm.multiGpu
                        text: modelData.systemPrefersOther && modelData.preference === 1
                            ? i18nc("@info %1 is a GPU name", "Now: %1. The program asks for this itself.", modelData.nowText)
                            : i18nc("@info %1 is a GPU name", "Now: %1", modelData.nowText)
                        elide: Text.ElideRight
                        font: Kirigami.Theme.smallFont
                        opacity: 0.8
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: i18nc("@info %1 is a way of painting windows", "Windows painted: %1", modelData.paintText)
                        elide: Text.ElideRight
                        font: Kirigami.Theme.smallFont
                        opacity: 0.8
                    }
                }
                QQC2.ComboBox {
                    visible: kcm.multiGpu
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                    model: kcm.appOptions
                    textRole: "text"
                    valueRole: "value"
                    currentIndex: count > 0 ? Math.max(0, indexOfValue(modelData.preference)) : -1
                    onActivated: kcm.setAppPreference(modelData.id, currentValue)
                }
                QQC2.ComboBox {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 14
                    model: kcm.paintProgramOptions
                    textRole: "text"
                    valueRole: "value"
                    currentIndex: count > 0 ? Math.max(0, indexOfValue(modelData.paint)) : -1
                    onActivated: kcm.setPaintProgram(modelData.id, currentValue)
                }
            }
        }
        QQC2.Label {
            visible: (kcm.multiGpu || kcm.canPaintOnGpu) && kcm.hiddenApps > 0
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: i18ncp("@info %1 is a number", "%1 more program is not shown. Type part of its name to find it.", "%1 more programs are not shown. Type part of their name to find them.", kcm.hiddenApps)
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        Kirigami.Heading {
            level: 2
            text: i18nc("@title:group", "Video decoding")
        }
        QQC2.CheckBox {
            Layout.fillWidth: true
            text: i18nc("@option:check", "Copy decoded video back")
            checked: kcm.copyBack
            onToggled: kcm.copyBack = checked
        }
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: i18nc("@info", "Some players can use the GPU's video decoder only by copying every decoded picture back to the processor. On some computers that drops more frames than decoding in software. Players that show the decoded pictures where they are do not need it, and a decoder you choose in a player is always used.")
        }
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: kcm.copyBackMachineText
        }
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: kcm.copyBackSetInSession
            type: Kirigami.MessageType.Warning
            text: i18nc("@info", "MEDIA_GPU_ROUTE_COPY_BACK is set in this session and is used instead of this choice.")
        }
        QQC2.CheckBox {
            Layout.fillWidth: true
            visible: kcm.multiGpu
            text: i18nc("@option:check", "Decode on another GPU")
            checked: kcm.otherGpu
            onToggled: kcm.otherGpu = checked
        }
        QQC2.Label {
            visible: kcm.multiGpu
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: i18nc("@info", "When the GPU players use cannot decode a video in hardware, a player that copies decoded pictures back decodes it on another GPU that can. Off: such a video is decoded in software, and the player says so.")
        }
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: kcm.otherGpuSetInSession
            type: Kirigami.MessageType.Warning
            text: i18nc("@info", "MEDIA_GPU_ROUTE_OTHER_GPU is set in this session and is used instead of this choice.")
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
