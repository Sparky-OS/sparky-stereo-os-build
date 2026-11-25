// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// One Throw to one Cast device: its network screen in KWin, the stream, the channel, the Default Media Receiver.
#pragma once

#include "castchannel.h"
#include "devicetable.h"
#include "discovery.h"
#include "networkscreen.h"
#include "streamer.h"

#include <QObject>
#include <QTimer>

namespace Throw
{

class ThrowSession : public QObject
{
    Q_OBJECT
public:
    ThrowSession(const Device &device, const ModelRow &row, QObject *parent = nullptr);
    ~ThrowSession() override;

    void start();
    void stop();

    QString state() const
    {
        return m_state;
    }
    QString detail() const
    {
        return m_detail;
    }
    Device device() const
    {
        return m_device;
    }
    QSize size() const
    {
        return m_size;
    }
    int refreshHz() const
    {
        return m_hz;
    }

Q_SIGNALS:
    void stateChanged(const QString &state, const QString &detail);
    void finished();

private:
    void fail(const QString &context, const QString &message, const QStringList &args, const QString &english);
    void setState(const QString &state, const QString &detail = QString());
    void teardown();
    void onReceiverStatus(const QJsonObject &status, int requestId);
    void onMediaStatus(const QJsonObject &payload);

    Device m_device;
    ModelRow m_row;
    QSize m_size;
    int m_hz = 30;
    NetworkScreen m_screen;
    Streamer m_streamer;
    CastChannel m_channel;
    QTimer m_fetchTimeout;
    QString m_transportId;
    QString m_sessionId;
    bool m_loadSent = false;
    bool m_stopping = false;
    QString m_state = QStringLiteral("starting");
    QString m_detail;
};

} // namespace Throw
