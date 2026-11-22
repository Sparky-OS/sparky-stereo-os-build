// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: captions
    property var page
    readonly property var data: page ? (page.status.liveCaptions || {}) : ({})
    readonly property var words: data.labels || ({})
    readonly property var models: data.models || []
    function act(args) { page.act(["live-captions"].concat(args)) }
    spacing: Kirigami.Units.largeSpacing
    Kirigami.Heading { level: 2; text: captions.words.title || "" }
    QQC2.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: captions.words.privacy || "" }
    QQC2.Switch {
        text: checked ? captions.words.off : captions.words.on
        checked: !!captions.data.on
        onClicked: captions.act([checked ? "on" : "off"])
    }
    QQC2.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: captions.data.message || "" }
    QQC2.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: captions.words.card || "" }
    QQC2.CheckBox {
        text: captions.words.login || ""; checked: !!captions.data.login
        onClicked: captions.act(["login", checked ? "on" : "off"])
    }
    QQC2.CheckBox {
        text: captions.words.microphone || ""; checked: !!captions.data.microphone
        enabled: !captions.data.on
        onClicked: captions.act(["microphone", checked ? "on" : "off"])
    }
    QQC2.Label { text: captions.words.model || "" }
    QQC2.ComboBox {
        id: model
        Layout.fillWidth: true
        textRole: "id"; valueRole: "id"; model: captions.models
        // No initial selection means no implicit default speech model.
        currentIndex: captions.models.findIndex(m => m.path === captions.data.model)
    }
    FileDialog {
        id: existing
        fileMode: FileDialog.OpenFile
        nameFilters: ["Whisper (*.bin)"]
        onAccepted: captions.act(["select", decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""))])
    }
    QQC2.Label {
        Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
        text: model.currentIndex >= 0 ? captions.models[model.currentIndex].offer : (captions.words.none || "")
    }
    Flow {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        QQC2.Button {
            text: captions.words.existing || ""
            enabled: !captions.data.on
            onClicked: existing.open()
        }
        QQC2.Button {
            text: captions.words.choose || ""
            enabled: model.currentIndex >= 0 && !captions.data.on
            onClicked: captions.act(["select", model.currentValue])
        }
        QQC2.Button {
            text: captions.words.download || ""
            enabled: model.currentIndex >= 0 && !captions.data.on
            onClicked: captions.act(["download", model.currentValue])
        }
        QQC2.Button {
            text: captions.words.anyway || ""
            visible: captions.data.held === true
            enabled: model.currentIndex >= 0 && !captions.data.on
            onClicked: captions.act(["download", model.currentValue, "--even-if-metered"])
        }
        QQC2.Button { text: captions.words.refresh || ""; onClicked: captions.page.refresh() }
    }
}
