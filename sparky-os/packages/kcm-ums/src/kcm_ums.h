/*
    SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KQuickConfigModule>

#include <QStringList>
#include <QUrl>

#include "umsprofile.h"
#include "umsservice.h"

class UmsKcm : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(bool serverEnabled READ serverEnabled WRITE setServerEnabled NOTIFY serverEnabledChanged)
    Q_PROPERTY(QString serverName READ serverName WRITE setServerName NOTIFY serverNameChanged)
    Q_PROPERTY(QStringList folders READ folders NOTIFY foldersChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)

public:
    UmsKcm(QObject *parent, const KPluginMetaData &data);

    bool serverEnabled() const;
    void setServerEnabled(bool enabled);
    QString serverName() const;
    void setServerName(const QString &name);
    QStringList folders() const;
    QString errorMessage() const;

    Q_INVOKABLE void addFolder(const QUrl &folder);
    Q_INVOKABLE void removeFolder(int index);
    Q_INVOKABLE void restoreDefaultFolders();
    Q_INVOKABLE void openWebInterface();

    void load() override;
    void save() override;
    void defaults() override;

Q_SIGNALS:
    void serverEnabledChanged();
    void serverNameChanged();
    void foldersChanged();
    void errorMessageChanged();

private:
    void updateState();
    void setError(const QString &message);

    UmsProfile m_profile;
    UmsService m_service;
    bool m_serverEnabled = false;
    QString m_serverName;
    QStringList m_folders;
    QString m_error;
    bool m_savedEnabled = false;
    QString m_savedName;
    QStringList m_savedFolders;
};
