/*
    SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QString>
#include <QStringList>

/**
 * UMS's own configuration: the shared folders in SHARED.conf (a JSON array) and the server name in UMS.conf
 * (a properties file). Both are edited in place: entries and lines this class does not manage stay as they are.
 */
class UmsProfile
{
public:
    explicit UmsProfile(const QString &directory);

    /** UMS_PROFILE, else $XDG_CONFIG_HOME/UMS, as UMS locates its profile. */
    static QString defaultDirectory();

    /** Pictures, Music and Videos as xdg-user-dirs names them; a folder equal to the home folder is left out. */
    static QStringList defaultFolders();

    /** The folders of SHARED.conf; the defaults while the file does not exist yet. */
    QStringList folders() const;
    bool setFolders(const QStringList &folders);

    QString serverName() const;
    bool setServerName(const QString &name);

    QString errorString() const;

private:
    QString sharedPath() const;
    QString configPath() const;

    QString m_directory;
    mutable QString m_error;
};
