// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import org.kde.ksvg as KSvg
import org.kde.kwin.decoration

Decoration {
    id: root
    Component.onCompleted: {
        borders.left = 4; borders.right = 4; borders.top = 28; borders.bottom = 4;
        maximizedBorders.left = 0; maximizedBorders.right = 0;
        maximizedBorders.top = 28; maximizedBorders.bottom = 0;
    }
    DecorationOptions { id: options; deco: decoration }
    KSvg.FrameSvgItem {
        anchors.fill: parent
        imagePath: Qt.resolvedUrl("../../../../../aurorae/themes/kubabbar-glass/decoration.svg")
        prefix: decoration.client.active ? "decoration" : "decoration-inactive"
        enabledBorders: decoration.client.maximized ? KSvg.FrameSvg.TopBorder : KSvg.FrameSvg.AllBorders
    }
    Item {
        id: titleArea
        width: parent.width; height: 28
        Component.onCompleted: decoration.installTitleItem(titleArea)
    }
    BoxButton {
        id: closeBox
        x: 9; y: 6
        artwork: "close"
        buttonType: DecorationOptions.DecorationButtonClose
    }
    Row {
        id: rightBoxes
        anchors.right: parent.right; anchors.rightMargin: 9
        y: 6; spacing: 6
        BoxButton {
            artwork: decoration.client.maximized ? "restore" : "maximize"
            buttonType: DecorationOptions.DecorationButtonMaximizeRestore
        }
        BoxButton {
            artwork: "minimize"
            buttonType: DecorationOptions.DecorationButtonMinimize
        }
    }
    Item {
        id: titleSpace
        anchors.left: closeBox.right; anchors.leftMargin: 8
        anchors.right: rightBoxes.left; anchors.rightMargin: 8
        height: 28
        Rectangle {
            visible: decoration.client.active
            anchors.centerIn: caption
            width: caption.width + 10
            height: Math.min(24, caption.contentHeight + 4)
            color: "#d8d9d5"
        }
        Text {
            id: caption
            anchors.centerIn: parent
            width: Math.min(implicitWidth, Math.max(0, parent.width - 12))
            height: parent.height
            text: decoration.client.caption
            textFormat: Text.PlainText
            font: options.titleFont
            color: decoration.client.active ? "#1b2119" : "#5d6557"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            renderType: Text.NativeRendering
        }
    }
}
