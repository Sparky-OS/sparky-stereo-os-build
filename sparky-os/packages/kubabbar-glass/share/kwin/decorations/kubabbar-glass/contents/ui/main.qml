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
    ButtonGroup {
        id: leftButtons
        x: 9; y: 6; height: 16
        spacing: 6
        explicitSpacer: 16
        menuButton: menuComponent
        appMenuButton: appMenuComponent
        minimizeButton: minimizeComponent
        maximizeButton: maximizeComponent
        keepBelowButton: keepBelowComponent
        keepAboveButton: keepAboveComponent
        helpButton: helpComponent
        shadeButton: shadeComponent
        allDesktopsButton: allDesktopsComponent
        closeButton: closeComponent
        buttons: options.titleButtonsLeft
    }
    ButtonGroup {
        id: rightButtons
        anchors.right: parent.right; anchors.rightMargin: 9
        y: 6; height: 16
        spacing: 6
        explicitSpacer: 16
        menuButton: menuComponent
        appMenuButton: appMenuComponent
        minimizeButton: minimizeComponent
        maximizeButton: maximizeComponent
        keepBelowButton: keepBelowComponent
        keepAboveButton: keepAboveComponent
        helpButton: helpComponent
        shadeButton: shadeComponent
        allDesktopsButton: allDesktopsComponent
        closeButton: closeComponent
        buttons: options.titleButtonsRight
    }
    Component { id: menuComponent; MenuButton { width: 16; height: 16; opacity: decoration.client.active ? 1 : 0.6 } }
    Component { id: appMenuComponent; BoxButton { artwork: "appmenu"; buttonType: DecorationOptions.DecorationButtonApplicationMenu } }
    Component { id: minimizeComponent; BoxButton { artwork: "minimize"; buttonType: DecorationOptions.DecorationButtonMinimize } }
    Component {
        id: maximizeComponent
        BoxButton {
            artwork: decoration.client.maximized ? "restore" : "maximize"
            buttonType: DecorationOptions.DecorationButtonMaximizeRestore
        }
    }
    Component { id: keepBelowComponent; BoxButton { artwork: "keepbelow"; buttonType: DecorationOptions.DecorationButtonKeepBelow } }
    Component { id: keepAboveComponent; BoxButton { artwork: "keepabove"; buttonType: DecorationOptions.DecorationButtonKeepAbove } }
    Component { id: helpComponent; BoxButton { artwork: "help"; buttonType: DecorationOptions.DecorationButtonQuickHelp } }
    Component { id: shadeComponent; BoxButton { artwork: "shade"; buttonType: DecorationOptions.DecorationButtonShade } }
    Component { id: allDesktopsComponent; BoxButton { artwork: "alldesktops"; buttonType: DecorationOptions.DecorationButtonOnAllDesktops } }
    Component { id: closeComponent; BoxButton { artwork: "close"; buttonType: DecorationOptions.DecorationButtonClose } }
    Item {
        id: titleSpace
        anchors.left: leftButtons.right; anchors.leftMargin: 8
        anchors.right: rightButtons.left; anchors.rightMargin: 8
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
