// SPDX-License-Identifier: GPL-2.0-or-later
#include "showsession.h"
#include <KConfigGroup>
#include <KIdleTime>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QGuiApplication>
#include <QLoggingCategory>
Q_LOGGING_CATEGORY(stereoShowLog, "org.sparky.stereoshow", QtWarningMsg)

ShowSession::ShowSession(bool greeter, QObject *parent)
    : QObject(parent), m_client(this), m_dpms(this), m_greeter(greeter)
{
    m_watcher = KConfigWatcher::create(KSharedConfig::openConfig(QStringLiteral("stereoshowrc")));
    connect(m_watcher.data(), &KConfigWatcher::configChanged, this, &ShowSession::reload);
    connect(&m_dpms, &KScreen::Dpms::modeChanged, this, [this](KScreen::Dpms::Mode mode, QScreen *screen) {
        m_screens[screen] = mode == KScreen::Dpms::On;
        update();
    });
    connect(qGuiApp, &QGuiApplication::screenRemoved, this, [this](QScreen *screen) { m_screens.remove(screen); update(); });
    auto system = QDBusConnection::systemBus();
    system.connect(QStringLiteral("org.freedesktop.UPower"), QStringLiteral("/org/freedesktop/UPower"),
                   QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("PropertiesChanged"),
                   this, SLOT(batteryChanged(QString,QVariantMap,QStringList)));
    m_powerWatcher.setConnection(system);
    m_powerWatcher.setWatchMode(QDBusServiceWatcher::WatchForOwnerChange);
    m_powerWatcher.addWatchedService(QStringLiteral("org.freedesktop.UPower"));
    connect(&m_powerWatcher, &QDBusServiceWatcher::serviceOwnerChanged, this, [this] {
        m_onAC = false; update(); readBattery();
    });
    if (!greeter) {
        auto session = QDBusConnection::sessionBus();
        session.connect(QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("/ScreenSaver"),
                        QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("ActiveChanged"), this, SLOT(lockChanged(bool)));
        m_lockWatcher.setConnection(session);
        m_lockWatcher.setWatchMode(QDBusServiceWatcher::WatchForOwnerChange);
        m_lockWatcher.addWatchedService(QStringLiteral("org.freedesktop.ScreenSaver"));
        connect(&m_lockWatcher, &QDBusServiceWatcher::serviceOwnerChanged, this, &ShowSession::readLock);
        readLock();
        auto *idle = KIdleTime::instance();
        connect(idle, &KIdleTime::timeoutReached, this, [this, idle](int id) {
            if (id != m_idleId) return;
            m_idle = true; idle->catchNextResumeEvent(); update();
        });
        connect(idle, &KIdleTime::resumingFromIdle, this, [this] { m_idle = false; update(); });
    }
    reload(); readBattery();
}

void ShowSession::reload()
{
    KConfigGroup config(m_watcher->config(), QStringLiteral("General"));
    const int previousStart = m_policy.startSeconds;
    m_policy.enabled = config.readEntry("Enabled", true);
    m_policy.startSeconds = qBound(60, config.readEntry("IdleSeconds", 8100), 86400);
    m_policy.cycleSeconds = qBound(60, config.readEntry("CycleSeconds", 600), 86400);
    m_client.setCycleSeconds(m_policy.cycleSeconds);
    if (!m_greeter && (m_idleId < 0 || previousStart != m_policy.startSeconds)) {
        auto *idle = KIdleTime::instance();
        if (m_idleId >= 0) idle->removeIdleTimeout(m_idleId);
        m_idleId = idle->addIdleTimeout(m_policy.startSeconds * 1000);
        m_idle = false;
    }
    update();
}

void ShowSession::readLock()
{
    lockChanged(true);
    auto call = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("/ScreenSaver"),
                                              QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("GetActive"));
    auto *reply = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(call), this);
    connect(reply, &QDBusPendingCallWatcher::finished, this, [this, reply] {
        QDBusPendingReply<bool> result = *reply;
        if (!result.isError()) lockChanged(result.value());
        reply->deleteLater();
    });
}

void ShowSession::readBattery()
{
    auto call = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.UPower"), QStringLiteral("/org/freedesktop/UPower"),
                                              QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
    call << QStringLiteral("org.freedesktop.UPower") << QStringLiteral("OnBattery");
    auto *reply = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(call), this);
    connect(reply, &QDBusPendingCallWatcher::finished, this, [this, reply] {
        QDBusPendingReply<QDBusVariant> result = *reply;
        m_onAC = !result.isError() && result.value().variant().metaType().id() == QMetaType::Bool && !result.value().variant().toBool();
        reply->deleteLater(); update();
    });
}

void ShowSession::batteryChanged(const QString &interface, const QVariantMap &values, const QStringList &invalidated)
{
    if (interface != QStringLiteral("org.freedesktop.UPower")) return;
    if (values.contains(QStringLiteral("OnBattery"))) {
        auto value = values.value(QStringLiteral("OnBattery"));
        m_onAC = value.metaType().id() == QMetaType::Bool && !value.toBool();
        update();
    } else if (invalidated.contains(QStringLiteral("OnBattery"))) {
        m_onAC = false; update(); readBattery();
    }
}

void ShowSession::lockChanged(bool locked)
{
    m_locked = locked;
    m_idle = false;
    update();
}

void ShowSession::update()
{
    bool displayOn = false;
    for (bool on : std::as_const(m_screens)) displayOn |= on;
    const bool running = m_policy.visible(m_onAC, displayOn, m_greeter,
                                          m_idle ? m_policy.startSeconds : 0, false) && (m_greeter || !m_locked);
    qCDebug(stereoShowLog) << "state" << m_greeter << m_onAC << displayOn << m_locked << m_idle;
    m_client.setRunning(running);
    if (running == m_running) return;
    m_running = running;
    qCDebug(stereoShowLog) << "running" << running << "greeter" << m_greeter << "AC" << m_onAC << "display" << displayOn;
    Q_EMIT runningChanged(running);
}
