/*
    SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kcm_ums.h"

#include <KLocalizedString>
#include <KPluginFactory>

#include <QDesktopServices>
#include <QProcess>

K_PLUGIN_CLASS_WITH_JSON(UmsKcm, "kcm_ums.json")

UmsKcm::UmsKcm(QObject *parent, const KPluginMetaData &data)
    : KQuickConfigModule(parent, data)
    , m_profile(UmsProfile::defaultDirectory())
{
    setButtons(Help | Apply | Default);
}

bool UmsKcm::serverEnabled() const
{
    return m_serverEnabled;
}

void UmsKcm::setServerEnabled(bool enabled)
{
    if (m_serverEnabled != enabled) {
        m_serverEnabled = enabled;
        Q_EMIT serverEnabledChanged();
        updateState();
    }
}

QString UmsKcm::serverName() const
{
    return m_serverName;
}

void UmsKcm::setServerName(const QString &name)
{
    if (m_serverName != name) {
        m_serverName = name;
        Q_EMIT serverNameChanged();
        updateState();
    }
}

QStringList UmsKcm::folders() const
{
    return m_folders;
}

QString UmsKcm::errorMessage() const
{
    return m_error;
}

void UmsKcm::setError(const QString &message)
{
    if (m_error != message) {
        m_error = message;
        Q_EMIT errorMessageChanged();
    }
}

void UmsKcm::addFolder(const QUrl &folder)
{
    const QString path = folder.toLocalFile();
    if (!path.isEmpty() && !m_folders.contains(path)) {
        m_folders << path;
        Q_EMIT foldersChanged();
        updateState();
    }
}

void UmsKcm::removeFolder(int index)
{
    if (index >= 0 && index < m_folders.size()) {
        m_folders.removeAt(index);
        Q_EMIT foldersChanged();
        updateState();
    }
}

void UmsKcm::restoreDefaultFolders()
{
    m_folders = UmsProfile::defaultFolders();
    Q_EMIT foldersChanged();
    updateState();
}

void UmsKcm::openWebInterface()
{
    QDesktopServices::openUrl(QUrl(QStringLiteral("http://localhost:9001")));
}

void UmsKcm::load()
{
    m_savedEnabled = m_service.isEnabled();
    m_savedName = m_profile.serverName();
    m_savedFolders = m_profile.folders();
    m_serverEnabled = m_savedEnabled;
    m_serverName = m_savedName;
    m_folders = m_savedFolders;
    Q_EMIT serverEnabledChanged();
    Q_EMIT serverNameChanged();
    Q_EMIT foldersChanged();
    setError(QString());
    setNeedsSave(false);
    updateState();
}

void UmsKcm::save()
{
    QString error;
    if (m_folders != m_savedFolders && !m_profile.setFolders(m_folders)) {
        error = m_profile.errorString();
    }
    if (error.isEmpty() && m_serverName != m_savedName) {
        if (!m_profile.setServerName(m_serverName)) {
            error = m_profile.errorString();
        } else if (m_serverEnabled == m_savedEnabled && m_service.isActive() && !m_service.restartIfActive()) {
            error = m_service.errorString();
        }
    }
    if (error.isEmpty() && m_serverEnabled != m_savedEnabled && !m_service.setEnabled(m_serverEnabled)) {
        error = m_service.errorString();
    }
    if (!error.isEmpty()) {
        setError(i18n("Could not change the media server: %1", error));
        return;
    }
    load();
}

void UmsKcm::defaults()
{
    setServerEnabled(false);
    setServerName(QString());
    restoreDefaultFolders();
}

void UmsKcm::updateState()
{
    setNeedsSave(m_serverEnabled != m_savedEnabled || m_serverName != m_savedName || m_folders != m_savedFolders);
    setRepresentsDefaults(!m_serverEnabled && m_serverName.isEmpty() && m_folders == UmsProfile::defaultFolders());
}

#include "kcm_ums.moc"

void UmsKcm::openDeviceControls()
{
    if (!QProcess::startDetached(QStringLiteral("ums-renderer"), {})) {
        setError(i18n("Media Devices could not start."));
    }
}
