// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// The Throw page of System Settings: it talks to the Throw daemon (org.sparky.Throw) and knows no Cast of its own.
#pragma once

#include <KQuickConfigModule>
#include <QDBusInterface>
#include <QVariantList>
#include <QVariantMap>

class ThrowKcm : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(QVariantList devices READ devices NOTIFY devicesChanged)
    Q_PROPERTY(bool serviceRunning READ serviceRunning NOTIFY devicesChanged)
    Q_PROPERTY(QVariantMap info READ info NOTIFY infoChanged)
    Q_PROPERTY(QString infoId READ infoId NOTIFY infoChanged)
    Q_PROPERTY(bool infoLoading READ infoLoading NOTIFY infoChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    // a device whose page opens first (System Settings' arguments: device=<id>)
    Q_PROPERTY(QString openDevice READ openDevice CONSTANT)

public:
    ThrowKcm(QObject *parent, const KPluginMetaData &data, const QVariantList &args);
    QString openDevice() const
    {
        return m_openDevice;
    }

    QVariantList devices() const
    {
        return m_devices;
    }
    bool serviceRunning() const
    {
        return m_running;
    }
    QVariantMap info() const
    {
        return m_info;
    }
    QString infoId() const
    {
        return m_infoId;
    }
    bool infoLoading() const
    {
        return m_infoLoading;
    }
    QString lastError() const
    {
        return m_lastError;
    }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void throwTo(const QString &id);
    Q_INVOKABLE void stop(const QString &id);
    Q_INVOKABLE void loadInfo(const QString &id);
    Q_INVOKABLE void setVolume(const QString &id, double level, int muted);
    // the codec and mode for a device ("" for the table's choice), kept by the daemon per device
    Q_INVOKABLE void setChoice(const QString &id, const QString &codec, const QString &mode);
    Q_INVOKABLE void openOnlineAccounts();
    Q_INVOKABLE void openDisplaySettings();

Q_SIGNALS:
    void devicesChanged();
    void infoChanged();
    void lastErrorChanged();

private Q_SLOTS:
    void onDevicesChanged();

private:
    void setError(const QString &error);
    QDBusInterface *throwd();

    QVariantList m_devices;
    bool m_running = false;
    QVariantMap m_info;
    QString m_infoId;
    bool m_infoLoading = false;
    QString m_lastError;
    QDBusInterface *m_throwd = nullptr;
    QString m_openDevice;
};
