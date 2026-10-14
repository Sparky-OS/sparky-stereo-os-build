// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import org.kde.ksvg as KSvg
import org.kde.kwin.decoration

DecorationButton {
    id: button
    property string artwork
    width: 16
    height: 16
    KSvg.SvgItem {
        anchors.fill: parent
        imagePath: Qt.resolvedUrl("../../../../../aurorae/themes/kubabbar-glass/" + button.artwork + ".svg")
        elementId: (button.pressed ? "pressed" : button.hovered ? "hover" : decoration.client.active ? "active" : "inactive")
                   + (!decoration.client.active && (button.pressed || button.hovered) ? "-inactive" : "") + "-center"
    }
}
