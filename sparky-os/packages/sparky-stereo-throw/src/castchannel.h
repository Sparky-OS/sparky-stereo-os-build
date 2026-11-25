// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// One CASTv2 channel to one device: TLS on its port (8009), the connection, heartbeat, receiver and media namespaces.
#pragma once

#include "castmessage.h"

#include <QHostAddress>
#include <QJsonObject>
#include <QObject>
#include <QSslSocket>
#include <QTimer>

namespace Throw
{

class CastChannel : public QObject
{
    Q_OBJECT
public:
    explicit CastChannel(QObject *parent = nullptr);
    ~CastChannel() override;

    void open(const QString &host, quint16 port);
    void close();
    bool isReady() const
    {
        return m_ready;
    }
    QHostAddress localAddress() const
    {
        return m_socket.localAddress();
    }

    // receiver-0
    int getStatus();
    int launch(const QString &appId);
    int stopApp(const QString &sessionId);
    int setVolume(std::optional<double> level, std::optional<bool> muted);
    // the media namespace of a running application
    int load(const QString &transportId, const QString &url, const QString &contentType);
    // the player's state, as the device reports it (MEDIA_STATUS)
    int getMediaStatus(const QString &transportId);

Q_SIGNALS:
    void ready();
    void receiverStatus(const QJsonObject &status, int requestId);
    void launchFailed(const QString &reason, int requestId);
    void mediaStatus(const QJsonObject &status, int requestId);
    void loadFailed(const QString &type, const QString &reason, int requestId);
    void requestRefused(const QString &type, const QString &reason, int requestId);
    // the device closed the channel or its application, or stopped answering the heartbeat
    void closed(const QString &why);

private:
    void send(const QString &destination, const QString &nameSpace, QJsonObject payload, int requestId = 0);
    void onReadyRead();
    void onMessage(const CastMessage &message);
    void beat();

    QSslSocket m_socket;
    FrameReader m_reader;
    QTimer m_heartbeat;
    int m_missedPongs = 0;
    int m_nextRequest = 1;
    bool m_ready = false;
    bool m_closing = false;
    QString m_transportConnected;
};

} // namespace Throw
