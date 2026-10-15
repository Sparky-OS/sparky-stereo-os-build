import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

PlasmoidItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.StandardBackground
    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar ? fullRepresentation : compactRepresentation
    compactRepresentation: Rectangle {
        implicitWidth: 48
        implicitHeight: 48
        color: "#ec2361"
        Text { anchors.centerIn: parent; text: "91"; color: "white" }
        Timer { interval: 2000; running: true; repeat: true; onTriggered: root.expanded = true }
    }
    fullRepresentation: Item {
        Layout.minimumWidth: 340
        Layout.minimumHeight: 240
        Layout.preferredWidth: 340
        Layout.preferredHeight: 240
        Text {
            x: 32; y: 28
            text: "BACKGROUND 91%"
            font.pixelSize: 22
            font.bold: true
            color: "#ec2361"
        }
        Kirigami.Icon { x: 32; y: 92; width: 48; height: 48; source: "folder" }
        PlasmaComponents.Button { x: 110; y: 95; width: 160; text: "Opaque control" }
        Text { x: 32; y: 180; text: "Text and icons stay opaque"; color: "#ec2361"; font.pixelSize: 16 }
    }
}
