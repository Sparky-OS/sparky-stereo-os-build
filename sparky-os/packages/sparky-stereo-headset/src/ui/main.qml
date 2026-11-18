// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: root

    property int pick: 0
    readonly property var headset: kcm.headsets.length > 0 ? kcm.headsets[Math.min(pick, kcm.headsets.length - 1)] : null

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: kcm.problem.length > 0
            type: Kirigami.MessageType.Error
            text: kcm.problem
        }

        Kirigami.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.gridUnit * 3
            visible: root.headset === null
            icon.name: "audio-headset"
            text: kcm.message.length > 0 ? kcm.message : i18n("No headset is connected.")
            explanation: i18n("Plug in a headset that HeadsetControl supports, or switch it on. Its settings appear here, and the choices you make come back when you connect the same headset again.")
        }

        QQC2.ComboBox {
            Layout.fillWidth: true
            visible: kcm.headsets.length > 1
            model: kcm.headsets.map(h => h.name)
            currentIndex: root.pick
            onActivated: index => root.pick = index
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true
            visible: root.headset !== null

            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: root.headset ? root.headset.name : ""
            }

            RowLayout {
                visible: root.headset !== null && root.headset.hasBattery
                Kirigami.FormData.label: i18n("Battery:")
                QQC2.ProgressBar {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                    from: 0
                    to: 100
                    value: root.headset && root.headset.batteryKnown ? root.headset.battery : 0
                    enabled: root.headset !== null && root.headset.batteryKnown
                }
                QQC2.Label {
                    text: root.headset ? root.headset.batteryText : ""
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }

            RowLayout {
                visible: root.headset !== null && root.headset.hasChatmix
                Kirigami.FormData.label: i18n("Chat mix:")
                QQC2.ProgressBar {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                    from: 0
                    to: 128
                    value: root.headset && root.headset.chatmix >= 0 ? root.headset.chatmix : 0
                }
                QQC2.Label {
                    text: i18n("Balance between game sound and chat sound")
                }
            }

            Repeater {
                model: root.headset ? root.headset.settings : []

                delegate: Loader {
                    required property var modelData
                    Kirigami.FormData.label: modelData.kind === "switch" ? "" : modelData.label + ":"
                    sourceComponent: modelData.kind === "switch" ? switchControl : modelData.kind === "number" ? numberControl : choiceControl
                    onLoaded: item.setting = modelData
                }
            }

            QQC2.Label {
                visible: root.headset !== null && root.headset.settings.length > 0
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                wrapMode: Text.Wrap
                opacity: 0.7
                text: i18n("Only the settings you change here are sent to the headset and kept. The others stay as the headset has them.")
            }
        }
    }

    Component {
        id: switchControl
        QQC2.CheckBox {
            property var setting
            text: setting ? setting.label : ""
            checked: setting ? setting.value : false
            onToggled: kcm.stage(root.headset.id, setting.key, checked)
        }
    }

    Component {
        id: numberControl
        RowLayout {
            id: numberRow
            property var setting
            // the range first, then the value: a value set before its range is clamped to the old one
            onSettingChanged: {
                if (setting) {
                    slider.from = setting.min;
                    slider.to = setting.max;
                    slider.value = setting.value;
                }
            }
            QQC2.Slider {
                id: slider
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                stepSize: 1
                from: 0
                to: 128
                onMoved: kcm.stage(root.headset.id, setting.key, Math.round(value))
            }
            QQC2.Label {
                text: Math.round(slider.value)
            }
        }
    }

    Component {
        id: choiceControl
        QQC2.ComboBox {
            property var setting
            model: setting ? setting.choices : []
            currentIndex: setting ? Math.max(0, setting.choices.indexOf(setting.value)) : 0
            onActivated: index => kcm.stage(root.headset.id, setting.key, setting.choices[index])
        }
    }
}
