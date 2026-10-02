/***************************************************************************
 *   Copyright (C) 2014 by Daniel Vrátil <dvratil@redhat.com>              *
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This program is distributed in the hope that it will be useful,       *
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
 *   GNU General Public License for more details.                          *
 *                                                                         *
 *   You should have received a copy of the GNU General Public License     *
 *   along with this program; if not, write to the                         *
 *   Free Software Foundation, Inc.,                                       *
 *   51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA .        *
 ***************************************************************************/

// Qt 6 port 2026: Daniel Ramos (Capitain Jack), same licence

import QtQuick

import org.kde.plasma.components as PlasmaComponents

import org.kde.plasma.workspace.keyboardlayout

PlasmaComponents.Button {
    id: kbLayoutButton
    activeFocusOnTab: true
    implicitWidth: implicitContentWidth + leftPadding + rightPadding
    text: layout.currentLayout

    Accessible.name: i18ndc("plasma_lookandfeel_org.kde.lookandfeel", "Button to change keyboard layout", "Switch layout")

    onClicked: {
        layout.nextLayout();
    }

    visible: Boolean(layout.layouts) && layout.layouts.length > 1


    KeyboardLayout {
          id: layout

          function nextLayout() {
              var layouts = layout.layouts;
              var index = (layouts.indexOf(layout.currentLayout)+1) % layouts.length;

              layout.currentLayout = layouts[index];
          }
    }
}
