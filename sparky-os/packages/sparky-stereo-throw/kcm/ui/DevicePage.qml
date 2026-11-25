// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// One device: what it says about itself, what can be set here without an account (its volume), and what needs the
// person's Google account.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page
    property var device: ({})
    readonly property var info: kcm.infoId === device.id ? kcm.info : ({})
    readonly property var eureka: info.eureka || ({})
    readonly property var deviceInfo: eureka.device_info || ({})
    readonly property var build: (info.build || {}).build_info || ({})
    readonly property var volume: (info.receiver || {}).volume || ({})
    readonly property bool volumeKnown: volume.level !== undefined

    title: device.name || ""

    Kirigami.FormLayout {
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18ndc("sparky-stereo-throw", "@title:group what the device says about itself", "This device")
        }
        QQC2.BusyIndicator {
            visible: kcm.infoLoading
            running: visible
        }
        QQC2.Label {
            Kirigami.FormData.label: i18ndc("sparky-stereo-throw", "@label the name the person gave the device", "Name:")
            text: eureka.name || device.name || ""
        }
        QQC2.Label {
            Kirigami.FormData.label: i18ndc("sparky-stereo-throw", "@label", "Model:")
            text: deviceInfo.model_name || device.model || ""
        }
        QQC2.Label {
            Kirigami.FormData.label: i18ndc("sparky-stereo-throw", "@label", "Maker:")
            visible: !!deviceInfo.manufacturer
            text: deviceInfo.manufacturer || ""
        }
        QQC2.Label {
            Kirigami.FormData.label: i18ndc("sparky-stereo-throw", "@label what the model name tells about the device", "Generation:")
            text: device.generation || ""
        }
        QQC2.Label {
            Kirigami.FormData.label: i18ndc("sparky-stereo-throw", "@label", "Address:")
            text: device.address || device.host || ""
        }
        QQC2.Label {
            Kirigami.FormData.label: i18ndc("sparky-stereo-throw", "@label the device's software version", "Firmware:")
            text: build.cast_build_revision || i18ndc("sparky-stereo-throw", "@info the device did not give it", "not given by the device")
        }
        QQC2.Label {
            Kirigami.FormData.label: i18ndc("sparky-stereo-throw", "@label the picture a Throw sends", "Throw mode:")
            text: i18ndc("sparky-stereo-throw", "@info %1 the mode, %2 the codec, %3 its level", "%1, %2 level %3", device.mode || "", device.codec || "", device.level || "")
        }
        QQC2.Button {
            visible: device.state === "throwing"
            icon.name: "preferences-desktop-display"
            text: i18ndc("sparky-stereo-throw", "@action:button the network screen's 3D format and eye swap are in Display Settings", "3D Format and Eye Swap…")
            onClicked: kcm.openDisplaySettings()
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18ndc("sparky-stereo-throw", "@title:group settings the device takes from this computer with no account", "Set from here")
        }
        RowLayout {
            Kirigami.FormData.label: i18ndc("sparky-stereo-throw", "@label the device's own volume", "Volume:")
            enabled: page.volumeKnown && page.volume.controlType !== "fixed"
            QQC2.Slider {
                id: slider
                from: 0
                to: 1
                stepSize: page.volume.stepInterval || 0.05
                value: page.volume.level || 0
                onMoved: kcm.setVolume(device.id, value, -1)
            }
            QQC2.Label {
                text: page.volumeKnown ? i18ndc("sparky-stereo-throw", "@info a percentage", "%1%", Math.round((page.volume.level || 0) * 100)) : ""
            }
        }
        QQC2.CheckBox {
            enabled: page.volumeKnown
            text: i18ndc("sparky-stereo-throw", "@option:check the device's sound off", "Muted")
            checked: !!page.volume.muted
            onToggled: kcm.setVolume(device.id, -1, checked ? 1 : 0)
        }
        QQC2.Label {
            visible: page.volume.controlType === "fixed"
            text: i18ndc("sparky-stereo-throw", "@info the device's volume is set by the TV or receiver it is connected to", "The volume is set on the TV or receiver this device is connected to.")
            wrapMode: Text.Wrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18ndc("sparky-stereo-throw", "@title:group settings that need the person's Google account", "Needs your Google account")
        }
        Repeater {
            model: [
                i18ndc("sparky-stereo-throw", "@item a device setting that needs the Google account", "Name"),
                i18ndc("sparky-stereo-throw", "@item a device setting that needs the Google account", "Time zone and language"),
                i18ndc("sparky-stereo-throw", "@item a device setting that needs the Google account", "Wi-Fi network"),
                i18ndc("sparky-stereo-throw", "@item a device setting that needs the Google account", "Restart and factory reset"),
                i18ndc("sparky-stereo-throw", "@item a device setting that needs the Google account", "Ambient screen and photos"),
                i18ndc("sparky-stereo-throw", "@item a device setting that needs the Google account", "Guest mode"),
                i18ndc("sparky-stereo-throw", "@item a device setting that needs the Google account", "Speaker groups"),
            ]
            delegate: QQC2.Label {
                required property string modelData
                text: "• " + modelData
                enabled: false
            }
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.Wrap
            text: i18ndc("sparky-stereo-throw", "@info why the settings above cannot be changed here",
                        "These need a key the device gives only to your Google account. Sign in under Online Accounts; the Google account there does not give that key yet, so for now they are changed in the Google Home app.")
        }
        QQC2.Button {
            icon.name: "applications-internet"
            text: i18ndc("sparky-stereo-throw", "@action:button open KDE's Online Accounts page", "Open Online Accounts…")
            onClicked: kcm.openOnlineAccounts()
        }
    }
}
