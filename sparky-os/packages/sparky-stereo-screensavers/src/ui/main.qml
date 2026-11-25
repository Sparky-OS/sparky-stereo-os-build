// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// The layout is the one of KDE's Screen Saver module (kde-workspace, kcontrol/screensaver, KDE 4.11): the list, the
// small preview beside it with the full-screen button under it, the times. Its authors are in the package's copyright file.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.sparky.stereo.screensavers

KCM.AbstractKCM {
    id: root

    framedView: false
    readonly property var current: list.currentIndex >= 0 ? (ticks, kcm.savers.get(list.currentIndex)) : ({})
    property int ticks: 0 // read again after a tick changes

    function failureText(kind, detail, title) {
        switch (kind) {
        case 3:
            return i18n("“%1” cannot be shown: its files are not the ones its stereo check was made on. Update the system; if it stays, reinstall gl-stereo-savers.", title);
        case 4:
            return i18n("“%1” is not installed. Reinstall the XScreenSaver packages.", title);
        case 5:
            return i18n("“%1” could not start: the private display it draws on did not start. Check that the package xvfb is installed.", title);
        case 6:
            return i18n("“%1” stopped by itself (%2). Choose another screensaver, or try again.", title, detail);
        case 7:
            return i18n("“%1” drew no picture. Try again; on a busy computer a screensaver can take a while to start.", title);
        case 8:
            return i18n("The preview program is missing (%1). Reinstall sparky-stereo-screensavers.", detail);
        case 9:
            return i18n("“%1” sent a picture the page could not accept (%2). Choose another screensaver.", title, detail);
        }
        return "";
    }

    function pairNoteText(note) {
        if (note === "") {
            return "";
        }
        if (note === "no-stereo-compositor") {
            return i18n("This desktop does not take 3D pictures from programs, so the preview shows one view.");
        }
        if (note === "cut") {
            return i18n("The preview does not fit in the window, so it shows one view. Make the window larger to see it in 3D.");
        }
        return i18n("The desktop refused the 3D picture, so the preview shows one view.");
    }

    Connections {
        target: kcm.savers
        function onTicksChanged() {
            root.ticks++;
        }
    }

    header: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: kcm.savers.problem !== ""
            type: Kirigami.MessageType.Error
            text: kcm.savers.problem
        }
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: kcm.savers.notOffered > 0 && kcm.savers.problem === ""
            type: Kirigami.MessageType.Warning
            text: i18np("%1 screensaver cannot be offered. Select it to read why.", "%1 screensavers cannot be offered. Select one to read why.", kcm.savers.notOffered)
        }
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: !kcm.showEnabled
            type: Kirigami.MessageType.Information
            text: i18n("The screensaver show is switched off. The choices below are kept and used when it is switched on again.")
        }
        Kirigami.InlineMessage {
            id: varietyMessage
            Layout.fillWidth: true
            visible: false
            type: Kirigami.MessageType.Error
            text: i18n("Stereo Variety could not be opened. Check that the package variety is installed.")
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.largeSpacing

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                Kirigami.SearchField {
                    id: search
                    Layout.fillWidth: true
                }
                QQC2.Label {
                    text: i18n("%1 in 3D, %2 in 2D", kcm.savers.stereoCount, kcm.savers.flatCount)
                    color: Kirigami.Theme.disabledTextColor
                }
            }

            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Component.onCompleted: background.visible = true

                ListView {
                    id: list
                    objectName: "saverList"
                    clip: true
                    model: kcm.savers
                    currentIndex: -1
                    Component.onCompleted: currentIndex = count > 0 ? 0 : -1
                    delegate: QQC2.ItemDelegate {
                        id: row
                        required property int index
                        required property string saverId
                        required property string title
                        required property bool stereo
                        required property bool offered
                        required property bool ticked
                        readonly property bool matches: search.text === "" || title.toLowerCase().includes(search.text.toLowerCase()) || saverId.includes(search.text.toLowerCase())
                        width: ListView.view.width
                        height: matches ? implicitHeight : 0
                        visible: matches
                        highlighted: ListView.isCurrentItem
                        onClicked: list.currentIndex = index
                        contentItem: RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            QQC2.CheckBox {
                                checked: row.ticked
                                enabled: row.offered
                                onToggled: kcm.savers.setTicked(row.index, checked)
                                QQC2.ToolTip.text: i18n("In the show")
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                Accessible.name: i18n("In the show")
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: row.title
                                elide: Text.ElideRight
                                color: row.offered ? (row.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor) : Kirigami.Theme.disabledTextColor
                            }
                            QQC2.Label {
                                text: !row.offered ? i18n("Not offered") : row.stereo ? i18nc("a screensaver drawn with depth", "3D") : i18nc("a screensaver drawn flat", "2D")
                                color: row.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.disabledTextColor
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                QQC2.Label {
                    Layout.fillWidth: true
                    text: i18np("%1 screensaver in the show", "%1 screensavers in the show", kcm.savers.tickedCount)
                    elide: Text.ElideRight
                }
                QQC2.Button {
                    text: i18n("Only This One")
                    icon.name: "checkbox"
                    enabled: list.currentIndex >= 0 && root.current.offered === true
                    onClicked: kcm.savers.tickOnly(list.currentIndex)
                }
                QQC2.Button {
                    text: i18n("All 3D Ones")
                    icon.name: "edit-select-all"
                    onClicked: kcm.savers.tickAllStereo()
                }
            }
        }

        QQC2.ScrollView {
            id: side
            Layout.fillHeight: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 22
            Layout.minimumWidth: Kirigami.Units.gridUnit * 22
            contentWidth: availableWidth

            ColumnLayout {
                width: side.availableWidth
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    id: frame
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 336
                    implicitHeight: 192
                    color: "black"
                    radius: 0

                    SaverPreview {
                        id: preview
                        objectName: "saverPreview"
                        anchors.fill: parent
                        saver: root.current.offered === true ? root.current.saverId : ""
                        stereo: root.current.stereo === true
                        active: root.visible
                    }
                    Kirigami.PlaceholderMessage {
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.gridUnit * 2
                        visible: preview.failure !== 0 || (!preview.showing && !preview.fullScreenOpen)
                        Kirigami.Theme.colorSet: Kirigami.Theme.Complementary
                        Kirigami.Theme.inherit: false
                        explanation: preview.failure !== 0 ? root.failureText(preview.failure, preview.failureDetail, root.current.title)
                            : list.currentIndex < 0 ? i18n("Select a screensaver to see it here.")
                            : root.current.offered !== true ? root.current.reason
                            : i18n("Starting “%1”…", root.current.title)
                    }
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    font: Kirigami.Theme.smallFont
                    text: preview.showing && preview.stereo && !preview.pairShown ? root.pairNoteText(preview.pairNote) : ""
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    QQC2.Button {
                        objectName: "fullScreenButton"
                        text: i18n("Full Screen Preview")
                        icon.name: "view-fullscreen"
                        enabled: root.current.offered === true && !preview.fullScreenOpen
                        onClicked: preview.fullScreen()
                        QQC2.ToolTip.text: i18n("Shows the selected screensaver on the whole screen. Any key or a move of the pointer ends it.")
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                    QQC2.Button {
                        visible: preview.failure !== 0
                        text: i18n("Try Again")
                        icon.name: "view-refresh"
                        onClicked: preview.retry()
                    }
                }

                Kirigami.Heading {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    level: 4
                    visible: list.currentIndex >= 0
                    text: root.current.title ?? ""
                    elide: Text.ElideRight
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    visible: list.currentIndex >= 0
                    wrapMode: Text.WordWrap
                    text: root.current.offered !== true ? (root.current.reason ?? "")
                        : root.current.stereo === true ? i18n("Drawn in 3D, within your depth limits.")
                        : i18n("Drawn in 2D: the same picture in both eyes, at the screen. It joins the show when ticked.")
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    visible: (root.current.authors ?? "") !== ""
                    wrapMode: Text.WordWrap
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.disabledTextColor
                    text: i18n("By %1. XScreenSaver is by Jamie Zawinski and its contributors.", root.current.authors ?? "")
                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                }

                Kirigami.FormLayout {
                    Layout.fillWidth: true

                    QQC2.CheckBox {
                        objectName: "showEnabled"
                        Kirigami.FormData.label: i18n("Show:")
                        text: i18n("Screensaver show on AC power")
                        checked: kcm.showEnabled
                        onToggled: kcm.showEnabled = checked
                    }
                    QQC2.SpinBox {
                        Kirigami.FormData.label: i18n("Start after idle:")
                        from: 1
                        to: 1440
                        value: kcm.startMinutes
                        enabled: kcm.showEnabled
                        onValueModified: kcm.startMinutes = value
                        textFromValue: (value, locale) => i18np("%1 minute", "%1 minutes", value)
                        valueFromText: (text, locale) => parseInt(text)
                    }
                    QQC2.SpinBox {
                        Kirigami.FormData.label: i18n("Change screensaver every:")
                        from: 1
                        to: 1440
                        value: kcm.changeMinutes
                        enabled: kcm.showEnabled
                        onValueModified: kcm.changeMinutes = value
                        textFromValue: (value, locale) => i18np("%1 minute", "%1 minutes", value)
                        valueFromText: (text, locale) => parseInt(text)
                    }
                    QQC2.Label {
                        Kirigami.FormData.label: i18n("Lock screen automatically:")
                        text: kcm.lockAutomatically ? i18np("After %1 minute", "After %1 minutes", kcm.lockMinutes) : i18nc("the screen is never locked automatically", "Never")
                    }
                    QQC2.Label {
                        Kirigami.FormData.label: i18n("Desktop background:")
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: kcm.desktopKinds.map(kind => kcm.kindName(kind)).join(", ")
                    }
                    QQC2.Label {
                        Kirigami.FormData.label: i18n("Lock screen background:")
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: kcm.kindName(kcm.lockKind)
                    }
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.disabledTextColor
                    text: i18n("The show also plays after a manual lock while the screen is on. The desktop and the lock screen each keep their own background: a picture, a slide show, a stereo image or a video is chosen on Wallpaper for the desktop and on Screen Locking for the lock screen.")
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    visible: !kcm.kindInstalled("org.kde.video")
                    wrapMode: Text.WordWrap
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.neutralTextColor
                    text: i18n("The video background is not installed (the package %1). Install it to choose a video on Wallpaper and on Screen Locking.", "qml-module-org-kde-video-wallpaper")
                }
            }
        }
    }

    footer: Flow {
        spacing: Kirigami.Units.smallSpacing
        padding: Kirigami.Units.smallSpacing

        QQC2.Button {
            objectName: "linkWallpaper"
            text: i18nc("@action:button opens that settings page", "Wallpaper…")
            icon.name: "preferences-desktop-wallpaper"
            onClicked: KCM.KCMLauncher.openSystemSettings("kcm_wallpaper")
        }
        QQC2.Button {
            objectName: "linkLocking"
            text: i18nc("@action:button opens that settings page", "Screen Locking…")
            icon.name: "preferences-desktop-user-password"
            onClicked: KCM.KCMLauncher.openSystemSettings("kcm_screenlocker")
        }
        QQC2.Button {
            text: i18nc("@action:button opens that settings page", "Display & Monitor…")
            icon.name: "preferences-desktop-display"
            onClicked: KCM.KCMLauncher.openSystemSettings("kcm_kscreen")
        }
        QQC2.Button {
            text: i18nc("@action:button opens that settings page", "Power Management…")
            icon.name: "preferences-system-power-management"
            onClicked: KCM.KCMLauncher.openSystemSettings("kcm_powerdevilprofilesconfig")
        }
        QQC2.Button {
            visible: kcm.varietyInstalled
            text: i18nc("@action:button opens the wallpaper slide show's own settings", "Stereo Variety (slide show)…")
            icon.name: "variety"
            onClicked: varietyMessage.visible = !kcm.openVariety()
        }
    }
}
