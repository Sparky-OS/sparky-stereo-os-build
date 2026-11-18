// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQml
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils
import org.sparky.stereo.headset

PlasmoidItem {
    id: root

    HeadsetStatus {
        id: headset
    }

    // The entry is in the tray only while a headset is connected (PassiveStatus puts it in the hidden part, which is empty without one)
    Plasmoid.icon: headset.iconName
    Plasmoid.status: headset.present ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus
    toolTipMainText: headset.present ? headset.name : i18n("Headset")
    toolTipSubText: headset.problem.length > 0 ? headset.problem : headset.batteryText

    compactRepresentation: MouseArea {
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                headset.set("Lights", !headset.lights);
            } else {
                root.expanded = !root.expanded;
            }
        }
        Kirigami.Icon {
            anchors.fill: parent
            source: headset.iconName
            active: parent.containsMouse
        }
        Rectangle {
            visible: headset.batteryKnown
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: Math.max(Kirigami.Units.gridUnit * 0.9, parent.width * 0.5)
            height: Math.max(Kirigami.Units.gridUnit * 0.5, parent.height * 0.28)
            radius: 2
            color: headset.battery <= 15 && !headset.charging ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.positiveTextColor
            Text {
                anchors.centerIn: parent
                text: headset.battery
                font.pixelSize: Math.max(parent.height * 0.85, 6)
                font.bold: true
                color: "white"
            }
        }
    }

    fullRepresentation: FullRepresentation {
        status: headset
        onOpenSettings: KCMUtils.KCMLauncher.openSystemSettings("kcm_sparkystereo_headset")
    }

    // The panel entry's menu: what the connected headset reports and HeadsetControl can set; nothing is listed that the headset lacks
    Plasmoid.contextualActions: [
        lightsAction,
        promptsAction,
        sidetoneOff, sidetoneLow, sidetoneMedium, sidetoneHigh
    ].concat(presetActions)

    property var presetActions: []

    // Plasma's own "Configure…" slot of an entry's menu opens the System Settings page (the entry has no settings of its own)
    PlasmaCore.Action {
        id: settingsAction
        text: i18n("Headset Settings…")
        icon.name: "configure"
        onTriggered: KCMUtils.KCMLauncher.openSystemSettings("kcm_sparkystereo_headset")
    }
    Component.onCompleted: Plasmoid.setInternalAction("configure", settingsAction)
    PlasmaCore.Action {
        id: lightsAction
        text: i18n("Lights")
        icon.name: "lighttable"
        visible: headset.hasLights
        checkable: true
        checked: headset.lights
        onTriggered: headset.set("Lights", !headset.lights)
    }
    PlasmaCore.Action {
        id: promptsAction
        text: i18n("Voice prompts")
        icon.name: "audio-input-microphone"
        visible: headset.hasVoicePrompts
        checkable: true
        checked: headset.voicePrompts
        onTriggered: headset.set("VoicePrompts", !headset.voicePrompts)
    }
    PlasmaCore.Action {
        id: sidetoneOff
        text: i18n("Sidetone: off")
        visible: headset.hasSidetone
        checkable: true
        checked: headset.sidetone === 0
        onTriggered: headset.set("Sidetone", 0)
    }
    PlasmaCore.Action {
        id: sidetoneLow
        text: i18n("Sidetone: low")
        visible: headset.hasSidetone
        checkable: true
        checked: headset.sidetone === 32
        onTriggered: headset.set("Sidetone", 32)
    }
    PlasmaCore.Action {
        id: sidetoneMedium
        text: i18n("Sidetone: medium")
        visible: headset.hasSidetone
        checkable: true
        checked: headset.sidetone === 64
        onTriggered: headset.set("Sidetone", 64)
    }
    PlasmaCore.Action {
        id: sidetoneHigh
        text: i18n("Sidetone: high")
        visible: headset.hasSidetone
        checkable: true
        checked: headset.sidetone === 96
        onTriggered: headset.set("Sidetone", 96)
    }

    Instantiator {
        model: headset.hasEqualizerPreset ? headset.presets : []
        delegate: PlasmaCore.Action {
            required property string modelData
            text: i18n("Equalizer: %1", modelData)
            checkable: true
            checked: headset.equalizerPreset === modelData
            onTriggered: headset.set("EqualizerPreset", modelData)
        }
        onObjectAdded: (index, object) => root.presetActions = root.presetActions.concat([object])
        onObjectRemoved: (index, object) => root.presetActions = root.presetActions.filter(a => a !== object)
    }
}
