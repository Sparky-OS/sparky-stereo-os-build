// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include "frameclient.h"
#include "showpolicy.h"
#include <KConfigWatcher>
#include <KScreenDpms/Dpms>
#include <QDBusServiceWatcher>
#include <QHash>

class ShowSession : public QObject
{
    Q_OBJECT
public:
    explicit ShowSession(bool greeter, QObject *parent = nullptr);
    FrameClient *client() { return &m_client; }
    bool running() const { return m_running; }
Q_SIGNALS:
    void runningChanged(bool running);
private Q_SLOTS:
    void batteryChanged(const QString &interface, const QVariantMap &values, const QStringList &invalidated);
    void lockChanged(bool locked);
private:
    void readBattery();
    void readLock();
    void reload();
    void update();
    FrameClient m_client;
    KScreen::Dpms m_dpms;
    KConfigWatcher::Ptr m_watcher;
    QDBusServiceWatcher m_powerWatcher;
    QDBusServiceWatcher m_lockWatcher;
    QHash<QScreen *, bool> m_screens;
    StereoShow::Policy m_policy;
    bool m_greeter;
    bool m_onAC = false;
    bool m_locked = false;
    bool m_idle = false;
    bool m_running = false;
    int m_idleId = -1;
};
