// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

PlasmaExtras.Representation {
    id: full

    property var status
    signal openSettings

    Layout.minimumWidth: Kirigami.Units.gridUnit * 18
    Layout.minimumHeight: Kirigami.Units.gridUnit * 7
    Component.onCompleted: status.refresh()

    header: PlasmaExtras.PlasmoidHeading {
        RowLayout {
            anchors.fill: parent
            Kirigami.Icon {
                source: "audio-headset"
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            }
            PlasmaExtras.Heading {
                level: 3
                Layout.fillWidth: true
                text: full.status.present ? full.status.name : i18n("Headset")
                elide: Text.ElideRight
            }
            PlasmaComponents3.ToolButton {
                icon.name: "configure"
                text: i18n("Headset Settings…")
                display: QQC2.AbstractButton.IconOnly
                onClicked: full.openSettings()
                PlasmaComponents3.ToolTip { text: i18n("Headset Settings…") }
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        PlasmaExtras.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !full.status.present
            iconName: "audio-headset"
            text: i18n("No headset is connected.")
        }

        ColumnLayout {
            visible: full.status.present && full.status.hasBattery
            Layout.fillWidth: true
            PlasmaComponents3.ProgressBar {
                Layout.fillWidth: true
                from: 0
                to: 100
                value: full.status.batteryKnown ? full.status.battery : 0
                enabled: full.status.batteryKnown
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: full.status.batteryText
            }
        }

        // The same click actions as the entry's menu, for what the connected headset reports (nothing is shown that it lacks)
        PlasmaComponents3.Switch {
            visible: full.status.present && full.status.hasLights
            text: i18n("Lights")
            checked: full.status.lights
            onToggled: {
                full.status.set("Lights", checked);
                checked = Qt.binding(() => full.status.lights);
            }
        }
        PlasmaComponents3.Switch {
            visible: full.status.present && full.status.hasVoicePrompts
            text: i18n("Voice prompts")
            checked: full.status.voicePrompts
            onToggled: {
                full.status.set("VoicePrompts", checked);
                checked = Qt.binding(() => full.status.voicePrompts);
            }
        }
        PlasmaComponents3.ComboBox {
            id: sidetoneBox
            visible: full.status.present && full.status.hasSidetone
            Layout.fillWidth: true
            readonly property var levels: [0, 32, 64, 96]
            model: [i18n("Sidetone: off"), i18n("Sidetone: low"), i18n("Sidetone: medium"), i18n("Sidetone: high")]
            currentIndex: levels.indexOf(full.status.sidetone)
            displayText: currentIndex < 0 ? i18n("Sidetone (hear your own voice)") : currentText
            onActivated: index => full.status.set("Sidetone", levels[index])
        }
        PlasmaComponents3.ComboBox {
            visible: full.status.present && full.status.hasEqualizerPreset
            Layout.fillWidth: true
            model: full.status.presets
            currentIndex: full.status.presets.indexOf(full.status.equalizerPreset)
            displayText: currentIndex < 0 ? i18n("Equalizer preset") : i18n("Equalizer: %1", currentText)
            onActivated: index => full.status.set("EqualizerPreset", full.status.presets[index])
        }

        PlasmaComponents3.Label {
            visible: full.status.problem.length > 0
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Kirigami.Theme.negativeTextColor
            text: full.status.problem
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
