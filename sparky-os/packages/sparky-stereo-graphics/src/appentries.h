// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "graphicssettings.h"

#include <QList>
#include <QString>
#include <QStringList>

namespace SparkyGraphics
{

// KDE's own key PrefersNonDefaultGPU in a desktop entry; there is no other list.
enum class AppPreference {
    Unset, // the entry says nothing: the category decides
    OtherGpu, // PrefersNonDefaultGPU=true
    MainGpu, // PrefersNonDefaultGPU=false, written explicitly
};

struct AppEntry {
    QString id; // "org.kde.dolphin.desktop"
    QString name;
    QString icon;
    QString path; // the file that wins
    QStringList categories;
    Category category = Category::Other;
    AppPreference preference = AppPreference::Unset; // what the winning file says
    bool fromUserCopy = false; // the winning file is the person's own copy
    bool systemPrefersOther = false; // the system's entry sets the key to true
};

class AppEntries
{
public:
    // dataHome is $XDG_DATA_HOME, dataDirs is $XDG_DATA_DIRS, both without "/applications"
    AppEntries(const QString &dataHome, const QStringList &dataDirs);
    static AppEntries fromEnvironment();

    QList<AppEntry> list() const;
    AppEntry find(const QString &id) const;
    // A desktop file outside the menu (a launcher on the desktop): its own file is the entry
    static AppEntry fromFile(const QString &path);

    // Writes or removes the key in the person's copy of the entry, as KMenuEdit does.
    bool setPreference(const QString &id, AppPreference preference);

    // Brings the copies this page made up to date with the system entries; returns how many it rewrote.
    int refreshCopies();

    static Category categoryFor(const QStringList &desktopCategories);

private:
    QString systemPath(const QString &id) const;
    QString userPath(const QString &id) const;

    QString m_dataHome;
    QStringList m_dataDirs;
};

}
