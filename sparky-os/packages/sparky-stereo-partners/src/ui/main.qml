// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: root

    readonly property var st: kcm.status
    readonly property var engine: st.engine || ({})
    readonly property var card: st.card || ({})
    readonly property var interfaces: st.interfaces || []

    function kindLabel(kind) {
        switch (kind) {
        case "text": return i18nc("@label kind of work", "Text")
        case "speech": return i18nc("@label kind of work", "Speech")
        case "image": return i18nc("@label kind of work", "Image")
        case "3d": return i18nc("@label kind of work", "3D")
        }
        return kind
    }
    function iface(id) {
        for (const i of interfaces) { if (i.id === id) return i }
        return null
    }
    // the interfaces that can do a kind of work
    function interfaceOptions(kind) {
        const out = [{value: "none", text: i18nc("@item:inlistbox no interface", "None")}]
        for (const i of interfaces) {
            const fits = (kind === "text" && (i.kind === "ollama" || i.kind === "openai-compatible"))
                || (kind === "speech" && i.kind === "vibe") || (kind === "3d" && i.kind === "spirula")
                || (kind === "image" && i.kind === "openai-compatible")
            if (fits) out.push({value: i.id, text: i.name})
        }
        return out
    }
    readonly property var llamacpp: st.llamacpp || ({})
    // which engine an install dialog is for (the plan the command just printed)
    property string planEngine: "ollama"

    function engineName(eng) {
        return eng === "llamacpp" ? i18nc("@item the other local engine", "llama.cpp") : i18nc("@item the local engine", "Ollama")
    }
    // the models a local interface offers: Ollama's (on this computer and from the registry), or llama.cpp's files
    function modelOptions(current, ifaceId) {
        const out = []
        const seen = {}
        if (ifaceId === "llamacpp-local") {
            for (const m of (llamacpp.models || [])) {
                out.push({value: m.name, text: m.sizeText ? i18nc("@item:inlistbox %1 a model, %2 its size", "%1 (%2, on this computer)", m.name, m.sizeText) : m.name})
                seen[m.name] = true
            }
        } else {
            for (const m of (engine.models || [])) {
                out.push({value: m.name, text: i18nc("@item:inlistbox %1 a model, %2 its size", "%1 (%2, on this computer)", m.name, m.sizeText)})
                seen[m.name] = true
            }
            for (const m of kcm.models) {
                if (seen[m.name]) continue
                let note = m.name === (st.proposal || {}).model ? i18nc("@item:inlistbox", "Proposed for this computer")
                         : m.note === "small" ? i18nc("@item:inlistbox", "For very small computers") : ""
                const size = m.sizeText ? m.sizeText : i18nc("@item:inlistbox size not known", "size not read")
                out.push({value: m.name, text: note ? i18nc("@item:inlistbox %1 a model, %2 its size, %3 a note", "%1 (%2), %3", m.name, size, note)
                                                   : i18nc("@item:inlistbox %1 a model, %2 its size", "%1 (%2)", m.name, size)})
                seen[m.name] = true
            }
        }
        if (current && !seen[current]) out.push({value: current, text: current})
        if (!current) out.unshift({value: "", text: i18nc("@item:inlistbox", "No model chosen")})
        return out
    }
    function cardOptions() {
        const name = card.choice === "auto" && card.name ? card.name : ""
        const out = [{value: "auto", text: name ? i18nc("@item:inlistbox %1 a card", "Automatic: %1", name) : i18nc("@item:inlistbox", "Automatic")}]
        for (const g of (card.options || [])) out.push({value: g.id, text: g.name})
        out.push({value: "cpu", text: i18nc("@item:inlistbox the card the partners compute on", "Processor only")})
        return out
    }
    function privacy(kind, c) {
        const i = iface(c.interface)
        if (!i || c.interface === "none") return ""
        if (i.runs === "provider")
            return i18nc("@info %1 a provider, %2 its address", "Sends what you write to %1 (%2).", i.name, i.url)
        if (i.kind === "ollama" && /:cloud$|-cloud$/.test(c.model || ""))
            return i18nc("@info %1 a provider, %2 its address", "Sends what you write to %1 (%2).", i18nc("@item", "Ollama's service"), "ollama.com")
        return kind === "speech" ? i18nc("@info", "Runs on this computer. Nothing you say leaves it.")
                                 : i18nc("@info", "Runs on this computer. Nothing you write leaves it.")
    }
    function pending(key, fallback) {
        return kcm.pending[key] !== undefined ? kcm.pending[key] : fallback
    }

    header: Kirigami.InlineMessage {
        visible: kcm.message.length > 0
        type: kcm.messageIsInfo ? Kirigami.MessageType.Information : Kirigami.MessageType.Warning
        text: kcm.message
        showCloseButton: true
    }

    // a label that ends before what stands beside it: elided, the whole text in a tooltip when it does not fit
    component FittedLabel: QQC2.Label {
        Layout.fillWidth: true
        Layout.minimumWidth: Kirigami.Units.gridUnit * 6
        elide: Text.ElideRight
        HoverHandler { id: fittedHover }
        QQC2.ToolTip.visible: truncated && fittedHover.hovered
        QQC2.ToolTip.text: text
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    }
    // a list that takes the width its longest entry needs, or the page's when that is less
    component FittedComboBox: QQC2.ComboBox {
        implicitContentWidthPolicy: QQC2.ComboBox.WidestText
        Layout.maximumWidth: root.width - Kirigami.Units.gridUnit * 14
        textRole: "text"; valueRole: "value"
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: i18nc("@info", "Programs and services that write, listen, draw and model with you.") + " "
                + i18nc("@info", "For each kind of work, choose who answers, with which model and on which card.")
        }

        // ── System defaults
        Kirigami.Heading { level: 2; text: i18nc("@title:group", "System defaults") }
        Repeater {
            model: st.defaults || []
            delegate: GridLayout {
                id: kindRow
                required property var modelData
                readonly property string kind: modelData.kind
                readonly property string chosen: root.pending("default/" + kind + "/interface", modelData.interface)
                readonly property var chosenIface: root.iface(chosen)
                readonly property bool hasModel: !!chosenIface && (chosenIface.kind === "ollama" || chosenIface.id === "llamacpp-local")
                Layout.fillWidth: true
                columns: 3
                columnSpacing: Kirigami.Units.largeSpacing

                QQC2.Label { Layout.preferredWidth: Kirigami.Units.gridUnit * 5; font.bold: true; text: root.kindLabel(kindRow.kind) }
                QQC2.Label { text: i18nc("@label who answers", "Interface") }
                FittedComboBox {
                    model: root.interfaceOptions(kindRow.kind)
                    currentIndex: Math.max(0, model.findIndex(o => o.value === (kindRow.chosen || "none")))
                    onActivated: kcm.choose("default/" + kindRow.kind + "/interface", ["set-default", kindRow.kind, "--interface", currentValue], currentValue)
                }

                Item { visible: kindRow.hasModel; width: 1; height: 1 }
                QQC2.Label { visible: kindRow.hasModel; text: i18nc("@label", "Model") }
                FittedComboBox {
                    visible: kindRow.hasModel
                    readonly property string current: root.pending("default/" + kindRow.kind + "/model", kindRow.modelData.model)
                    model: root.modelOptions(current, kindRow.chosen)
                    currentIndex: Math.max(0, model.findIndex(o => o.value === current))
                    onActivated: kcm.choose("default/" + kindRow.kind + "/model",
                                            currentValue ? ["set-default", kindRow.kind, "--model", currentValue] : ["set-default", kindRow.kind, "--no-model"], currentValue)
                }

                Item { visible: !!kindRow.chosenIface && kindRow.chosenIface.runs === "here"; width: 1; height: 1 }
                QQC2.Label { visible: !!kindRow.chosenIface && kindRow.chosenIface.runs === "here"; text: i18nc("@label the card the partners compute on", "Card") }
                RowLayout {
                    visible: !!kindRow.chosenIface && kindRow.chosenIface.runs === "here"
                    FittedComboBox {
                        model: root.cardOptions()
                        currentIndex: Math.max(0, model.findIndex(o => o.value === root.pending("card", root.card.choice || "auto")))
                        onActivated: kcm.choose("card", ["card", currentValue], currentValue)
                    }
                    QQC2.Button {
                        text: i18nc("@action:button", "Graphics settings")
                        icon.name: "preferences-desktop-display"
                        onClicked: KCM.KCMLauncher.openSystemSettings("kcm_sparkystereo_graphics")
                    }
                }

                Item { width: 1; height: 1 }
                QQC2.Label {
                    Layout.columnSpan: 2
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font: Kirigami.Theme.smallFont
                    text: {
                        const lines = []
                        const c = Object.assign({}, kindRow.modelData, {interface: kindRow.chosen})
                        if (kindRow.chosenIface && !kindRow.chosenIface.installed)
                            lines.push(i18nc("@info %1 a program", "%1 is not installed.", kindRow.chosenIface.name))
                        if (kindRow.chosenIface && kindRow.chosenIface.runs === "here" && kindRow.kind === "text") {
                            lines.push(root.card.problem ? root.card.problem
                                       : root.card.choice === "cpu" ? i18nc("@info", "Now: the processor only")
                                       // Automatic on a computer where no card can hold the proposed model (Graphics' reason)
                                       : root.card.reason === "cpu-memory" ? i18nc("@info", "Now: the processor, because no card here has the memory of its own for the model this page proposes.")
                                       : i18nc("@info %1 is a GPU name", "Now: %1", root.card.name || root.card.id || ""))
                            if (!root.card.problem && root.card.reason === "unmeasured-memory")
                                lines.push(i18nc("@info", "Automatic leaves out the cards whose own memory cannot hold the model this page proposes."))
                        }
                        const p = root.privacy(kindRow.kind, c)
                        if (p) lines.push(p)
                        return lines.join("\n")
                    }
                }
            }
        }

        // ── On this computer: the two local engines
        Kirigami.Heading { level: 2; text: i18nc("@title:group", "On this computer") }
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: Kirigami.Units.largeSpacing

            // Ollama: its name stands on the line of its state, at the top of its block
            QQC2.Label {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                Layout.alignment: Qt.AlignTop | Qt.AlignLeft
                font.bold: true
                text: root.engineName("ollama")
            }
            ColumnLayout {
                Layout.fillWidth: true
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: !root.engine.installed ? i18nc("@info", "Not installed")
                        : root.engine.on ? i18nc("@info %1 an address", "On, answering on this computer only (%1)", root.engine.address)
                        : i18nc("@info", "Off")
                }
                QQC2.Label {
                    visible: !root.engine.installed
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font: Kirigami.Theme.smallFont
                    text: i18nc("@info %1 a program, %2 its size", "Installing downloads %1 (%2) and the runner for this computer's card; every size is shown before anything is downloaded.",
                                root.engineName("ollama"), kcm.humanSize(root.st.ollamaSize || 0))
                }
                RowLayout {
                    QQC2.Button {
                        visible: !root.engine.installed
                        enabled: !kcm.busy
                        text: i18nc("@action:button %1 a program", "Install %1", root.engineName("ollama"))
                        icon.name: "download"
                        onClicked: { root.planEngine = "ollama"; kcm.act(["install-plan"]) }
                    }
                    QQC2.Button {
                        visible: !!root.engine.installed && !root.engine.on
                        enabled: !kcm.busy
                        text: i18nc("@action:button", "Turn on")
                        onClicked: kcm.act(["engine", "on"])
                    }
                    QQC2.Button {
                        visible: !!root.engine.installed && !!root.engine.on
                        enabled: !kcm.busy
                        text: i18nc("@action:button", "Turn off")
                        onClicked: kcm.act(["engine", "off"])
                    }
                    QQC2.BusyIndicator { visible: kcm.busy; running: kcm.busy; implicitHeight: Kirigami.Units.gridUnit * 1.5 }
                    QQC2.Label { visible: kcm.progress.length > 0; text: kcm.progress }
                }
                Repeater {
                    model: !!root.engine.installed ? kcm.models : []
                    delegate: RowLayout {
                        required property var modelData
                        readonly property bool present: (root.engine.models || []).some(m => m.name === modelData.name)
                        QQC2.Label {
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 14
                            text: modelData.error ? i18nc("@info %1 a model, %2 why", "%1: its size could not be read (%2)", modelData.name, modelData.error)
                                                  : i18nc("@item:inlistbox %1 a model, %2 its size", "%1 (%2)", modelData.name, modelData.sizeText)
                        }
                        QQC2.Label {
                            text: modelData.name === (root.st.proposal || {}).model ? i18nc("@item:inlistbox", "Proposed for this computer")
                                : modelData.note === "small" ? i18nc("@item:inlistbox", "For very small computers") : ""
                            font: Kirigami.Theme.smallFont
                        }
                        QQC2.Button {
                            visible: !parent.present && !modelData.error
                            enabled: root.engine.on && !kcm.busy
                            text: i18nc("@action:button", "Download")
                            onClicked: kcm.act(["download", modelData.name])
                        }
                        QQC2.Label { visible: parent.present; text: i18nc("@info a model", "On this computer"); font: Kirigami.Theme.smallFont }
                    }
                }
                QQC2.Button {
                    visible: kcm.heldModel.length > 0
                    text: i18nc("@action:button", "Download anyway")
                    onClicked: kcm.act(["download", kcm.heldModel, "--even-if-metered"])
                }
                QQC2.Label {
                    visible: !!root.engine.installed
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font: Kirigami.Theme.smallFont
                    text: i18nc("@info", "Models hosted by Ollama's service are allowed: they send what you write to ollama.com.") + "\n"
                        + i18nc("@info", "While Ollama is on, it asks ollama.com for its list of hosted models and its suggestions; nothing you write is sent.")
                }
                QQC2.Label {
                    visible: !!(root.st.proposal || {}).slow
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: i18nc("@info %1 the computer's memory", "A model on this computer will be slow and may not fit in its memory (%1).", kcm.humanSize((root.st.proposal || {}).memory || 0))
                }
            }

            // llama.cpp: Debian's llama-server, the other local engine, chosen by the person
            QQC2.Label {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                Layout.alignment: Qt.AlignTop | Qt.AlignLeft
                font.bold: true
                text: root.engineName("llamacpp")
            }
            ColumnLayout {
                Layout.fillWidth: true
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: !root.llamacpp.installed ? i18nc("@info", "Not installed")
                        : root.llamacpp.on ? i18nc("@info %1 an address", "On, answering on this computer only (%1)", root.llamacpp.address)
                        : i18nc("@info", "Off")
                }
                QQC2.Label {
                    visible: !root.llamacpp.installed
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font: Kirigami.Theme.smallFont
                    text: i18nc("@info %1 a size", "Installing downloads Debian's llama-server (%1) and its Vulkan back end, which runs on any card; every size is shown before anything is downloaded.",
                                kcm.humanSize(root.llamacpp.size || 0))
                }
                RowLayout {
                    QQC2.Button {
                        visible: !root.llamacpp.installed
                        enabled: !kcm.busy
                        text: i18nc("@action:button %1 a program", "Install %1", root.engineName("llamacpp"))
                        icon.name: "download"
                        onClicked: { root.planEngine = "llamacpp"; kcm.act(["install-plan", "--engine", "llamacpp"]) }
                    }
                    QQC2.Button {
                        visible: !!root.llamacpp.installed && !root.llamacpp.on
                        enabled: !kcm.busy
                        text: i18nc("@action:button", "Turn on")
                        onClicked: kcm.act(["engine", "on", "--engine", "llamacpp"])
                    }
                    QQC2.Button {
                        visible: !!root.llamacpp.installed && !!root.llamacpp.on
                        enabled: !kcm.busy
                        text: i18nc("@action:button", "Turn off")
                        onClicked: kcm.act(["engine", "off", "--engine", "llamacpp"])
                    }
                    QQC2.Button {
                        visible: !!root.llamacpp.installed
                        text: i18nc("@action:button", "Open the models folder")
                        icon.name: "folder-open"
                        onClicked: Qt.openUrlExternally("file://" + root.llamacpp.folder)
                    }
                    QQC2.Button {
                        visible: !!root.llamacpp.installed
                        text: i18nc("@action:button", "Look again")
                        icon.name: "view-refresh"
                        enabled: !kcm.busy
                        onClicked: kcm.refresh()
                    }
                }
                Repeater {
                    model: root.llamacpp.models || []
                    delegate: QQC2.Label {
                        required property var modelData
                        text: modelData.sizeText ? i18nc("@item:inlistbox %1 a model, %2 its size", "%1 (%2)", modelData.name, modelData.sizeText) : modelData.name
                    }
                }
                QQC2.Label {
                    visible: !!root.llamacpp.installed
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font: Kirigami.Theme.smallFont
                    text: i18nc("@info %1 a folder", "llama.cpp downloads no model by itself: put model files (GGUF) in %1, then choose Look again.", root.llamacpp.folder || "")
                }
            }
        }

        // ── Providers
        Kirigami.Heading { level: 2; text: i18nc("@title:group", "Providers") }
        // Ollama's service: signed in through the local engine, which signs with its own key
        RowLayout {
            visible: !!root.engine.installed
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                FittedLabel { text: i18nc("@item %1 a provider, %2 its address", "%1 (%2)", i18nc("@item", "Ollama's service"), "ollama.com") }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font: Kirigami.Theme.smallFont
                    text: {
                        const a = kcm.account
                        switch (a.state) {
                        case "signed-in": return i18nc("@info %1 an account name", "Signed in as %1.", a.name)
                        case "signed-out": return i18nc("@info", "Not signed in")
                        case "off": return i18nc("@info", "Turn Ollama on to sign in.")
                        case "unavailable": return i18nc("@info %1 why", "Ollama's service could not be reached: %1", a.why || "")
                        }
                        return i18nc("@info the page asks the service", "Asking…")
                    }
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font: Kirigami.Theme.smallFont
                    text: i18nc("@info %1 a computer's name, %2 a file", "Signing in opens ollama.com in your browser and links this computer's name (%1) and Ollama's key for it (kept by Ollama in %2) to your account there.",
                                root.st.computer || "", root.st.ollamaKey || "")
                }
            }
            QQC2.Button {
                visible: kcm.account.state === "signed-out" || kcm.account.state === "unavailable"
                enabled: !kcm.busy && !!root.engine.on
                text: i18nc("@action:button", "Sign in…")
                icon.name: "im-user-online"
                onClicked: kcm.act(["signin"])
            }
            QQC2.Button {
                visible: kcm.account.state === "signed-out"
                enabled: !kcm.busy
                text: i18nc("@action:button", "Check")
                icon.name: "view-refresh"
                onClicked: kcm.refreshAccount()
            }
            QQC2.Button {
                visible: kcm.account.state === "signed-in"
                enabled: !kcm.busy
                text: i18nc("@action:button", "Sign out")
                icon.name: "im-user-offline"
                onClicked: kcm.act(["signout"])
            }
        }
        Repeater {
            model: root.interfaces.filter(i => i.runs === "provider")
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
                    FittedLabel { text: i18nc("@item %1 a provider, %2 its address", "%1 (%2)", modelData.name, modelData.url) }
                    QQC2.Label { visible: !!modelData.wallet; text: i18nc("@info", "The key is kept in KDE Wallet."); font: Kirigami.Theme.smallFont }
                }
                QQC2.Button {
                    text: i18nc("@action:button", "Remove")
                    icon.name: "list-remove"
                    enabled: !kcm.busy
                    onClicked: kcm.act(["provider", "remove", modelData.id.replace(/^provider-/, "")])
                }
            }
        }
        QQC2.Button {
            text: i18nc("@action:button", "Add a provider…")
            icon.name: "list-add"
            onClicked: providerDialog.open()
        }

        // ── Programs
        Kirigami.Heading { level: 2; text: i18nc("@title:group", "Programs") }
        Repeater {
            model: st.programs || []
            delegate: ColumnLayout {
                id: programRow
                required property var modelData
                Layout.fillWidth: true
                QQC2.Label {
                    font.bold: true
                    text: programRow.modelData.installed ? programRow.modelData.name
                        : i18nc("@item %1 a program", "%1 (not installed)", programRow.modelData.name)
                }
                QQC2.Label {
                    visible: text.length > 0
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font: Kirigami.Theme.smallFont
                    text: {
                        const lines = []
                        switch (programRow.modelData.note) {
                        case "own-services": lines.push(i18nc("@info", "It uses the services you sign in to in it; this page cannot choose for it.")); break
                        case "own-engines": lines.push(i18nc("@info", "It uses its own engines and models on this computer; this page cannot choose for it.")); break
                        case "kde-text-addons":
                            lines.push(i18nc("@info", "KDE's text add-ons follow this choice when you have set up no instance of your own in them."))
                            // what they can follow, said where it matters: their llama.cpp add-on is unfinished, and they know no provider's own address
                            if ((programRow.modelData.choices || []).some(c => c.protocol === "openai-compatible"))
                                lines.push(i18nc("@info", "They can follow only Ollama for now: their llama.cpp add-on is not finished in version 2.1.2, and they cannot reach a provider's own address."))
                            break
                        case "seeded": lines.push(i18nc("@info", "Its presets take this choice when they are set up; a later change here reaches it when they are set up again.")); break
                        }
                        return lines.join("\n")
                    }
                }
                Repeater {
                    model: (programRow.modelData.note === "own-services" || programRow.modelData.note === "own-engines") ? [] : programRow.modelData.choices
                    delegate: RowLayout {
                        id: choiceRow
                        required property var modelData
                        readonly property string pkey: "program/" + programRow.modelData.id + "/" + modelData.kind
                        readonly property bool own: root.pending(pkey, modelData.own ? modelData.interface : "") !== ""
                        QQC2.Label { Layout.preferredWidth: Kirigami.Units.gridUnit * 5; text: root.kindLabel(choiceRow.modelData.kind) }
                        QQC2.RadioButton {
                            text: i18nc("@option:radio", "Follow the system default")
                            checked: !choiceRow.own
                            onToggled: if (checked) kcm.choose(choiceRow.pkey, ["program", programRow.modelData.id, choiceRow.modelData.kind, "follow"], "")
                        }
                        QQC2.RadioButton {
                            id: ownChoice
                            text: i18nc("@option:radio", "Its own choice")
                            checked: choiceRow.own
                            onToggled: if (checked) ownCombo.activated(ownCombo.currentIndex)
                        }
                        FittedComboBox {
                            id: ownCombo
                            enabled: ownChoice.checked
                            model: root.interfaceOptions(choiceRow.modelData.kind).filter(o => o.value !== "none")
                            currentIndex: Math.max(0, model.findIndex(o => o.value === choiceRow.modelData.interface))
                            onActivated: kcm.choose(choiceRow.pkey, ["program", programRow.modelData.id, choiceRow.modelData.kind, "own", "--interface", currentValue], currentValue)
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: kcm
        function onPlanReady(packages, total) {
            planDialog.packages = packages
            planDialog.total = total
            planDialog.open()
        }
    }

    Kirigami.PromptDialog {
        id: planDialog
        property var packages: []
        property double total: 0
        title: i18nc("@title:window %1 a program", "Install %1", root.engineName(root.planEngine))
        subtitle: packages.map(p => i18nc("@item %1 a package, %2 its size", "%1 (%2)", p.name, kcm.humanSize(p.size))).join("\n") + "\n"
                + i18nc("@info %1 a size", "Downloads %1 in all.", kcm.humanSize(total))
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: kcm.act(root.planEngine === "llamacpp" ? ["install", "--engine", "llamacpp"] : ["install"])
    }

    Kirigami.PromptDialog {
        id: providerDialog
        title: i18nc("@title:window", "Add a provider")
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: kcm.act(["provider", "add", providerId.text, "--name", providerName.text, "--url", providerUrl.text], providerKey.text)
        Kirigami.FormLayout {
            QQC2.TextField { id: providerName; Kirigami.FormData.label: i18nc("@label", "Name:") }
            QQC2.TextField { id: providerId; Kirigami.FormData.label: i18nc("@label short name in small letters", "Short name:") }
            QQC2.TextField { id: providerUrl; Kirigami.FormData.label: i18nc("@label", "Address:"); placeholderText: "https://" }
            Kirigami.PasswordField { id: providerKey; Kirigami.FormData.label: i18nc("@label", "Key:") }
            QQC2.Label { text: i18nc("@info", "The key is kept in KDE Wallet."); font: Kirigami.Theme.smallFont }
        }
    }
}
