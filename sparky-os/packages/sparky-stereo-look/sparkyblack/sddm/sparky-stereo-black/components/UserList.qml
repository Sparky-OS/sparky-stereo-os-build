/*
 *   Copyright 2014 David Edmundson <davidedmundson@kde.org>
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU Library General Public License as
 *   published by the Free Software Foundation; either version 2 or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details
 *
 *   You should have received a copy of the GNU Library General Public
 *   License along with this program; if not, write to the
 *   Free Software Foundation, Inc.,
 *   51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

// Qt 6 port 2026: Daniel Ramos (Capitain Jack), same licence

import QtQuick

import org.kde.kirigami as Kirigami

ListView {
    id: view
    readonly property string selectedUser: currentItem ? currentItem.userName : ""
    readonly property int userItemWidth: Kirigami.Units.largeSpacing * 8
    readonly property int userItemHeight: Kirigami.Units.largeSpacing * 8
    readonly property int userFaceSize: Kirigami.Units.largeSpacing * 6

    /*
     * Signals that a user was explicitly selected
     */
    signal userSelected;

    orientation: ListView.Horizontal
    highlightRangeMode: ListView.StrictlyEnforceRange

    delegate: UserDelegate {
        name: (model.realName === "") ? model.name : model.realName
        userName: model.name || ""
        iconSource: model.icon ? model.icon : "user-identity"
        width: view.userItemWidth
        faceSize: view.userFaceSize

        onClicked: {
            view.currentIndex = index;
            view.userSelected();
        }
    }

    Keys.onEscapePressed: view.userSelected()
    Keys.onEnterPressed: view.userSelected()
    Keys.onReturnPressed: view.userSelected()
}
