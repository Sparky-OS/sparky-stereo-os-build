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
    // the device as the daemon describes it now (a choice made here changes it)
    readonly property var current: {
        for (const d of kcm.devices) {
            if (d.id === device.id) {
                return d
            }
        }
        return device
    }
    readonly property var codecRows: current.codecs || []
    readonly property var codecRow: {
        for (const c of codecRows) {
            if (c.codec === current.codec) {
                return c
            }
        }
        return ({})
    }
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
            text: current.generation || ""
            wrapMode: Text.Wrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        }
        QQC2.Label {
            Kirigami.FormData.label: i18ndc("sparky-stereo-throw", "@label", "Address:")
            text: device.address || device.host || ""
        }
        QQC2.Label {
            Kirigami.FormData.label: i18ndc("sparky-stereo-throw", "@label the device's software version", "Firmware:")
            text: build.cast_build_revision || i18ndc("sparky-stereo-throw", "@info the device did not give it", "not given by the device")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18ndc("sparky-stereo-throw", "@title:group how a Throw to this device is made", "Throw")
        }
        QQC2.ComboBox {
            id: codecBox
            visible: !!page.current.video
            Kirigami.FormData.label: i18ndc("sparky-stereo-throw", "@label the video codec a Throw sends", "Codec:")
            textRole: "text"
            valueRole: "value"
            implicitContentWidthPolicy: QQC2.ComboBox.WidestText
            model: {
                const rows = [{value: "", text: i18ndc("sparky-stereo-throw", "@item the table's choice; %1 what it is", "Automatic (%1)", page.current.autoCodecLabel || "")}]
                for (const c of page.codecRows) {
                    rows.push({value: c.codec, text: c.available ? c.label : i18ndc("sparky-stereo-throw", "@item a codec this computer cannot encode; %1 its name", "%1 (no encoder on this computer)", c.label)})
                }
                return rows
            }
            currentIndex: Math.max(0, indexOfValue(page.current.choiceCodec || ""))
            onActivated: kcm.setChoice(page.current.id, currentValue, "")
        }
        QQC2.ComboBox {
            visible: !!page.current.video
            Kirigami.FormData.label: i18ndc("sparky-stereo-throw", "@label the picture's size and rate a Throw sends", "Mode:")
            textRole: "text"
            valueRole: "value"
            implicitContentWidthPolicy: QQC2.ComboBox.WidestText
            model: {
                const rows = [{value: "", text: i18ndc("sparky-stereo-throw", "@item the table's choice; %1 what it is", "Automatic (%1)", page.codecRow.default || "")}]
                for (const m of (page.codecRow.modes || [])) {
                    rows.push({value: m, text: m})
                }
                return rows
            }
            currentIndex: Math.max(0, indexOfValue(page.current.choiceMode || ""))
            onActivated: kcm.setChoice(page.current.id, page.current.choiceCodec || "", currentValue)
        }
        QQC2.Label {
            visible: !!page.current.video && !!page.current.mode
            Kirigami.FormData.label: i18ndc("sparky-stereo-throw", "@label the picture a Throw sends", "Throw mode:")
            text: i18ndc("sparky-stereo-throw", "@info %1 the mode, %2 the codec, %3 its level", "%1, %2 level %3", page.current.mode || "", page.current.codecLabel || "", page.current.level || "")
        }
        QQC2.ComboBox {
            // the sound is a choice as the codec and the mode are; Automatic is the best one the stream carries that has not
            // failed on this device, and what this device did with each is said
            Kirigami.FormData.label: i18ndc("sparky-stereo-throw", "@label the sound format a Throw sends", "Sound format:")
            textRole: "text"
            valueRole: "value"
            implicitContentWidthPolicy: QQC2.ComboBox.WidestText
            model: {
                const rows = [{value: "", text: i18ndc("sparky-stereo-throw", "@item the table's choice; %1 what it is", "Automatic (%1)", page.current.autoSoundLabel || "")}]
                for (const s of (page.current.sounds || [])) {
                    let text = s.label
                    if (s.played && s.startSeconds >= 0) {
                        text = i18ndc("sparky-stereo-throw", "@item a sound this device played; %1 its name, %2 seconds", "%1 (played on this device, started after %2 s)",
                                      s.label, Math.round(s.startSeconds))
                    } else if (s.played) {
                        text = i18ndc("sparky-stereo-throw", "@item a sound this device played; %1 its name", "%1 (played on this device)", s.label)
                    } else if (s.failed) {
                        text = i18ndc("sparky-stereo-throw", "@item a sound this device did not start playing; %1 its name", "%1 (did not start on this device)", s.label)
                    }
                    rows.push({value: s.id, text: text})
                }
                return rows
            }
            currentIndex: Math.max(0, indexOfValue(page.current.choiceSound || ""))
            onActivated: kcm.setSound(page.current.id, currentValue)
        }
        QQC2.Label {
            Kirigami.FormData.label: i18ndc("sparky-stereo-throw", "@label the sound a Throw sends", "Sound:")
            text: page.current.sound || ""
            wrapMode: Text.Wrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        }
        QQC2.Label {
            // what the sound means for a person, in plain words, and what a slower start means on this device
            visible: text.length > 0
            text: {
                let words = page.current.soundAbout || ""
                if (page.current.soundStart >= 0) {
                    words += " " + i18ndc("sparky-stereo-throw", "@info how long this device took to start with this sound; %1 seconds",
                                          "On this device it started %1 s after the Throw began; until then the television shows its own loading screen.",
                                          Math.round(page.current.soundStart))
                }
                return words.trim()
            }
            wrapMode: Text.Wrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            font: Kirigami.Theme.smallFont
        }
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: !!page.current.limited
            type: Kirigami.MessageType.Information
            text: page.current.limited || ""
        }
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: !!page.current.planError
            type: Kirigami.MessageType.Error
            text: page.current.planError || ""
        }
        QQC2.Button {
            visible: page.current.state === "throwing" && !!page.current.video
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
