// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// One Throw to one Cast device: its network screen in KWin (none for a speaker or a group: the sound alone), the sound
// sink "Throw: <device>", the stream, the channel, the Default Media Receiver.
#pragma once

#include "castchannel.h"
#include "codecs.h"
#include "devicetable.h"
#include "discovery.h"
#include "networkscreen.h"
#include "streamer.h"

#include <QElapsedTimer>
#include <QJsonObject>
#include <QObject>
#include <QTimer>

namespace Throw
{

class ThrowSession : public QObject
{
    Q_OBJECT
public:
    ThrowSession(const Device &device, const ModelRow &row, const Plan &plan, QObject *parent = nullptr);
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
    Plan plan() const
    {
        return m_plan;
    }
    // what the device reports and what it fetched (the kit's record each second)
    QJsonObject status() const;
    // the sound sink's PipeWire name
    QString sinkName() const;

Q_SIGNALS:
    void stateChanged(const QString &state, const QString &detail);
    void finished();
    // the device played the stream with this sound (seconds from LOAD to its first PLAYING), or did not start playing with it
    // in time
    void soundPlayed(const QString &sound, double startSeconds);
    void soundNotStarted(const QString &sound);

private:
    void fail(const QString &context, const QString &message, const QStringList &args, const QString &english);
    void setState(const QString &state, const QString &detail = QString());
    void teardown();
    void startStream(quint64 serial, quint32 node);
    void onReceiverStatus(const QJsonObject &status, int requestId);
    void onMediaStatus(const QJsonObject &payload);

    Device m_device;
    ModelRow m_row;
    Plan m_plan;
    NetworkScreen m_screen;
    Streamer m_streamer;
    CastChannel m_channel;
    QTimer m_fetchTimeout;
    QTimer m_poll;
    QTimer m_playTimeout;
    QElapsedTimer m_sinceLoad;
    // wall clock times (milliseconds since the epoch) the status gives: the LOAD sent, the last MEDIA_STATUS, the first PLAYING
    qint64 m_loadAt = -1;
    qint64 m_statusAt = -1;
    qint64 m_firstPlayingAt = -1;
    bool m_played = false;
    QString m_transportId;
    QString m_sessionId;
    bool m_loadSent = false;
    bool m_stopping = false;
    QString m_state = QStringLiteral("starting");
    QString m_detail;
    QJsonObject m_media; // the last MEDIA_STATUS entry
};

} // namespace Throw
