// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include "throwkcm.h"

#include <KLocalizedString>
#include <KPluginFactory>

#include <QDBusConnection>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>

K_PLUGIN_CLASS_WITH_JSON(ThrowKcm, "kcm_sparkystereo_throw.json")

namespace
{
const QString Service = QStringLiteral("org.sparky.Throw");
const QString Path = QStringLiteral("/org/sparky/Throw");
} // namespace

ThrowKcm::ThrowKcm(QObject *parent, const KPluginMetaData &data, const QVariantList &args)
    : KQuickConfigModule(parent, data)
{
    for (const auto &arg : args) {
        const QString text = arg.toString();
        if (text.startsWith(QLatin1String("device="))) {
            m_openDevice = text.mid(7);
        }
    }
    setButtons(KQuickConfigModule::NoAdditionalButton);
    QDBusConnection::sessionBus().connect(Service, Path, Service, QStringLiteral("DevicesChanged"), this, SLOT(onDevicesChanged()));
    refresh();
}

QDBusInterface *ThrowKcm::throwd()
{
    if (!m_throwd) {
        m_throwd = new QDBusInterface(Service, Path, Service, QDBusConnection::sessionBus(), this);
        m_throwd->setTimeout(30000);
    }
    return m_throwd;
}

void ThrowKcm::onDevicesChanged()
{
    refresh();
}

void ThrowKcm::refresh()
{
    auto watcher = new QDBusPendingCallWatcher(throwd()->asyncCall(QStringLiteral("Devices")), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QString> reply = *w;
        m_running = reply.isValid();
        m_devices.clear();
        if (reply.isValid()) {
            for (const auto &value : QJsonDocument::fromJson(reply.value().toUtf8()).array()) {
                m_devices.append(value.toObject().toVariantMap());
            }
        }
        Q_EMIT devicesChanged();
    });
}

void ThrowKcm::setError(const QString &error)
{
    m_lastError = error;
    Q_EMIT lastErrorChanged();
}

void ThrowKcm::throwTo(const QString &id)
{
    auto watcher = new QDBusPendingCallWatcher(throwd()->asyncCall(QStringLiteral("Throw"), id), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QString> reply = *w;
        setError(reply.isValid() ? reply.value() : reply.error().message());
        refresh();
    });
}

void ThrowKcm::stop(const QString &id)
{
    auto watcher = new QDBusPendingCallWatcher(throwd()->asyncCall(QStringLiteral("Stop"), id), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QString> reply = *w;
        setError(reply.isValid() ? reply.value() : reply.error().message());
        refresh();
    });
}

void ThrowKcm::loadInfo(const QString &id)
{
    m_infoId = id;
    m_infoLoading = true;
    m_info.clear();
    Q_EMIT infoChanged();
    auto watcher = new QDBusPendingCallWatcher(throwd()->asyncCall(QStringLiteral("DeviceInfo"), id), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, id](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        if (id != m_infoId) {
            return;
        }
        QDBusPendingReply<QString> reply = *w;
        m_infoLoading = false;
        if (reply.isValid()) {
            m_info = QJsonDocument::fromJson(reply.value().toUtf8()).object().toVariantMap();
        } else {
            m_info = {{QStringLiteral("error"), reply.error().message()}};
        }
        Q_EMIT infoChanged();
    });
}

void ThrowKcm::setVolume(const QString &id, double level, int muted)
{
    auto watcher = new QDBusPendingCallWatcher(throwd()->asyncCall(QStringLiteral("SetVolume"), id, level, muted), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, id](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QString> reply = *w;
        const QJsonObject answer = QJsonDocument::fromJson(reply.isValid() ? reply.value().toUtf8() : QByteArray()).object();
        if (!reply.isValid() || answer.contains(QStringLiteral("error"))) {
            // the device refused, or did not answer: said, and the page shows what the device holds after
            setError(reply.isValid() ? answer.value(QStringLiteral("error")).toString() : reply.error().message());
        } else {
            setError(QString());
        }
        loadInfo(id);
    });
}

void ThrowKcm::setChoice(const QString &id, const QString &codec, const QString &mode)
{
    auto watcher = new QDBusPendingCallWatcher(throwd()->asyncCall(QStringLiteral("SetChoice"), id, codec, mode), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QString> reply = *w;
        const QJsonObject answer = QJsonDocument::fromJson(reply.isValid() ? reply.value().toUtf8() : QByteArray()).object();
        setError(!reply.isValid() ? reply.error().message() : answer.value(QStringLiteral("error")).toString());
        refresh();
    });
}

void ThrowKcm::openOnlineAccounts()
{
    QProcess::startDetached(QStringLiteral("systemsettings"), {QStringLiteral("kcm_kaccounts")});
}

void ThrowKcm::openDisplaySettings()
{
    QProcess::startDetached(QStringLiteral("systemsettings"), {QStringLiteral("kcm_kscreen")});
}

#include "throwkcm.moc"
