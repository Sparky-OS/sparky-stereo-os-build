// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// The network screen's picture and the Throw sink's sound as the device fetches them: KPipeWire's encoder on the
// screen's PipeWire node, the sink's samples encoded by libavcodec, both in one container (the codec's: Matroska, MP4,
// WebM, or Ogg for the sound alone) on a small HTTP server. The server listens on the address of this computer that faces
// the device and answers that device only; the picture and sound travel unencrypted, as the device's own player fetches
// them.
#pragma once

#include "audiosink.h"
#include "codecs.h"

#include <QElapsedTimer>
#include <QHostAddress>
#include <QObject>
#include <QPointer>
#include <QSize>
#include <QTcpServer>
#include <QTcpSocket>
#include <deque>
#include <memory>
#include <vector>

#include <KPipeWire/PipeWireEncodedStream>

struct AVFormatContext;
struct AVIOContext;
struct AVCodecContext;
struct AVAudioFifo;
struct AVFrame;

namespace Throw
{

// one encoded packet of either track, at its time in milliseconds on the Throw's clock
struct Kept {
    bool video = true;
    QByteArray data;
    bool key = false;
    qint64 ms = 0;
    qint64 durationMs = 0;
};

// one stream to one reader: the container's header at the first video keyframe (or the first sound with no picture)
class Muxer
{
public:
    struct Tracks {
        QString format;
        bool video = true;
        QString codec; // h264, hevc, vp9, vp8
        QSize size;
        int fps = 30;
        bool audio = true;
        QString audioCodec; // flac, opus
        int rate = 48000;
        int channels = 2;
        QByteArray audioExtradata;
        int audioFrameSize = 0;
        int audioInitialPadding = 0;
    };
    Muxer(QTcpSocket *socket, const Tracks &tracks);
    ~Muxer();
    // false, with error(), when the stream cannot go on; packets before the start are skipped
    bool write(const Kept &packet);
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
    bool begin(const QByteArray &keyFrame);

    QPointer<QTcpSocket> m_socket;
    Tracks m_tracks;
    AVFormatContext *m_context = nullptr;
    AVIOContext *m_io = nullptr;
    int m_videoIndex = -1;
    int m_audioIndex = -1;
    qint64 m_firstMs = -1;
    qint64 m_lastVideo = -1;
    qint64 m_lastAudio = -1;
    qint64 m_bytes = 0;
    QString m_error;
};

class Streamer : public QObject
{
    Q_OBJECT
public:
    explicit Streamer(QObject *parent = nullptr);
    ~Streamer() override;

    // the picture (when plan.video) on the screen's node, the sound from a sink of that name, and the HTTP server on the
    // address facing the device; false with error() when any cannot start
    bool start(const Plan &plan, quint64 objectSerial, quint32 node, const QHostAddress &device, const QString &sinkName,
               const QString &sinkDescription);
    void stop();
    // the URL the device is asked to load
    QString url() const;
    QString error() const
    {
        return m_error;
    }
    QString contentType() const
    {
        return m_plan.info.mime;
    }
    qint64 bytesServed() const
    {
        return m_writer ? m_writer->bytes() : m_bytesBefore;
    }
    QHostAddress listenAddress() const
    {
        return m_server.serverAddress();
    }

Q_SIGNALS:
    void clientConnected(const QString &peer);
    void streaming(); // the first keyframe (or the first sound) went to the device
    void failed(const QString &error);

private:
    void onConnection();
    void onVideoPacket(const PipeWireEncodedStream::Packet &packet);
    void onSamples();
    bool openAudioEncoder();
    void encodeAudio();
    void keep(const Kept &packet);
    bool writePacket(const Kept &packet);
    void serve(QTcpSocket *socket);

    Plan m_plan;
    std::unique_ptr<PipeWireEncodedStream> m_encoder;
    AudioSink m_sink;
    QTcpServer m_server;
    QHostAddress m_device;
    QString m_token;
    QTcpSocket *m_client = nullptr;
    std::unique_ptr<Muxer> m_writer;
    QElapsedTimer m_clock;
    bool m_announced = false;
    bool m_gotVideo = false;
    qint64 m_bytesBefore = 0;
    QString m_error;

    // the current group of pictures (video since the last keyframe) and the last seconds of sound: a device that
    // connects gets them at once, the group moved to now, then the live packets. KWin sends a frame only when the screen
    // changes and KPipeWire repeats the last one once, so on a still screen no other keyframe comes (loopback row T5).
    std::vector<Kept> m_group;
    qint64 m_groupBytes = 0;
    std::deque<Kept> m_recentSound;

    // the sound's encoder
    AVCodecContext *m_audio = nullptr;
    AVAudioFifo *m_fifo = nullptr;
    AVFrame *m_frame = nullptr;
    qint64 m_samplesOut = 0;
    qint64 m_audioStartMs = -1;
};

} // namespace Throw
