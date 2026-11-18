import QtQuick
Item {
    width: 200; height: 100
    Item {
        objectName: "tray-item"
        anchors.fill: parent
        MouseArea { objectName: "area"; anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true }
        Item { id: iconContainer; anchors.fill: parent
            Item { objectName: "applet"; anchors.fill: parent }
        }
    }
}
