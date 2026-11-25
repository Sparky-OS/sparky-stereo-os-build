// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: page
    function tr(source) { return i18nd("kcm_sparkystereo_weather", source) }
    readonly property string photoreal: tr("Photoreal")
    readonly property string realWeather: "Sparky Stereo Real Weather"
    readonly property string machineLabel: kcm.machineLook === "RealWeather" ? realWeather
        : kcm.machineLook === "Photoreal" ? photoreal : tr("Icon Theme")

    component SettingBox: Controls.ComboBox {
        required property string key
        textRole: "label"
        valueRole: "value"
        currentIndex: indexOfValue(kcm.values[key])
        onActivated: kcm.change(key, currentValue)
    }

    Kirigami.FormLayout {
        SettingBox {
            objectName: "weatherLook"
            Kirigami.FormData.label: page.tr("Look")
            key: "Look"
            model: [
                {value: "Auto", label: page.tr("Automatic")},
                {value: "IconTheme", label: page.tr("Icon Theme")},
                {value: "Vector", label: page.tr("Vector")},
                {value: "Photoreal", label: page.photoreal},
                {value: "RealWeather", label: page.realWeather}
            ]
        }
        SettingBox {
            objectName: "weatherHardware"
            Kirigami.FormData.label: page.tr("Automatic uses")
            key: "HardwareLook"
            model: [
                {value: "", label: i18nd("kcm_sparkystereo_weather", "Machine choice (%1)", page.machineLabel)},
                {value: "Photoreal", label: page.photoreal},
                {value: "RealWeather", label: page.realWeather}
            ]
        }
        SettingBox {
            objectName: "weatherPanel"
            Kirigami.FormData.label: page.tr("Panel icon")
            key: "PanelIcon"
            model: [
                {value: "Colour", label: page.tr("Colour")},
                {value: "OneColour", label: page.tr("One Colour")}
            ]
        }
        SettingBox {
            objectName: "weatherShade"
            Kirigami.FormData.label: page.tr("Shade")
            key: "Shade"
            model: [
                {value: "Present", label: page.tr("Present")},
                {value: "Darker", label: page.tr("Darker")}
            ]
        }
        Controls.CheckBox {
            objectName: "weatherAnimation"
            text: page.tr("Animate on hover")
            checked: kcm.values["Animation"] === "true"
            onToggled: kcm.change("Animation", checked ? "true" : "false")
        }
        RowLayout {
            Kirigami.FormData.label: page.tr("Preview")
            Repeater {
                model: ["weather-clear", "weather-clear-night"]
                Kirigami.Icon {
                    required property string modelData
                    source: modelData
                    Layout.preferredWidth: Kirigami.Units.iconSizes.large
                    Layout.preferredHeight: Kirigami.Units.iconSizes.large
                    weatherTheme: true
                    weatherHovered: hover.hovered
                    HoverHandler { id: hover }
                }
            }
        }
        Kirigami.InlineMessage {
            visible: kcm.error.length > 0
            text: kcm.error
            type: Kirigami.MessageType.Error
        }
    }
}
