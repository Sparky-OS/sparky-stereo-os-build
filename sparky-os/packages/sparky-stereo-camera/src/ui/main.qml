// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtMultimedia
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.sparky.stereo.camera

KCM.SimpleKCM {
    id: root

    readonly property bool hasCameras: kcm.cameras.length > 0

    function indexOfCurrent() {
        for (let i = 0; i < kcm.cameras.length; ++i) {
            if (kcm.cameras[i].name === kcm.current) {
                return i;
            }
        }
        return -1;
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: kcm.engineError.length > 0
            type: Kirigami.MessageType.Error
            text: kcm.engineError
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: kcm.savedNotes.length > 0
            type: Kirigami.MessageType.Warning
            text: kcm.savedNotes.join(" ")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: kcm.machineNotes.length > 0
            type: Kirigami.MessageType.Information
            text: kcm.machineNotes.join(" ")
        }

        Kirigami.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.gridUnit * 3
            visible: !root.hasCameras && kcm.engineError.length === 0
            icon.name: "camera-web"
            text: i18n("No camera found")
            explanation: i18n("Plug in a camera. It appears here by itself, and you do not have to restart anything.")
        }

        // Which camera programs get when they ask for "the camera"
        Kirigami.FormLayout {
            Layout.fillWidth: true
            visible: root.hasCameras

            Item {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Default camera")
            }
            Repeater {
                model: kcm.cameras
                delegate: QQC2.RadioButton {
                    required property var modelData
                    Kirigami.FormData.label: ""
                    text: modelData.description
                    checked: kcm.defaultCamera === modelData.name
                    onToggled: kcm.defaultCamera = modelData.name
                    QQC2.ToolTip.text: i18n("Programs that ask for a camera without choosing one get this camera.")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }
            QQC2.Label {
                Kirigami.FormData.label: ""
                Layout.maximumWidth: Kirigami.Units.gridUnit * 28
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: i18n("A program in which you chose a camera keeps your choice. Programs that open the camera themselves, such as those built on Qt Multimedia, do not follow this default yet.")
            }
        }

        Kirigami.Separator { Layout.fillWidth: true; visible: root.hasCameras }

        Kirigami.FormLayout {
            Layout.fillWidth: true
            visible: root.hasCameras

            QQC2.ComboBox {
                id: cameraBox
                Kirigami.FormData.label: i18n("Settings for:")
                model: kcm.cameras
                textRole: "description"
                implicitContentWidthPolicy: QQC2.ComboBox.WidestText
                Layout.minimumWidth: Kirigami.Units.gridUnit * 14
                currentIndex: root.indexOfCurrent()
                onCountChanged: currentIndex = root.indexOfCurrent()
                onActivated: kcm.current = kcm.cameras[currentIndex].name
            }

            QQC2.Label {
                Kirigami.FormData.label: ""
                visible: kcm.currentNote.length > 0
                Layout.maximumWidth: Kirigami.Units.gridUnit * 28
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.negativeTextColor
                text: kcm.currentNote
            }
        }

        // The preview: a two-lens camera's packed picture is a declared pair, a one-lens camera's is flat
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Kirigami.Units.gridUnit * 28
            Layout.preferredHeight: Kirigami.Units.gridUnit * 16
            visible: root.hasCameras && kcm.currentNodeId >= 0
            color: "black"
            radius: Kirigami.Units.cornerRadius

            VideoOutput {
                id: videoOut
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectFit
                stereoInput: VideoOutput.StereoNone
            }
            PreviewSource {
                id: preview
                nodeId: root.hasCameras ? kcm.currentNodeId : -1
                videoSink: videoOut.videoSink
            }
            QQC2.Label {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.largeSpacing * 2
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: "white"
                visible: preview.state !== "streaming"
                text: preview.error.length > 0 ? preview.error
                    : i18n("Starting the preview…")
            }
        }

        QQC2.Button {
            Layout.alignment: Qt.AlignHCenter
            visible: root.hasCameras && kcm.currentNodeId >= 0 && kcm.packing !== "mono"
            enabled: kcm.packingInfo.input.length > 0
            objectName: "showPair"
            text: i18n("Show the pair in 3D")
            icon.name: "camera-video"
            onClicked: pairWindow.visible = true
            QQC2.ToolTip.text: i18n("This preview cannot show that packing. Other programs can.")
            QQC2.ToolTip.visible: hovered && !enabled
        }

        QQC2.Label {
            objectName: "pairRefusal"
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: root.hasCameras && kcm.currentNodeId >= 0 && kcm.packing !== "mono" && kcm.packingInfo.input.length === 0
            text: i18n("This preview cannot show that packing. Other programs can.")
        }

        // The pair is a 3D area of its own: a window whose video output declares the two views to Stereo KWin
        Window {
            id: pairWindow
            width: 960
            height: 540
            visible: false
            title: i18n("Camera preview in 3D")
            color: "black"
            VideoOutput {
                id: pairOut
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectFit
                stereoInput: kcm.packingInfo.input.length > 0 ? VideoOutput[kcm.packingInfo.input] : VideoOutput.StereoNone
                stereoSwapEyes: kcm.packingInfo.swap
            }
            PreviewSource {
                nodeId: pairWindow.visible ? kcm.currentNodeId : -1
                videoSink: pairOut.videoSink
            }
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true
            visible: root.hasCameras && kcm.formats.length > 0

            Item {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Picture")
            }

            QQC2.ComboBox {
                id: formatBox
                Kirigami.FormData.label: i18n("Format:")
                model: kcm.formats
                textRole: "description"
                valueRole: "fourcc"
                implicitContentWidthPolicy: QQC2.ComboBox.WidestText
                currentIndex: Math.max(0, indexOfValue(kcm.mode.fourcc))
                onCountChanged: currentIndex = Math.max(0, indexOfValue(kcm.mode.fourcc))
                onActivated: root.pickMode(currentValue, 0, 0, 0)
            }
            QQC2.ComboBox {
                id: sizeBox
                Kirigami.FormData.label: i18n("Size:")
                readonly property var sizes: kcm.formats.length > 0 && formatBox.currentIndex >= 0 ? kcm.formats[formatBox.currentIndex].sizes : []
                model: sizes.map(s => s.stepwise ? i18n("%1 × %2 to %3 × %4", s.width, s.height, s.maxWidth, s.maxHeight) : i18n("%1 × %2", s.width, s.height))
                currentIndex: {
                    for (let i = 0; i < sizes.length; ++i) {
                        if (sizes[i].width === kcm.mode.width && sizes[i].height === kcm.mode.height) {
                            return i;
                        }
                    }
                    return 0;
                }
                onActivated: root.pickMode(formatBox.currentValue, sizes[currentIndex].width, sizes[currentIndex].height, 0)
            }
            QQC2.ComboBox {
                id: rateBox
                Kirigami.FormData.label: i18n("Frames per second:")
                readonly property var rates: sizeBox.sizes.length > 0 ? kcm.frameRates(formatBox.currentValue, sizeBox.sizes[Math.max(0, sizeBox.currentIndex)].width, sizeBox.sizes[Math.max(0, sizeBox.currentIndex)].height) : []
                model: rates.map(r => String(Math.round(r * 100) / 100))
                currentIndex: {
                    for (let i = 0; i < rates.length; ++i) {
                        if (Math.abs(rates[i] - kcm.mode.fps) < 0.01) {
                            return i;
                        }
                    }
                    return 0;
                }
                onActivated: root.pickMode(formatBox.currentValue, sizeBox.sizes[sizeBox.currentIndex].width, sizeBox.sizes[sizeBox.currentIndex].height, rates[currentIndex])
            }
            QQC2.Label {
                Kirigami.FormData.label: ""
                visible: kcm.modeError.length > 0
                Layout.maximumWidth: Kirigami.Units.gridUnit * 28
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.negativeTextColor
                text: kcm.modeError
            }
            QQC2.Label {
                Kirigami.FormData.label: ""
                Layout.maximumWidth: Kirigami.Units.gridUnit * 28
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: i18n("Programs that choose their own size and format are not changed by this.")
            }
            QQC2.Label {
                Kirigami.FormData.label: ""
                Layout.maximumWidth: Kirigami.Units.gridUnit * 28
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: i18n("A camera you have not set starts at its largest picture and, at that size, its highest frame rate.")
            }
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true
            visible: root.hasCameras && kcm.controls.length > 0

            Item {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Camera controls")
            }

            Repeater {
                model: kcm.controls
                delegate: ColumnLayout {
                    id: ctl
                    required property var modelData
                    property string failure: ""
                    Kirigami.FormData.label: modelData.kind === "button" ? "" : modelData.label + ":"
                    spacing: 0

                    function apply(v) {
                        failure = kcm.setControl(modelData.id, v);
                    }

                    // integer
                    RowLayout {
                        visible: ctl.modelData.kind === "integer"
                        QQC2.Slider {
                            id: slider
                            enabled: ctl.modelData.editable && !ctl.modelData.inactive
                            from: ctl.modelData.min
                            to: ctl.modelData.max
                            stepSize: ctl.modelData.step
                            value: ctl.modelData.value
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 14
                            onMoved: ctl.apply(Math.round(value))
                        }
                        QQC2.Label { text: Math.round(slider.value); Layout.minimumWidth: Kirigami.Units.gridUnit * 3 }
                    }
                    // boolean
                    QQC2.Switch {
                        visible: ctl.modelData.kind === "boolean"
                        enabled: ctl.modelData.editable && !ctl.modelData.inactive
                        checked: ctl.modelData.value !== 0
                        onToggled: ctl.apply(checked ? 1 : 0)
                    }
                    // menu
                    QQC2.ComboBox {
                        visible: ctl.modelData.kind === "menu" || ctl.modelData.kind === "integer-menu"
                        enabled: ctl.modelData.editable && !ctl.modelData.inactive
                        model: ctl.modelData.menu
                        textRole: "text"
                        valueRole: "index"
                        implicitContentWidthPolicy: QQC2.ComboBox.WidestText
                        currentIndex: Math.max(0, indexOfValue(ctl.modelData.value))
                        onCountChanged: currentIndex = Math.max(0, indexOfValue(ctl.modelData.value))
                        onActivated: ctl.apply(currentValue)
                    }
                    // button
                    QQC2.Button {
                        visible: ctl.modelData.kind === "button"
                        text: ctl.modelData.label
                        onClicked: ctl.apply(1)
                    }
                    // a kind this page cannot change
                    QQC2.Label {
                        visible: ctl.modelData.kind === "other"
                        text: ctl.modelData.label
                        opacity: 0.6
                    }
                    QQC2.Label {
                        visible: text.length > 0
                        Layout.maximumWidth: Kirigami.Units.gridUnit * 28
                        wrapMode: Text.WordWrap
                        color: ctl.failure.length > 0 ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                        opacity: ctl.failure.length > 0 ? 1 : 0.6
                        text: ctl.failure.length > 0 ? ctl.failure : ctl.modelData.note
                    }
                }
            }

            QQC2.Button {
                Kirigami.FormData.label: ""
                text: i18n("Reset to the camera's defaults")
                icon.name: "edit-reset"
                onClicked: kcm.resetControls()
            }
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true
            visible: root.hasCameras && kcm.formats.length > 0

            Item {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Two lenses")
            }
            QQC2.ComboBox {
                Kirigami.FormData.label: i18n("3D Input Format:")
                model: kcm.packings
                textRole: "text"
                valueRole: "id"
                implicitContentWidthPolicy: QQC2.ComboBox.WidestText
                currentIndex: Math.max(0, indexOfValue(kcm.packing))
                onCountChanged: currentIndex = Math.max(0, indexOfValue(kcm.packing))
                onActivated: kcm.packing = currentValue
            }
            QQC2.Label {
                Kirigami.FormData.label: ""
                Layout.maximumWidth: Kirigami.Units.gridUnit * 28
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: i18n("A camera with two lenses sends both pictures in one. Say how it packs them, and the preview shows the pair in 3D. A camera with one lens stays \"Not 3D\".")
            }
        }
    }

    function pickMode(fourcc, w, h, fps) {
        // a change of format starts at the first size and rate the camera lists for it
        const fmt = kcm.formats.find(f => f.fourcc === fourcc);
        const size = (w > 0) ? {width: w, height: h} : fmt.sizes[0];
        const rates = kcm.frameRates(fourcc, size.width, size.height);
        kcm.setMode(fourcc, size.width, size.height, fps > 0 ? fps : (rates.length > 0 ? rates[0] : 0));
    }

    function prettyName(name) {
        const text = name.replace(/_/g, " ");
        return text.charAt(0).toUpperCase() + text.slice(1);
    }
}
