// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: root

    function iconFor(severity) {
        return severity === "failed" ? "dialog-error" : severity === "degraded" ? "dialog-warning" : "dialog-information"
    }

    header: ColumnLayout {
        spacing: 0
        Kirigami.InlineMessage {
            objectName: "errorMessage"
            Layout.fillWidth: true
            visible: kcm.errorText.length > 0
            type: Kirigami.MessageType.Error
            text: kcm.errorText
            position: Kirigami.InlineMessage.Position.Header
        }
        Kirigami.InlineMessage {
            objectName: "noticeMessage"
            Layout.fillWidth: true
            visible: kcm.noticeText.length > 0
            type: Kirigami.MessageType.Positive
            text: kcm.noticeText
            position: Kirigami.InlineMessage.Position.Header
        }
    }

    Component {
        id: card
        Kirigami.AbstractCard {
            id: item
            required property var modelData
            readonly property bool isDismissed: modelData.dismissed === true
            Layout.fillWidth: true
            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing
                Kirigami.Icon {
                    source: root.iconFor(item.modelData.severity)
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Heading {
                        objectName: "problemTitle"
                        level: 4
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        text: item.modelData.title
                    }
                    QQC2.Label {
                        objectName: "problemText"
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        text: item.modelData.text
                    }
                    QQC2.Label {
                        objectName: "problemFacts"
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                        text: [item.modelData.severityText, item.modelData.since, item.modelData.over ? i18nc("@info", "Not happening now") : ""].filter(s => s && s.length > 0).join(" · ")
                    }
                    QQC2.Label {
                        visible: (item.modelData.lastRepair || "").length > 0
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: item.modelData.lastRepair || ""
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        QQC2.Button {
                            objectName: "repairButton"
                            visible: item.modelData.canRepair
                            enabled: !kcm.busy
                            icon.name: "tools-wizard"
                            text: i18nc("@action:button", "Repair")
                            onClicked: kcm.repair(item.modelData.handle)
                        }
                        Repeater {
                            model: item.modelData.labels
                            delegate: QQC2.Button {
                                required property string modelData
                                required property int index
                                objectName: "actionButton"
                                text: modelData
                                onClicked: kcm.runAction(item.modelData.handle, index)
                            }
                        }
                        QQC2.Button {
                            objectName: "dismissButton"
                            visible: item.modelData.canDismiss && !item.isDismissed
                            icon.name: "dialog-cancel"
                            text: i18nc("@action:button", "Dismiss")
                            onClicked: kcm.dismiss(item.modelData.handle)
                        }
                        QQC2.Button {
                            objectName: "bringBackButton"
                            visible: item.isDismissed
                            icon.name: "edit-undo"
                            text: i18nc("@action:button", "Bring back")
                            onClicked: kcm.bringBack(item.modelData.handle)
                        }
                    }
                }
            }
        }
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.PlaceholderMessage {
            objectName: "emptyState"
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.gridUnit * 4
            visible: kcm.current.length === 0 && kcm.dismissed.length === 0
            icon.name: "emblem-ok-symbolic"
            text: i18nc("@info placeholder", "No problems")
            explanation: i18nc("@info placeholder", "Nothing on this computer needs attention. When something fails, it is listed here until it is repaired, and what you dismiss stays listed here too, so you can bring it back.")
        }

        Kirigami.Heading {
            objectName: "currentHeading"
            visible: kcm.current.length > 0 || kcm.dismissed.length > 0
            level: 2
            text: i18ncp("@title:group", "Current problem (%1)", "Current problems (%1)", kcm.current.length)
        }
        QQC2.Label {
            objectName: "currentEmpty"
            visible: kcm.current.length === 0 && kcm.dismissed.length > 0
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            opacity: 0.7
            text: i18nc("@info", "Nothing needs your attention now.")
        }
        Repeater {
            model: kcm.current
            delegate: card
        }

        Kirigami.Heading {
            objectName: "dismissedHeading"
            visible: kcm.dismissed.length > 0
            level: 2
            Layout.topMargin: Kirigami.Units.largeSpacing
            text: i18ncp("@title:group", "Dismissed problem (%1)", "Dismissed problems (%1)", kcm.dismissed.length)
        }
        QQC2.Label {
            visible: kcm.dismissed.length > 0
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            opacity: 0.7
            text: i18nc("@info", "You do not get notified about these. A dismissed problem is shown again when its message changes or a repair fails; a failed service that fails the same way again at a later start stays dismissed.")
        }
        Repeater {
            model: kcm.dismissed
            delegate: card
        }
    }
}
