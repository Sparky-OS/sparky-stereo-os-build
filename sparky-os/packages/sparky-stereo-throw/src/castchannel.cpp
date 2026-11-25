// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include "castchannel.h"
#include "logging.h"

#include <QSslConfiguration>

namespace Throw
{

namespace
{
const QString Sender = QStringLiteral("sender-0");
const QString Receiver = QStringLiteral("receiver-0");
constexpr int HeartbeatMs = 5000;
constexpr int MissedPongsGone = 3;
} // namespace

CastChannel::CastChannel(QObject *parent)
    : QObject(parent)
{
    // A Cast device never authenticates its sender, and the public senders accept the device's certificate as it is
    // (pychromecast's socket_client.py: verify_mode = CERT_NONE; GNOME Network Displays' accept-certificate handler).
    QSslConfiguration tls = QSslConfiguration::defaultConfiguration();
    tls.setPeerVerifyMode(QSslSocket::VerifyNone);
    m_socket.setSslConfiguration(tls);
    connect(&m_socket, &QSslSocket::encrypted, this, [this] {
        m_ready = true;
        send(Receiver, NsConnection, {{QStringLiteral("type"), QStringLiteral("CONNECT")}});
        m_missedPongs = 0;
        m_heartbeat.start();
        Q_EMIT ready();
    });
    connect(&m_socket, &QSslSocket::readyRead, this, &CastChannel::onReadyRead);
    connect(&m_socket, &QSslSocket::disconnected, this, [this] {
        m_heartbeat.stop();
        const bool wasReady = m_ready;
        m_ready = false;
        if (!m_closing) {
            Q_EMIT closed(wasReady ? QStringLiteral("connection-ended") : QStringLiteral("connection-failed"));
        }
    });
    connect(&m_socket, &QSslSocket::errorOccurred, this, [this](QAbstractSocket::SocketError) {
        qCWarning(THROW) << "channel error:" << m_socket.errorString();
        if (!m_ready && !m_closing) {
            m_closing = true;
            Q_EMIT closed(QStringLiteral("connection-failed:") + m_socket.errorString());
        }
    });
    m_heartbeat.setInterval(HeartbeatMs);
    connect(&m_heartbeat, &QTimer::timeout, this, &CastChannel::beat);
}

CastChannel::~CastChannel()
{
    m_closing = true;
    m_socket.abort();
}

void CastChannel::open(const QString &host, quint16 port)
{
    m_closing = false;
    qCInfo(THROW) << "opening the Cast channel to" << host << port;
    m_socket.connectToHostEncrypted(host, port);
}

void CastChannel::close()
{
    if (m_ready) {
        if (!m_transportConnected.isEmpty()) {
            send(m_transportConnected, NsConnection, {{QStringLiteral("type"), QStringLiteral("CLOSE")}});
        }
        send(Receiver, NsConnection, {{QStringLiteral("type"), QStringLiteral("CLOSE")}});
        m_socket.flush();
    }
    m_closing = true;
    m_heartbeat.stop();
    m_ready = false;
    m_socket.disconnectFromHost();
}

void CastChannel::send(const QString &destination, const QString &nameSpace, QJsonObject payload, int requestId)
{
    if (requestId) {
        payload.insert(QStringLiteral("requestId"), requestId);
    }
    m_socket.write(CastMessage::json(Sender, destination, nameSpace, payload).frame());
}

int CastChannel::getStatus()
{
    const int id = m_nextRequest++;
    send(Receiver, NsReceiver, {{QStringLiteral("type"), QStringLiteral("GET_STATUS")}}, id);
    return id;
}

int CastChannel::launch(const QString &appId)
{
    const int id = m_nextRequest++;
    send(Receiver, NsReceiver, {{QStringLiteral("type"), QStringLiteral("LAUNCH")}, {QStringLiteral("appId"), appId}}, id);
    return id;
}

int CastChannel::stopApp(const QString &sessionId)
{
    const int id = m_nextRequest++;
    send(Receiver, NsReceiver, {{QStringLiteral("type"), QStringLiteral("STOP")}, {QStringLiteral("sessionId"), sessionId}}, id);
    return id;
}

int CastChannel::setVolume(std::optional<double> level, std::optional<bool> muted)
{
    QJsonObject volume;
    if (level) {
        volume.insert(QStringLiteral("level"), qBound(0.0, *level, 1.0));
    }
    if (muted) {
        volume.insert(QStringLiteral("muted"), *muted);
    }
    const int id = m_nextRequest++;
    send(Receiver, NsReceiver, {{QStringLiteral("type"), QStringLiteral("SET_VOLUME")}, {QStringLiteral("volume"), volume}}, id);
    return id;
}

int CastChannel::load(const QString &transportId, const QString &url, const QString &contentType)
{
    if (m_transportConnected != transportId) {
        send(transportId, NsConnection, {{QStringLiteral("type"), QStringLiteral("CONNECT")}});
        m_transportConnected = transportId;
    }
    const QJsonObject media{
        {QStringLiteral("contentId"), url},
        {QStringLiteral("contentType"), contentType},
        {QStringLiteral("streamType"), QStringLiteral("LIVE")},
    };
    const int id = m_nextRequest++;
    send(transportId, NsMedia, {{QStringLiteral("type"), QStringLiteral("LOAD")}, {QStringLiteral("media"), media}, {QStringLiteral("autoplay"), true}}, id);
    return id;
}

void CastChannel::onReadyRead()
{
    m_reader.append(m_socket.readAll());
    while (const auto message = m_reader.next()) {
        onMessage(*message);
    }
    if (!m_reader.error().isEmpty()) {
        qCWarning(THROW) << "channel:" << m_reader.error();
    }
}

void CastChannel::onMessage(const CastMessage &message)
{
    if (message.payloadType != CastMessage::String) {
        qCDebug(THROW) << "binary message on" << message.nameSpace << "ignored";
        return;
    }
    const QJsonObject payload = message.payloadJson();
    const QString type = payload.value(QStringLiteral("type")).toString();
    const int requestId = payload.value(QStringLiteral("requestId")).toInt();
    if (message.nameSpace == NsHeartbeat) {
        if (type == QLatin1String("PING")) {
            send(message.sourceId, NsHeartbeat, {{QStringLiteral("type"), QStringLiteral("PONG")}});
        } else if (type == QLatin1String("PONG")) {
            m_missedPongs = 0;
        }
    } else if (message.nameSpace == NsConnection && type == QLatin1String("CLOSE")) {
        Q_EMIT closed(message.sourceId == Receiver ? QStringLiteral("device-closed") : QStringLiteral("application-closed"));
    } else if (message.nameSpace == NsReceiver) {
        if (type == QLatin1String("RECEIVER_STATUS")) {
            Q_EMIT receiverStatus(payload.value(QStringLiteral("status")).toObject(), requestId);
        } else if (type == QLatin1String("LAUNCH_ERROR")) {
            Q_EMIT launchFailed(payload.value(QStringLiteral("reason")).toString(), requestId);
        } else if (type == QLatin1String("INVALID_REQUEST")) {
            Q_EMIT requestRefused(type, payload.value(QStringLiteral("reason")).toString(), requestId);
        }
    } else if (message.nameSpace == NsMedia) {
        if (type == QLatin1String("MEDIA_STATUS")) {
            Q_EMIT mediaStatus(payload, requestId);
        } else if (type == QLatin1String("LOAD_FAILED") || type == QLatin1String("LOAD_CANCELLED") || type == QLatin1String("INVALID_REQUEST")) {
            Q_EMIT loadFailed(type, payload.value(QStringLiteral("reason")).toString(), requestId);
        }
    }
}

void CastChannel::beat()
{
    if (++m_missedPongs > MissedPongsGone) {
        qCWarning(THROW) << "the device stopped answering the heartbeat";
        m_heartbeat.stop();
        m_closing = true;
        m_ready = false;
        m_socket.abort();
        Q_EMIT closed(QStringLiteral("heartbeat-lost"));
        return;
    }
    send(Receiver, NsHeartbeat, {{QStringLiteral("type"), QStringLiteral("PING")}});
}

} // namespace Throw
