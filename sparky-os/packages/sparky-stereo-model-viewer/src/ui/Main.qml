// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: root
    title: viewer.hasModel ? viewer.fileName : i18nc("@title:window", "Stereo Model Viewer")
    width: 1100
    height: 760
    minimumWidth: 480
    minimumHeight: 360

    FileDialog {
        id: openDialog
        title: i18nc("@title:window", "Open a 3D model")
        nameFilters: viewer.nameFilters
        onAccepted: viewer.open(selectedFile)
    }

    QQC2.Menu {
        id: recentMenu
        Instantiator {
            model: viewer.recent
            delegate: QQC2.MenuItem {
                required property string modelData
                text: modelData.split("/").pop()
                onTriggered: viewer.openPath(modelData)
            }
            onObjectAdded: (index, object) => recentMenu.insertItem(index, object)
            onObjectRemoved: (index, object) => recentMenu.removeItem(object)
        }
        QQC2.MenuSeparator {}
        QQC2.MenuItem {
            text: i18nc("@action:inmenu", "Clear the list")
            onTriggered: viewer.clearRecent()
        }
    }

    pageStack.initialPage: Kirigami.Page {
        id: page
        padding: 0
        titleDelegate: Item {}

        actions: [
            Kirigami.Action {
                text: i18nc("@action:button", "Open…")
                icon.name: "document-open"
                onTriggered: openDialog.open()
            },
            Kirigami.Action {
                text: i18nc("@action:button", "Recent files")
                icon.name: "document-open-recent"
                enabled: viewer.recent.length > 0
                onTriggered: recentMenu.popup()
            },
            Kirigami.Action {
                text: i18nc("@action:button", "Reset view")
                icon.name: "zoom-fit-best"
                enabled: viewer.hasModel
                onTriggered: viewer.reset()
            },
            Kirigami.Action {
                visible: viewer.hasAnimation
                text: viewer.playing ? i18nc("@action:button", "Stop the animation") : i18nc("@action:button", "Play the animation")
                icon.name: viewer.playing ? "media-playback-stop" : "media-playback-start"
                onTriggered: viewer.togglePlay()
            },
            Kirigami.Action {
                text: i18nc("@action:button", "Enable 3D")
                checkable: true
                checked: viewer.stereo
                onToggled: viewer.stereo = checked
            },
            Kirigami.Action {
                text: i18nc("@action:button", "Render resolution per eye")
                Kirigami.Action {
                    text: i18nc("@item:inmenu", "Half of the area")
                    checkable: true
                    checked: viewer.resolution === 50
                    onTriggered: viewer.resolution = 50
                }
                Kirigami.Action {
                    text: i18nc("@item:inmenu", "The size of the area")
                    checkable: true
                    checked: viewer.resolution === 100
                    onTriggered: viewer.resolution = 100
                }
                Kirigami.Action {
                    text: i18nc("@item:inmenu", "One and a half times the area")
                    checkable: true
                    checked: viewer.resolution === 150
                    onTriggered: viewer.resolution = 150
                }
                Kirigami.Action {
                    text: i18nc("@item:inmenu", "Twice the area")
                    checkable: true
                    checked: viewer.resolution === 200
                    onTriggered: viewer.resolution = 200
                }
            },
            Kirigami.Action {
                text: i18nc("@action:button", "Display Settings")
                icon.name: "preferences-desktop-display"
                onTriggered: viewer.showDisplaySettings()
            }
        ]

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: viewer.problem.length > 0
                type: Kirigami.MessageType.Error
                text: viewer.problem
            }
            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: viewer.stereo && viewer.hasModel && viewer.notice.length > 0
                type: Kirigami.MessageType.Information
                text: viewer.notice
            }

            Item {
                id: frame
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: Kirigami.Units.smallSpacing

                Kirigami.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.gridUnit * 4
                    visible: !viewer.hasModel
                    icon.name: "applications-graphics"
                    text: i18nc("@info placeholder", "Open a 3D model or drop a file here")
                    helpfulAction: Kirigami.Action {
                        text: i18nc("@action:button", "Open…")
                        icon.name: "document-open"
                        onTriggered: openDialog.open()
                    }
                }

                // the 3D area: libf3d's window is a child window of this window, laid over this rectangle
                Item {
                    id: area
                    anchors.fill: parent
                    visible: viewer.hasModel
                    function sync() {
                        if (!viewer.hasModel || width < 1 || height < 1)
                            return
                        const p = area.mapToItem(null, 0, 0)
                        viewer.place(root, p.x, p.y, width, height)
                    }
                    onWidthChanged: sync()
                    onHeightChanged: sync()
                    onVisibleChanged: sync()
                    Connections {
                        target: root
                        function onWidthChanged() { area.sync() }
                        function onHeightChanged() { area.sync() }
                    }
                    Timer {
                        interval: 200
                        running: viewer.hasModel
                        repeat: true
                        onTriggered: area.sync()
                    }
                }
            }
        }

        DropArea {
            anchors.fill: parent
            onDropped: drop => {
                if (drop.hasUrls)
                    viewer.open(drop.urls[0])
            }
        }
    }
}
