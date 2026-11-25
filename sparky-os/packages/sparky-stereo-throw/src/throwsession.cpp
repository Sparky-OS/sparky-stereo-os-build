// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include "throwsession.h"
#include "logging.h"
#include "tell.h"

#include <KConfigGroup>
#include <KLocalizedString>
#include <KSharedConfig>

#include <QJsonArray>
#include <QRegularExpression>

namespace Throw
{

namespace
{
constexpr int FetchTimeoutMs = 20000;
const QString CtxDevice = QStringLiteral("@info a Throw failed; %1 is the Cast device's name, %2 the reason it gave");
} // namespace

ThrowSession::ThrowSession(const Device &device, const ModelRow &row, QObject *parent)
    : QObject(parent)
    , m_device(device)
    , m_row(row)
{
    m_size = row.size;
    m_hz = row.refreshHz;
    // the person's own mode for this device, when set (sparky-stereo-throwrc, [Device][<id>] Mode=1280x720@30)
    const KConfigGroup group = KSharedConfig::openConfig(QStringLiteral("sparky-stereo-throwrc"))->group(QStringLiteral("Device")).group(device.id);
    static const QRegularExpression modeRe(QStringLiteral("^(\\d+)x(\\d+)@(\\d+)$"));
    const auto match = modeRe.match(group.readEntry("Mode", QString()));
    if (match.hasMatch()) {
        m_size = QSize(match.captured(1).toInt(), match.captured(2).toInt());
        m_hz = match.captured(3).toInt();
    }

    connect(&m_screen, &NetworkScreen::created, this, [this](quint64 serial, quint32 node) {
        if (!m_streamer.start(serial, node, m_size, m_hz)) {
            fail(QStringLiteral("@info a Throw failed; %1 is the Cast device's name, %2 why the stream could not start"),
                 QStringLiteral("The Throw to %1 could not start its stream: %2"), {m_device.name, m_streamer.error()},
                 QStringLiteral("The Throw to %1 could not start its stream: %2").arg(m_device.name, m_streamer.error()));
            return;
        }
        m_channel.open(m_device.address.isNull() ? m_device.host : m_device.address.toString(), m_device.port);
    });
    connect(&m_screen, &NetworkScreen::failed, this, [this](const QString &error) {
        fail(QStringLiteral("@info a Throw failed; %1 is the Cast device's name, %2 what KWin answered"),
             QStringLiteral("KWin could not make the network screen for %1: %2"), {m_device.name, error},
             QStringLiteral("KWin could not make the network screen for %1: %2").arg(m_device.name, error));
    });
    connect(&m_screen, &NetworkScreen::closed, this, [this] {
        if (!m_stopping) {
            setState(QStringLiteral("stopped"), QStringLiteral("network-screen-closed"));
            teardown();
        }
    });
    connect(&m_streamer, &Streamer::failed, this, [this](const QString &error) {
        fail(QStringLiteral("@info a Throw failed; %1 is the Cast device's name, %2 what the encoder said"),
             QStringLiteral("The picture for %1 could not be encoded: %2"), {m_device.name, error},
             QStringLiteral("The picture for %1 could not be encoded: %2").arg(m_device.name, error));
    });
    connect(&m_streamer, &Streamer::clientConnected, this, [this] {
        m_fetchTimeout.stop();
    });
    connect(&m_streamer, &Streamer::streaming, this, [this] {
        qCInfo(THROW) << "the first keyframe went to" << m_device.name;
    });
    connect(&m_channel, &CastChannel::ready, this, [this] {
        m_channel.launch(DefaultMediaReceiver);
    });
    connect(&m_channel, &CastChannel::receiverStatus, this, &ThrowSession::onReceiverStatus);
    connect(&m_channel, &CastChannel::launchFailed, this, [this](const QString &reason) {
        fail(CtxDevice, QStringLiteral("%1 refused to start its media player: %2"), {m_device.name, reason},
             QStringLiteral("%1 refused to start its media player: %2").arg(m_device.name, reason));
    });
    connect(&m_channel, &CastChannel::loadFailed, this, [this](const QString &type, const QString &reason) {
        const QString why = reason.isEmpty() ? type : type + QStringLiteral(" (") + reason + QLatin1Char(')');
        fail(CtxDevice, QStringLiteral("%1 refused the stream: %2"), {m_device.name, why},
             QStringLiteral("%1 refused the stream: %2").arg(m_device.name, why));
    });
    connect(&m_channel, &CastChannel::mediaStatus, this, [this](const QJsonObject &payload) {
        onMediaStatus(payload);
    });
    connect(&m_channel, &CastChannel::closed, this, [this](const QString &why) {
        if (m_stopping) {
            return;
        }
        if (why == QLatin1String("heartbeat-lost")) {
            fail(QStringLiteral("@info a Throw ended; %1 is the Cast device's name"), QStringLiteral("%1 stopped answering. The Throw to it has ended."),
                 {m_device.name}, QStringLiteral("%1 stopped answering. The Throw to it has ended.").arg(m_device.name));
        } else if (why.startsWith(QLatin1String("connection-failed"))) {
            const QString reason = why.section(QLatin1Char(':'), 1);
            fail(CtxDevice, QStringLiteral("%1 could not be reached: %2"), {m_device.name, reason},
                 QStringLiteral("%1 could not be reached: %2").arg(m_device.name, reason));
        } else {
            // the person stopped it on the device, or the device closed its player: an ordinary end, said
            Tell::event(QStringLiteral("throwEnded"),
                        i18nc("@info:status a Throw ended on the device's side; %1 is its name", "%1 closed the Throw.", m_device.name));
            setState(QStringLiteral("stopped"), why);
            teardown();
        }
    });
    m_fetchTimeout.setSingleShot(true);
    m_fetchTimeout.setInterval(FetchTimeoutMs);
    connect(&m_fetchTimeout, &QTimer::timeout, this, [this] {
        fail(QStringLiteral("@info a Throw failed; %1 is the Cast device's name, %2 a number of seconds"),
             QStringLiteral("%1 did not fetch the stream within %2 seconds."), {m_device.name, QString::number(FetchTimeoutMs / 1000)},
             QStringLiteral("%1 did not fetch the stream within %2 seconds.").arg(m_device.name).arg(FetchTimeoutMs / 1000));
    });
}

ThrowSession::~ThrowSession()
{
    m_stopping = true;
}

void ThrowSession::start()
{
    if (!m_row.video) {
        fail(QStringLiteral("@info a Throw cannot start; %1 is the Cast device's name"),
             QStringLiteral("%1 is a speaker or a group: it has no screen to throw to."), {m_device.name},
             QStringLiteral("%1 is a speaker or a group: it has no screen to throw to.").arg(m_device.name));
        return;
    }
    if (!m_row.known) {
        Tell::unknownModel(m_device.id, m_device.name, m_device.model);
    }
    setState(QStringLiteral("starting"));
    m_screen.request(m_device.id, m_device.name, m_size, m_hz * 1000);
}

void ThrowSession::stop()
{
    if (m_state == QLatin1String("stopped") || m_state == QLatin1String("failed")) {
        return;
    }
    if (m_channel.isReady() && !m_sessionId.isEmpty()) {
        m_channel.stopApp(m_sessionId);
    }
    Tell::event(QStringLiteral("throwEnded"), i18nc("@info:status a Throw ended; %1 is the Cast device's name", "The Throw to %1 has ended.", m_device.name));
    setState(QStringLiteral("stopped"), QStringLiteral("stopped"));
    teardown();
}

void ThrowSession::fail(const QString &context, const QString &message, const QStringList &args, const QString &english)
{
    if (m_state == QLatin1String("failed") || m_state == QLatin1String("stopped")) {
        return;
    }
    Tell::failure(m_device.id, context, message, args, english);
    setState(QStringLiteral("failed"), english);
    teardown();
}

void ThrowSession::setState(const QString &state, const QString &detail)
{
    m_state = state;
    m_detail = detail;
    qCInfo(THROW) << m_device.name << "->" << state << detail;
    Q_EMIT stateChanged(state, detail);
}

void ThrowSession::teardown()
{
    m_stopping = true;
    m_fetchTimeout.stop();
    m_channel.close();
    m_streamer.stop();
    m_screen.close();
    Q_EMIT finished();
}

void ThrowSession::onReceiverStatus(const QJsonObject &status, int)
{
    const QJsonArray applications = status.value(QStringLiteral("applications")).toArray();
    for (const auto &value : applications) {
        const QJsonObject app = value.toObject();
        if (app.value(QStringLiteral("appId")).toString() != DefaultMediaReceiver) {
            continue;
        }
        m_transportId = app.value(QStringLiteral("transportId")).toString();
        m_sessionId = app.value(QStringLiteral("sessionId")).toString();
        if (!m_loadSent && !m_transportId.isEmpty()) {
            m_loadSent = true;
            const QString url = m_streamer.url(m_channel.localAddress());
            qCInfo(THROW) << "asking" << m_device.name << "to load" << url;
            m_channel.load(m_transportId, url, Streamer::contentType());
            m_fetchTimeout.start();
        }
        return;
    }
    if (m_loadSent && m_state == QLatin1String("throwing")) {
        // our player is no longer running on the device: someone else cast to it, or it was closed there
        Tell::event(QStringLiteral("throwEnded"), i18nc("@info:status a Throw ended on the device's side; %1 is its name", "%1 closed the Throw.", m_device.name));
        setState(QStringLiteral("stopped"), QStringLiteral("player-gone"));
        teardown();
    }
}

void ThrowSession::onMediaStatus(const QJsonObject &payload)
{
    const QJsonArray statuses = payload.value(QStringLiteral("status")).toArray();
    for (const auto &value : statuses) {
        const QJsonObject status = value.toObject();
        const QString player = status.value(QStringLiteral("playerState")).toString();
        if ((player == QLatin1String("PLAYING") || player == QLatin1String("BUFFERING")) && m_state == QLatin1String("starting")) {
            Tell::clear(m_device.id);
            Tell::event(QStringLiteral("throwStarted"), i18nc("@info:status a Throw runs; %1 is the Cast device's name", "Throwing to %1.", m_device.name));
            setState(QStringLiteral("throwing"));
        } else if (player == QLatin1String("IDLE") && status.value(QStringLiteral("idleReason")).toString() == QLatin1String("ERROR")) {
            fail(CtxDevice, QStringLiteral("%1 refused the stream: %2"), {m_device.name, QStringLiteral("ERROR")},
                 QStringLiteral("%1 refused the stream: %2").arg(m_device.name, QStringLiteral("ERROR")));
        }
    }
}

} // namespace Throw
