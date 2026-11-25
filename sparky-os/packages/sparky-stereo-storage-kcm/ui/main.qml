// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root
    property var approved: []
    function selectItem(id, selected) {
        approved = selected ? approved.concat([id]) : approved.filter(item => item !== id)
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: kcm.unavailableVolume !== ""
            type: Kirigami.MessageType.Warning
            text: i18n("The requested volume is unavailable: %1", kcm.unavailableVolume)
        }
        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC.ComboBox {
                Kirigami.FormData.label: i18n("Volume")
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

            QQC.SpinBox {
                Kirigami.FormData.label: i18n("Minimum age of temporary files (days)")
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

            QQC.ComboBox {
                id: periodChoice
                Kirigami.FormData.label: i18n("Period")
                Layout.fillWidth: true
                textRole: "label"
                valueRole: "value"
                model: [
                    {value: "manual", label: i18n("Manually")},
                    {value: "weekly", label: i18n("Weekly")},
                    {value: "fortnightly", label: i18n("Every two weeks")},
                    {value: "monthly", label: i18n("Monthly")}
                ]
                currentIndex: Math.max(0, indexOfValue(kcm.period))
                enabled: !kcm.busy
                onActivated: kcm.setSchedule(currentValue, kcm.scheduledAction)
                Accessible.name: i18n("Period")
            }

            QQC.ComboBox {
                Kirigami.FormData.label: i18n("At that time")
                Layout.fillWidth: true
                textRole: "label"
                valueRole: "value"
                model: [
                    {value: "review", label: i18n("Remind me and let me review")},
                    {value: "automatic", label: i18n("Clean by itself")}
                ]
                currentIndex: Math.max(0, indexOfValue(kcm.scheduledAction))
                enabled: !kcm.busy && kcm.period !== "manual"
                onActivated: kcm.setSchedule(kcm.period, currentValue)
                Accessible.name: i18n("At that time")
            }

            QQC.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: kcm.period === "manual" ? i18n("Review and confirm the items whenever you want to clean up.")
                    : kcm.scheduledAction === "automatic" ? i18n("Cleans the ticked items at the chosen time without asking again.")
                    : i18n("Open the reminder to review the ticked items before confirming removal.")
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
        }

        Kirigami.Heading {
            level: 2
            text: i18n("Last runs")
        }

        QQC.Label {
            visible: kcm.runs.length === 0
            text: i18n("No scheduled runs yet.")
        }

        Repeater {
            model: kcm.runs
            QQC.Label {
                required property var modelData
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                readonly property string summary: modelData.outcome === "failed" ? i18n("Could not start")
                    : modelData.outcome === "review" ? i18n("Reminder sent")
                    : modelData.estimated ? i18n("Estimated space freed: %1", kcm.formatSize(modelData.bytes))
                    : i18n("Space freed: %1", kcm.formatSize(modelData.bytes))
                readonly property string kinds: Object.keys(modelData.kinds).map(kind => {
                    const [id, optionId] = kind.split(".")
                    const cleaner = kcm.cleaners.find(group => group.id === id)
                    const option = cleaner ? cleaner.options.find(item => item.id === optionId) : null
                    return option ? cleaner.label + " — " + option.label : cleaner ? cleaner.label : kind
                }).join(", ")
                text: [modelData.date + " · " + modelData.mount + " · " + summary,
                       kinds, modelData.failures ? i18n("Entries needing review: %1", modelData.failures) : "",
                       modelData.aptDeferred ? i18n("APT items deferred until the next run.") : ""].filter(Boolean).join("\n")
            }
        }

        RowLayout {
            QQC.Button {
                readonly property bool canClean: !kcm.readOnly && root.approved.length > 0
                text: canClean ? i18n("Clean up…") : i18n("Preview")
                enabled: !kcm.busy
                highlighted: true
                onClicked: {
                    if (canClean) {
                        confirm.open()
                    } else {
                        root.approved = []
                        kcm.preview()
                    }
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
            visible: kcm.previewed && !kcm.busy && !kcm.items.length && !kcm.errors.length
        }

        Repeater {
            model: kcm.errors
            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                QQC.Label {
                    readonly property var names: [modelData.cleanerLabel, modelData.optionLabel].filter(Boolean)
                    text: names.join(" — ")
                    visible: text !== ""
                    font.bold: true
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
                QQC.Label {
                    text: modelData.reason
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
                QQC.Label {
                    text: modelData.path || ""
                    visible: text !== ""
                    opacity: 0.75
                    Layout.fillWidth: true
                    wrapMode: Text.WrapAnywhere
                }
            }
        }

        Repeater {
            model: kcm.items
            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC.CheckBox {
                    readonly property var names: [modelData.cleanerLabel, modelData.optionLabel].filter(Boolean)
                    text: names.length ? names.join(" — ") : modelData.label
                    font.bold: true
                    checked: root.approved.includes(modelData.id)
                    enabled: !kcm.busy && !kcm.readOnly
                    Accessible.description: [modelData.description, modelData.warning, modelData.path].filter(Boolean).join("\n")
                    onToggled: root.selectItem(modelData.id, checked)
                }
                QQC.Label {
                    text: modelData.description || modelData.label
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
                QQC.Label {
                    text: modelData.warning || ""
                    visible: text !== ""
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
                QQC.Label {
                    text: modelData.estimated ? i18n("%1 (estimate)", kcm.formatSize(modelData.bytes))
                                              : kcm.formatSize(modelData.bytes)
                    Layout.fillWidth: true
                }
                QQC.Label {
                    text: modelData.path
                    opacity: 0.75
                    Layout.fillWidth: true
                    wrapMode: Text.WrapAnywhere
                }
            }
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

}
