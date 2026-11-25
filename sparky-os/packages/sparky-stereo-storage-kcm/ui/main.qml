// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root
    property var approved: []
    property bool reviewed: false
    function selectItem(id, selected) {
        approved = selected ? approved.concat([id]) : approved.filter(item => item !== id)
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing
        RowLayout {
            Layout.fillWidth: true
            QQC.Label { text: i18n("Volume") }
            QQC.ComboBox {
                Layout.fillWidth: true
                model: kcm.volumes
                textRole: "label"
                valueRole: "path"
                currentIndex: Math.max(0, indexOfValue(kcm.volume))
                enabled: !kcm.busy
                onActivated: {
                    root.approved = []
                    kcm.chooseVolume(currentValue)
                }
                Accessible.name: i18n("Volume")
            }
        }
        QQC.CheckBox {
            text: i18n("Show administrator items")
            checked: kcm.administrator
            enabled: !kcm.busy
            onClicked: {
                root.approved = []
                kcm.chooseAdministrator(checked)
            }
        }
        RowLayout {
            QQC.Label { text: i18n("Minimum age of temporary files (days)") }
            QQC.SpinBox {
                from: 1
                to: 365
                value: kcm.temporaryAge
                editable: true
                enabled: !kcm.busy
                Accessible.name: i18n("Minimum age of temporary files (days)")
                onValueModified: {
                    root.approved = []
                    kcm.setTemporaryAge(value)
                }
            }
        }
        RowLayout {
            QQC.Button {
                text: i18n("Preview")
                enabled: !kcm.busy
                onClicked: {
                    root.approved = []
                    root.reviewed = true
                    kcm.preview()
                }
            }
            QQC.BusyIndicator { running: kcm.busy; visible: running }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            text: i18n("This volume is read-only.")
            visible: kcm.readOnly
        }

        QQC.Label {
            text: i18n("No items to review on this volume.")
            visible: root.reviewed && !kcm.busy && !kcm.items.length && !kcm.errors.length
        }

        Repeater {
            model: kcm.errors
            delegate: QQC.Label {
                required property var modelData
                Layout.fillWidth: true
                text: [modelData.operation, modelData.path, modelData.reason].filter(Boolean).join(" — ")
                wrapMode: Text.WrapAnywhere
            }
        }

        Repeater {
            model: kcm.items
            delegate: QQC.CheckBox {
                required property var modelData
                Layout.fillWidth: true
                text: i18n("%1 · %2 · %3", modelData.label, modelData.path,
                           modelData.estimated ? i18n("%1 (estimate)", kcm.formatSize(modelData.bytes))
                                               : kcm.formatSize(modelData.bytes))
                checked: root.approved.includes(modelData.id)
                enabled: !kcm.busy && !kcm.readOnly
                QQC.ToolTip.text: [modelData.description, modelData.warning].filter(Boolean).join("\n")
                QQC.ToolTip.visible: hovered && QQC.ToolTip.text !== ""
                Accessible.description: QQC.ToolTip.text
                onToggled: root.selectItem(modelData.id, checked)
            }
        }

        QQC.Button {
            text: i18n("Clean up…")
            enabled: !kcm.busy && !kcm.readOnly && root.approved.length > 0
            onClicked: confirm.open()
        }

        QQC.TextField {
            id: search
            Layout.fillWidth: true
            placeholderText: i18n("Search cleaners")
        }
        QQC.CheckBox {
            id: onlySelected
            text: i18n("Show selected cleaners only")
            checked: true
        }

        Repeater {
            model: kcm.cleaners
            delegate: ColumnLayout {
                id: group
                required property var modelData
                readonly property var options: onlySelected.checked && !search.text
                    ? modelData.options.filter(option => option.checked) : modelData.options
                visible: options.length > 0
                    && (!search.text || (modelData.label + " " + modelData.description).toLowerCase().includes(search.text.toLowerCase()))
                Layout.fillWidth: true
                Kirigami.Heading {
                    level: 3
                    text: group.modelData.label
                }
                QQC.Label {
                    text: group.modelData.description
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                    visible: text !== ""
                }
                Repeater {
                    model: group.options
                    delegate: ColumnLayout {
                        id: choice
                        required property var modelData
                        Layout.fillWidth: true
                        QQC.CheckBox {
                            text: choice.modelData.label
                            checked: choice.modelData.checked
                            enabled: !kcm.busy
                            onClicked: {
                                root.approved = []
                                kcm.setOption(group.modelData.id, choice.modelData.id, checked)
                            }
                        }
                        QQC.Label {
                            Layout.fillWidth: true
                            Layout.leftMargin: Kirigami.Units.largeSpacing
                            text: choice.modelData.description
                            wrapMode: Text.Wrap
                            visible: text !== ""
                        }
                        QQC.Label {
                            Layout.fillWidth: true
                            Layout.leftMargin: Kirigami.Units.largeSpacing
                            text: choice.modelData.warning
                            wrapMode: Text.Wrap
                            visible: text !== ""
                        }
                    }
                }
            }
        }


        Kirigami.Heading { level: 2; text: i18n("Schedule") }
        QQC.ComboBox {
            Layout.fillWidth: true
            model: [i18n("Off"), i18n("Weekly reminder"), i18n("Remind me when space is low"), i18n("Weekly cleanup")]
            currentIndex: kcm.schedule
            enabled: !kcm.busy
            onActivated: {
                if (currentIndex === 3) {
                    confirmSchedule.open()
                } else {
                    kcm.setSchedule(currentIndex)
                }
            }
            Accessible.name: i18n("Schedule")
        }
    }

    QQC.Dialog {
        id: confirm
        anchors.centerIn: parent
        title: i18n("Clean up…")
        modal: true
        standardButtons: QQC.Dialog.Ok | QQC.Dialog.Cancel
        QQC.Label { text: i18n("Remove the selected items?"); wrapMode: Text.Wrap }
        onAccepted: {
            const approved = root.approved
            root.approved = []
            kcm.clean(approved)
        }
    }

    QQC.Dialog {
        id: confirmSchedule
        anchors.centerIn: parent
        title: i18n("Weekly cleanup")
        modal: true
        standardButtons: QQC.Dialog.Ok | QQC.Dialog.Cancel
        QQC.Label { text: i18n("Allow weekly cleanup of selected generated caches?"); wrapMode: Text.Wrap }
        onAccepted: kcm.setSchedule(3)
    }
}
