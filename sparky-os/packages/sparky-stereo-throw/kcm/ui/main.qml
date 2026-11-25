// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// The devices found on the network, each as it names itself, with its Throw.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.ScrollViewKCM {
    id: root
    property bool opened: false

    Connections {
        target: kcm
        function onDevicesChanged() {
            if (root.opened || kcm.openDevice.length === 0) {
                return
            }
            for (const device of kcm.devices) {
                if (device.id === kcm.openDevice) {
                    root.opened = true
                    kcm.loadInfo(device.id)
                    kcm.push("DevicePage.qml", {"device": device})
                    return
                }
            }
        }
    }

    header: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: !kcm.serviceRunning
            type: Kirigami.MessageType.Error
            text: i18ndc("sparky-stereo-throw", "@info the daemon is not on the session bus", "The Throw service is not running (org.sparky.Throw).")
        }
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: kcm.lastError.length > 0
            type: Kirigami.MessageType.Error
            text: kcm.lastError
        }
    }

    view: ListView {
        id: list
        model: kcm.devices
        delegate: QQC2.ItemDelegate {
            id: item
            required property var modelData
            width: ListView.view.width
            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing
                Kirigami.Icon {
                    source: item.modelData.video ? "video-display" : "audio-speakers"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    QQC2.Label {
                        text: item.modelData.name
                        font.bold: true
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        opacity: 0.7
                        // the table's generation text, beside the model when it tells more than the model's own name
                        text: item.modelData.known
                              ? (item.modelData.generation === item.modelData.model ? item.modelData.model
                                 : i18ndc("sparky-stereo-throw", "@info a Cast device's model and what the model name tells; %1 model, %2 generation", "%1 — %2", item.modelData.model, item.modelData.generation))
                              : i18ndc("sparky-stereo-throw", "@info a Cast device whose model is not in the table; %1 its model", "%1 — not in the device table: the first Chromecast's limits are used", item.modelData.model)
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        // a failure is said whole: it wraps rather than run under the buttons
                        wrapMode: Text.Wrap
                        opacity: 0.7
                        text: item.modelData.state === "throwing" ? i18ndc("sparky-stereo-throw", "@info:status a Throw runs; %1 is the Cast device's name", "Throwing to %1.", item.modelData.name)
                              : item.modelData.state === "starting" ? i18ndc("sparky-stereo-throw", "@info:status a Throw is being set up", "Starting…")
                              : item.modelData.state === "failed" ? (item.modelData.detail || "")
                              : i18ndc("sparky-stereo-throw", "@info a Cast device's address and the mode its Throw uses; %1 address, %2 mode", "%1 · %2", item.modelData.address, item.modelData.mode)
                    }
                }
                QQC2.Button {
                    visible: item.modelData.video && item.modelData.state !== "throwing" && item.modelData.state !== "starting"
                    icon.name: "video-display"
                    text: i18ndc("sparky-stereo-throw", "@action:button start a Throw to this device", "Throw")
                    onClicked: kcm.throwTo(item.modelData.id)
                }
                QQC2.Button {
                    visible: item.modelData.state === "throwing" || item.modelData.state === "starting"
                    icon.name: "media-playback-stop"
                    text: i18ndc("sparky-stereo-throw", "@action:button end the running Throw", "Stop Throwing")
                    onClicked: kcm.stop(item.modelData.id)
                }
                QQC2.Button {
                    icon.name: "go-next"
                    text: i18ndc("sparky-stereo-throw", "@action:button open this device's page", "Details")
                    display: QQC2.AbstractButton.IconOnly
                    QQC2.ToolTip.text: text
                    QQC2.ToolTip.visible: hovered
                    onClicked: {
                        kcm.loadInfo(item.modelData.id)
                        kcm.push("DevicePage.qml", {"device": item.modelData})
                    }
                }
            }
        }

        Kirigami.PlaceholderMessage {
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.gridUnit * 4
            visible: list.count === 0 && kcm.serviceRunning
            icon.name: "network-wireless"
            text: i18ndc("sparky-stereo-throw", "@info no Cast device announced itself", "No Cast device found on this network.")
            explanation: i18ndc("sparky-stereo-throw", "@info", "A Chromecast, a Google TV or a TV with Google Cast built in appears here by itself when it is switched on and on the same network as this computer.")
        }
    }
}
