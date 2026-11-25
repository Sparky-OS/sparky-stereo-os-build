// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include "daemon.h"

#include <KLocalizedString>
#include <KSharedConfig>
#include <KConfigGroup>

#include <QCollator>
#include <algorithm>
#include "castchannel.h"
#include "logging.h"

#include <QDBusConnection>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QTimer>

namespace Throw
{

namespace
{
constexpr int AskTimeoutMs = 5000;

QString json(const QJsonValue &value)
{
    return value.isArray() ? QString::fromUtf8(QJsonDocument(value.toArray()).toJson(QJsonDocument::Compact))
                           : QString::fromUtf8(QJsonDocument(value.toObject()).toJson(QJsonDocument::Compact));
}

QString hostFor(const Device &device)
{
    if (device.address.isNull()) {
        return device.host;
    }
    return device.address.protocol() == QAbstractSocket::IPv6Protocol ? QLatin1Char('[') + device.address.toString() + QLatin1Char(']')
                                                                      : device.address.toString();
}

QJsonObject volumeOf(const QJsonObject &status)
{
    return status.value(QStringLiteral("volume")).toObject();
}
} // namespace

Daemon::Daemon(QObject *parent)
    : QObject(parent)
{
    connect(&m_discovery, &Discovery::deviceAdded, this, [this] {
        Q_EMIT DevicesChanged();
    });
    connect(&m_discovery, &Discovery::deviceRemoved, this, [this](const QString &id) {
        if (auto session = m_sessions.value(id)) {
            session->stop();
        }
        Q_EMIT DevicesChanged();
    });
}

bool Daemon::start()
{
    if (!m_table.error().isEmpty()) {
        qCWarning(THROW) << m_table.error();
    }
    auto bus = QDBusConnection::sessionBus();
    if (!bus.registerObject(QStringLiteral("/org/sparky/Throw"), this, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals)) {
        qCCritical(THROW) << "cannot register /org/sparky/Throw on the session bus";
        return false;
    }
    if (!bus.registerService(QStringLiteral("org.sparky.Throw"))) {
        qCCritical(THROW) << "org.sparky.Throw is already taken on the session bus:" << bus.lastError().message();
        return false;
    }
    if (!m_discovery.start()) {
        // without DNS-SD no device appears by itself: said in the log and on the page (Devices() is empty)
        qCWarning(THROW) << m_discovery.error();
    }
    return true;
}

namespace
{
KConfigGroup choiceGroup(const QString &id)
{
    return KSharedConfig::openConfig(QStringLiteral("sparky-stereo-throwrc"))->group(QStringLiteral("Device")).group(id);
}
QString words(const char *context, const QString &text)
{
    // the table's words in the person's language where the catalogue has them; a product's own name stays
    return text.isEmpty() ? text : ki18nc(context, text.toUtf8().constData()).toString();
}
} // namespace

Plan Daemon::planFor(const Device &device) const
{
    ModelRow row = m_table.row(device.model);
    if (device.group) {
        row.video = false;
    }
    const KConfigGroup group = choiceGroup(device.id);
    return Codecs::plan(row, group.readEntry("Codec", QString()), group.readEntry("Mode", QString()));
}

QJsonObject Daemon::describe(const Device &device) const
{
    const ModelRow row = m_table.row(device.model);
    const Plan plan = planFor(device);
    const KConfigGroup group = choiceGroup(device.id);
    const QStringList here = Codecs::encodable();
    QJsonArray codecs;
    for (const auto &c : row.codecs) {
        QJsonArray modes;
        for (const auto &m : c.modes) {
            modes.append(m.text());
        }
        const bool available = here.contains(c.codec);
        codecs.append(QJsonObject{
            {QStringLiteral("codec"), c.codec},
            {QStringLiteral("label"), Codecs::info(c.codec).label},
            {QStringLiteral("profile"), c.profile},
            {QStringLiteral("level"), c.level},
            {QStringLiteral("modes"), modes},
            {QStringLiteral("default"), c.defaultMode.text()},
            {QStringLiteral("available"), available},
            {QStringLiteral("missing"), available ? QString() : Codecs::missing(c.codec)},
        });
    }
    const bool video = row.video && !device.group;
    QJsonObject o{
        {QStringLiteral("id"), device.id},
        {QStringLiteral("name"), device.name},
        {QStringLiteral("model"), device.model},
        {QStringLiteral("generation"), words("@info a Cast model's generation, from the device table", row.generation)},
        {QStringLiteral("short"), words("@info a Cast model in a few words, from the device table", row.shortWords)},
        {QStringLiteral("known"), row.known},
        {QStringLiteral("video"), video},
        {QStringLiteral("group"), device.group},
        {QStringLiteral("host"), device.host},
        {QStringLiteral("address"), device.address.toString()},
        {QStringLiteral("port"), device.port},
        {QStringLiteral("codecs"), codecs},
        {QStringLiteral("choiceCodec"), group.readEntry("Codec", QString())},
        {QStringLiteral("choiceMode"), group.readEntry("Mode", QString())},
        {QStringLiteral("codec"), video ? plan.info.codec : QString()},
        {QStringLiteral("codecLabel"), video ? plan.info.label : QString()},
        {QStringLiteral("autoCodecLabel"), video ? Codecs::plan(row, QString(), QString()).info.label : QString()},
        {QStringLiteral("mode"), video && plan.mode.isValid() ? plan.mode.text() : QString()},
        {QStringLiteral("level"), video && row.codecRow(plan.info.codec) ? row.codecRow(plan.info.codec)->level : QString()},
        {QStringLiteral("container"), plan.info.format},
        {QStringLiteral("sound"), Codecs::soundWords(plan).translated()},
        {QStringLiteral("limited"), plan.limited.translated()},
        {QStringLiteral("planError"), plan.error.translated()},
        {QStringLiteral("state"), QStringLiteral("idle")},
    };
    if (const auto last = m_lastState.constFind(device.id); last != m_lastState.constEnd()) {
        o.insert(QStringLiteral("state"), last->first);
        o.insert(QStringLiteral("detail"), last->second);
    }
    if (auto session = m_sessions.value(device.id)) {
        o.insert(QStringLiteral("state"), session->state());
        o.insert(QStringLiteral("detail"), session->detail());
        if (session->plan().video) {
            o.insert(QStringLiteral("mode"), session->plan().mode.text());
            o.insert(QStringLiteral("codec"), session->plan().info.codec);
            o.insert(QStringLiteral("codecLabel"), session->plan().info.label);
        }
        o.insert(QStringLiteral("sink"), session->sinkName());
    }
    return o;
}

QString Daemon::SetChoice(const QString &id, const QString &codec, const QString &mode)
{
    const auto device = m_discovery.device(id);
    if (!device) {
        return json(QJsonObject{{QStringLiteral("error"), QStringLiteral("no device %1 has been found").arg(id)}});
    }
    const ModelRow row = m_table.row(device->model);
    if (!codec.isEmpty() && !row.codecRow(codec)) {
        return json(QJsonObject{{QStringLiteral("error"), QStringLiteral("%1 does not take %2").arg(device->name, codec)}});
    }
    if (!mode.isEmpty()) {
        const CodecRow *c = row.codecRow(codec.isEmpty() ? Codecs::plan(row, QString(), QString()).info.codec : codec);
        if (!c || !c->allows(Mode::parse(mode))) {
            return json(QJsonObject{{QStringLiteral("error"), QStringLiteral("%1 is not a mode %2 takes in that codec").arg(mode, device->name)}});
        }
    }
    // kept per device, by its identity, as KWin keeps its network screen's 3D format by the same identity
    KConfigGroup group = choiceGroup(id);
    if (codec.isEmpty()) {
        group.deleteEntry("Codec");
    } else {
        group.writeEntry("Codec", codec);
    }
    if (mode.isEmpty()) {
        group.deleteEntry("Mode");
    } else {
        group.writeEntry("Mode", mode);
    }
    group.sync();
    Q_EMIT DevicesChanged();
    return json(describe(*device));
}

QString Daemon::Status(const QString &id)
{
    if (auto session = m_sessions.value(id)) {
        return json(session->status());
    }
    QJsonObject o{{QStringLiteral("state"), QStringLiteral("idle")}};
    if (const auto last = m_lastState.constFind(id); last != m_lastState.constEnd()) {
        o.insert(QStringLiteral("state"), last->first);
        o.insert(QStringLiteral("detail"), last->second);
    }
    return json(o);
}

QString Daemon::Devices()
{
    // by the names the devices give themselves, in the person's collation; the identity orders equal names
    auto devices = m_discovery.devices();
    QCollator collator;
    collator.setNumericMode(true);
    std::sort(devices.begin(), devices.end(), [&collator](const Device &a, const Device &b) {
        const int order = collator.compare(a.name, b.name);
        return order != 0 ? order < 0 : a.id < b.id;
    });
    QJsonArray list;
    for (const auto &device : devices) {
        list.append(describe(device));
    }
    return json(list);
}

QString Daemon::Throw(const QString &id)
{
    const auto device = m_discovery.device(id);
    if (!device) {
        return QStringLiteral("no device %1 has been found").arg(id);
    }
    if (auto session = m_sessions.value(id); session && (session->state() == QLatin1String("starting") || session->state() == QLatin1String("throwing"))) {
        return QString();
    }
    auto session = new ThrowSession(*device, m_table.row(device->model), planFor(*device), this);
    m_sessions.insert(id, session);
    connect(session, &ThrowSession::stateChanged, this, [this, id](const QString &state, const QString &detail) {
        m_lastState.insert(id, {state, detail});
        Q_EMIT StateChanged(id, state, detail);
        Q_EMIT DevicesChanged();
    });
    connect(session, &ThrowSession::finished, this, [this, id, session] {
        QTimer::singleShot(0, session, &QObject::deleteLater);
        Q_UNUSED(id)
    });
    session->start();
    return QString();
}

QString Daemon::Stop(const QString &id)
{
    auto session = m_sessions.value(id);
    if (!session) {
        return QStringLiteral("no Throw to %1 is running").arg(id);
    }
    session->stop();
    return QString();
}

QString Daemon::DeviceInfo(const QString &id)
{
    const auto device = m_discovery.device(id);
    if (!device) {
        return json(QJsonObject{{QStringLiteral("error"), QStringLiteral("no device %1 has been found").arg(id)}});
    }
    setDelayedReply(true);
    auto &request = m_info[id];
    request.replies.append(message().createReply());
    if (request.pending) {
        return QString();
    }
    request.info = describe(*device);
    request.pending = 3;

    // what the device says about itself without an account: /setup/eureka_info, HTTPS on 8443 first, plain HTTP on 8008
    // after, an empty Host header after a 403 (pychromecast 14.1.1 dial.py: get_device_info, _urlopen)
    auto ask = [this, id, device](const QString &params, const QString &key) {
        auto attempt = std::make_shared<std::function<void(int)>>();
        *attempt = [this, id, device, params, key, attempt](int step) {
            const bool secure = step < 2;
            const QString url = QStringLiteral("%1://%2:%3/setup/eureka_info?params=%4")
                                    .arg(secure ? QStringLiteral("https") : QStringLiteral("http"), hostFor(*device))
                                    .arg(secure ? 8443 : 8008)
                                    .arg(params);
            QNetworkRequest req{QUrl(url)};
            req.setTransferTimeout(AskTimeoutMs);
            req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
            if (step % 2) {
                req.setRawHeader("Host", "");
            }
            QNetworkReply *reply = m_network.get(req);
            if (secure) {
                connect(reply, &QNetworkReply::sslErrors, reply, [reply] {
                    reply->ignoreSslErrors(); // the device's own certificate, as every public sender accepts it
                });
            }
            connect(reply, &QNetworkReply::finished, this, [this, id, url, reply, step, key, attempt] {
                reply->deleteLater();
                const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
                if (reply->error() == QNetworkReply::NoError) {
                    QJsonObject got = QJsonDocument::fromJson(reply->readAll()).object();
                    got.insert(QStringLiteral("source"), url);
                    m_info[id].info.insert(key, got);
                } else if (status == 403 && step % 2 == 0) {
                    (*attempt)(step + 1);
                    return;
                } else if (step < 2) {
                    (*attempt)(2);
                    return;
                } else {
                    m_info[id].info.insert(key, QJsonObject{{QStringLiteral("source"), url}, {QStringLiteral("status"), status},
                                                           {QStringLiteral("error"), reply->errorString()}});
                }
                finishInfo(id);
            });
        };
        (*attempt)(0);
    };
    ask(QStringLiteral("device_info,name"), QStringLiteral("eureka"));
    ask(QStringLiteral("build_info"), QStringLiteral("build"));

    // the platform receiver's status: volume and its kind, standby, the running application
    auto channel = new CastChannel(this);
    auto timer = new QTimer(channel);
    timer->setSingleShot(true);
    auto done = [this, id, channel](const QJsonObject &value) {
        if (channel->property("done").toBool()) {
            return;
        }
        channel->setProperty("done", true);
        m_info[id].info.insert(QStringLiteral("receiver"), value);
        channel->close();
        channel->deleteLater();
        finishInfo(id);
    };
    connect(channel, &CastChannel::ready, channel, [channel] {
        channel->getStatus();
    });
    connect(channel, &CastChannel::receiverStatus, channel, [done](const QJsonObject &status) {
        done(status);
    });
    connect(channel, &CastChannel::closed, channel, [done](const QString &why) {
        done(QJsonObject{{QStringLiteral("error"), why}});
    });
    connect(timer, &QTimer::timeout, channel, [done] {
        done(QJsonObject{{QStringLiteral("error"), QStringLiteral("no answer within 5 seconds")}});
    });
    timer->start(AskTimeoutMs);
    channel->open(device->address.isNull() ? device->host : device->address.toString(), device->port);
    return QString();
}

void Daemon::finishInfo(const QString &id)
{
    auto &request = m_info[id];
    if (--request.pending > 0) {
        return;
    }
    const QString answer = json(request.info);
    for (auto &reply : request.replies) {
        reply << answer;
        QDBusConnection::sessionBus().send(reply);
    }
    m_info.remove(id);
}

QString Daemon::SetVolume(const QString &id, double level, int muted)
{
    const auto device = m_discovery.device(id);
    if (!device) {
        return json(QJsonObject{{QStringLiteral("error"), QStringLiteral("no device %1 has been found").arg(id)}});
    }
    setDelayedReply(true);
    const QDBusMessage reply = message().createReply();
    auto channel = new CastChannel(this);
    auto timer = new QTimer(channel);
    timer->setSingleShot(true);
    auto finish = [channel, reply](const QJsonObject &value) {
        if (channel->property("done").toBool()) {
            return;
        }
        channel->setProperty("done", true);
        QDBusMessage answer = reply;
        answer << json(value);
        QDBusConnection::sessionBus().send(answer);
        channel->close();
        channel->deleteLater();
    };
    connect(channel, &CastChannel::ready, channel, [channel, level, muted] {
        const int request = channel->setVolume(level < 0 ? std::nullopt : std::optional<double>(level),
                                               muted < 0 ? std::nullopt : std::optional<bool>(muted != 0));
        channel->setProperty("request", request);
    });
    connect(channel, &CastChannel::receiverStatus, channel, [channel, finish](const QJsonObject &status, int requestId) {
        if (requestId && requestId == channel->property("request").toInt()) {
            // what the device holds now, read back from its answer, never what was asked
            finish(QJsonObject{{QStringLiteral("volume"), volumeOf(status)}});
        }
    });
    connect(channel, &CastChannel::requestRefused, channel, [finish](const QString &type, const QString &reason) {
        finish(QJsonObject{{QStringLiteral("error"), QString(type + QLatin1Char(' ') + reason)}});
    });
    connect(channel, &CastChannel::closed, channel, [finish](const QString &why) {
        finish(QJsonObject{{QStringLiteral("error"), why}});
    });
    connect(timer, &QTimer::timeout, channel, [finish] {
        finish(QJsonObject{{QStringLiteral("error"), QStringLiteral("no answer within 5 seconds")}});
    });
    timer->start(AskTimeoutMs);
    channel->open(device->address.isNull() ? device->host : device->address.toString(), device->port);
    return QString();
}

} // namespace Throw
