/*
 *   Copyright 2014 David Edmundson <davidedmundson@kde.org>
 *   Copyright (C) 2014 by Aleix Pol Gonzalez <aleixpol@blue-systems.com>
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
import QtQuick.Layouts

// The Qt 5 theme also showed the battery state, from Plasma's "powermanagement" data engine,
// which Plasma 6 no longer has; the clock now comes from a Timer.
ColumnLayout {
    property date now: new Date()

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: parent.now = new Date()
    }

    BreezeLabel { //should be a heading but we want it _loads_ bigger
        text: Qt.formatTime(parent.now)
        //we fill the width then align the text so that we can make the text shrink to fit
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignRight

        font.weight: Font.DemiBold
        fontSizeMode: Text.HorizontalFit
        font.pointSize: 36
    }

    BreezeLabel {
        text: Qt.formatDate(parent.now, Locale.LongFormat)
        Layout.alignment: Qt.AlignRight
    }
}
