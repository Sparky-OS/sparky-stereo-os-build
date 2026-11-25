// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// The network screen's picture as the device fetches it: KPipeWire's encoder on the screen's PipeWire node, Matroska
// live (libavformat, `live` on: no cues, no size), served over HTTP on a random path. Matroska live is the first
// container (row 81's review); the stream carries video only in this milestone, the audio track's place is kept.
#pragma once

#include <QElapsedTimer>
#include <QHostAddress>
#include <QObject>
#include <QPointer>
#include <QSize>
#include <QTcpServer>
#include <QTcpSocket>
#include <memory>
#include <vector>

#include <KPipeWire/PipeWireEncodedStream>

struct AVFormatContext;
struct AVIOContext;
struct AVStream;

namespace Throw
{

// one Matroska stream to one client, from its first keyframe on
class MatroskaWriter
{
public:
    explicit MatroskaWriter(QTcpSocket *socket);
    ~MatroskaWriter();
    // false, with error(), when the header cannot be written; packets before the first keyframe are skipped
    bool write(const PipeWireEncodedStream::Packet &packet, qint64 ms, const QSize &size, int fps);
    QString error() const
    {
        return m_error;
    }
    bool started() const
    {
        return m_context != nullptr;
    }
    qint64 bytes() const
    {
        return m_bytes;
    }

    static int writeCallback(void *opaque, const uint8_t *buf, int size);

private:
    bool begin(const QByteArray &keyFrame, const QSize &size, int fps);

    QPointer<QTcpSocket> m_socket;
    AVFormatContext *m_context = nullptr;
    AVIOContext *m_io = nullptr;
    AVStream *m_stream = nullptr;
    qint64 m_firstMs = -1;
    qint64 m_bytes = 0;
    QString m_error;
};

class Streamer : public QObject
{
    Q_OBJECT
public:
    explicit Streamer(QObject *parent = nullptr);
    ~Streamer() override;

    // starts the encoder on the network screen's node and the HTTP server; false with error() when either cannot start
    bool start(quint64 objectSerial, quint32 node, const QSize &size, int fps);
    void stop();
    // the URL the device is asked to load, on the address it reached us from
    QString url(const QHostAddress &local) const;
    QString error() const
    {
        return m_error;
    }
    static QString contentType()
    {
        return QStringLiteral("video/x-matroska");
    }

Q_SIGNALS:
    void clientConnected(const QString &peer);
    void streaming(); // the first keyframe went to the device
    void failed(const QString &error);

private:
    void onConnection();
    void onPacket(const PipeWireEncodedStream::Packet &packet);
    // to the device that reads now; false when it stopped reading
    bool writePacket(const PipeWireEncodedStream::Packet &packet, qint64 ms);

    std::unique_ptr<PipeWireEncodedStream> m_encoder;
    QTcpServer m_server;
    QString m_token;
    QTcpSocket *m_client = nullptr;
    std::unique_ptr<MatroskaWriter> m_writer;
    // the current group of pictures: the last keyframe and every packet after it, with its time. A device that connects
    // gets it at once and then the live packets. KWin sends a frame only when the screen changes (and one when the
    // stream starts), and KPipeWire repeats the last one once to flush its encoder, so on a still screen the keyframe
    // is encoded before the device connects and no other comes: a device waiting for the next keyframe would get
    // nothing (loopback row T5, found 2026-11-25).
    struct Kept {
        PipeWireEncodedStream::Packet packet;
        qint64 ms;
    };
    std::vector<Kept> m_group;
    qint64 m_groupBytes = 0;
    QElapsedTimer m_clock;
    QSize m_size;
    int m_fps = 30;
    bool m_announced = false;
    QString m_error;
};

} // namespace Throw
