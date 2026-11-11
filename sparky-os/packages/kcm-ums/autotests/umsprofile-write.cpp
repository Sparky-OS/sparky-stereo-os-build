/*
    SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Test helper: writes a profile with the same code the System Settings page uses.
// Usage: umsprofile-write <profile dir> <server name> <folder>...

#include <QCoreApplication>

#include "../src/umsprofile.h"

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    const QStringList arguments = app.arguments();
    if (arguments.size() < 3) {
        return 2;
    }
    UmsProfile profile(arguments.at(1));
    return profile.setServerName(arguments.at(2)) && profile.setFolders(arguments.mid(3)) ? 0 : 1;
}
