// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include "streamer.h"
#include "logging.h"

#include <QRandomGenerator>

extern "C" {
#include <libavformat/avformat.h>
#include <libavutil/mem.h>
#include <libavutil/opt.h>
}

namespace Throw
{

namespace
{
constexpr int IoBufferSize = 64 * 1024;

// the SPS and PPS of an Annex B keyframe, with their start codes: the muxer turns them into the track's avcC
QByteArray parameterSets(const QByteArray &annexB)
{
    QByteArray out;
    const auto *data = reinterpret_cast<const quint8 *>(annexB.constData());
    const qsizetype size = annexB.size();
    qsizetype i = 0;
    auto startCode = [&](qsizetype at) -> int {
        if (at + 3 <= size && data[at] == 0 && data[at + 1] == 0 && data[at + 2] == 1) {
            return 3;
        }
        if (at + 4 <= size && data[at] == 0 && data[at + 1] == 0 && data[at + 2] == 0 && data[at + 3] == 1) {
            return 4;
        }
        return 0;
    };
    while (i < size) {
        const int sc = startCode(i);
        if (!sc) {
            ++i;
            continue;
        }
        const qsizetype nalStart = i + sc;
        qsizetype next = nalStart;
        while (next < size && !startCode(next)) {
            ++next;
        }
        if (nalStart < size) {
            const int type = data[nalStart] & 0x1f;
            if (type == 7 || type == 8) {
                out.append("\x00\x00\x00\x01", 4);
                out.append(annexB.mid(nalStart, next - nalStart));
            }
        }
        i = next;
    }
    return out;
}
} // namespace

MatroskaWriter::MatroskaWriter(QTcpSocket *socket)
    : m_socket(socket)
{
}

MatroskaWriter::~MatroskaWriter()
{
    if (m_context) {
        av_write_trailer(m_context);
        avformat_free_context(m_context);
    }
    if (m_io) {
        av_freep(&m_io->buffer);
        avio_context_free(&m_io);
    }
}

int MatroskaWriter::writeCallback(void *opaque, const uint8_t *buf, int size)
{
    auto writer = static_cast<MatroskaWriter *>(opaque);
    if (!writer->m_socket || writer->m_socket->state() != QAbstractSocket::ConnectedState) {
        return AVERROR(EPIPE);
    }
    writer->m_socket->write(reinterpret_cast<const char *>(buf), size);
    writer->m_bytes += size;
    return size;
}

bool MatroskaWriter::begin(const QByteArray &keyFrame, const QSize &size, int fps)
{
    const QByteArray sets = parameterSets(keyFrame);
    if (sets.isEmpty()) {
        m_error = QStringLiteral("the encoder's keyframe carries no SPS and PPS");
        return false;
    }
    if (avformat_alloc_output_context2(&m_context, nullptr, "matroska", nullptr) < 0 || !m_context) {
        m_error = QStringLiteral("libavformat has no Matroska muxer");
        return false;
    }
    auto buffer = static_cast<unsigned char *>(av_malloc(IoBufferSize));
    m_io = avio_alloc_context(buffer, IoBufferSize, 1, this, nullptr, &MatroskaWriter::writeCallback, nullptr);
    m_context->pb = m_io;
    m_context->flags |= AVFMT_FLAG_CUSTOM_IO;
    m_stream = avformat_new_stream(m_context, nullptr);
    m_stream->time_base = AVRational{1, 1000};
    AVCodecParameters *par = m_stream->codecpar;
    par->codec_type = AVMEDIA_TYPE_VIDEO;
    par->codec_id = AV_CODEC_ID_H264;
    par->width = size.width();
    par->height = size.height();
    par->extradata = static_cast<uint8_t *>(av_mallocz(sets.size() + AV_INPUT_BUFFER_PADDING_SIZE));
    memcpy(par->extradata, sets.constData(), sets.size());
    par->extradata_size = int(sets.size());
    m_stream->avg_frame_rate = AVRational{fps, 1};
    AVDictionary *options = nullptr;
    // a live stream: no cues and no sizes to seek back to, clusters closed often so the device can start soon
    av_dict_set(&options, "live", "1", 0);
    av_dict_set(&options, "cluster_time_limit", "1000", 0);
    av_dict_set(&options, "write_crc32", "0", 0);
    const int ret = avformat_write_header(m_context, &options);
    av_dict_free(&options);
    if (ret < 0) {
        char text[AV_ERROR_MAX_STRING_SIZE] = {};
        av_strerror(ret, text, sizeof text);
        m_error = QStringLiteral("the Matroska header could not be written: %1").arg(QString::fromUtf8(text));
        avformat_free_context(m_context);
        m_context = nullptr;
        return false;
    }
    avio_flush(m_io);
    return true;
}

bool MatroskaWriter::write(const PipeWireEncodedStream::Packet &packet, qint64 ms, const QSize &size, int fps)
{
    const QByteArray data = packet.data();
    if (!m_context) {
        if (!packet.isKeyFrame()) {
            return true;
        }
        if (!begin(data, size, fps)) {
            return false;
        }
        m_firstMs = ms;
    }
    AVPacket *pkt = av_packet_alloc();
    if (av_new_packet(pkt, int(data.size())) < 0) {
        av_packet_free(&pkt);
        m_error = QStringLiteral("out of memory for a packet");
        return false;
    }
    memcpy(pkt->data, data.constData(), data.size());
    pkt->stream_index = 0;
    pkt->pts = pkt->dts = ms - m_firstMs;
    pkt->duration = 1000 / qMax(1, fps);
    if (packet.isKeyFrame()) {
        pkt->flags |= AV_PKT_FLAG_KEY;
    }
    const int ret = av_write_frame(m_context, pkt);
    av_packet_free(&pkt);
    if (ret < 0) {
        m_error = QStringLiteral("the device stopped reading the stream");
        return false;
    }
    avio_flush(m_io);
    return true;
}

Streamer::Streamer(QObject *parent)
    : QObject(parent)
{
    connect(&m_server, &QTcpServer::newConnection, this, &Streamer::onConnection);
}

Streamer::~Streamer()
{
    stop();
}

bool Streamer::start(quint64 objectSerial, quint32 node, const QSize &size, int fps)
{
    m_size = size;
    m_fps = fps;
    const quint64 a = QRandomGenerator::system()->generate64();
    const quint64 b = QRandomGenerator::system()->generate64();
    m_token = QString::number(a, 36) + QString::number(b, 36);
    if (!m_server.listen(QHostAddress::Any, 0)) {
        m_error = QStringLiteral("the stream's HTTP server cannot listen: %1").arg(m_server.errorString());
        return false;
    }
    m_encoder = std::make_unique<PipeWireEncodedStream>();
    // KPipeWire 6.7.4's recorder starts only with a node id ("Cannot start recording on a stream without a node ID"),
    // even when the object serial, which the protocol says to prefer, is given too: both are set
    m_encoder->setNodeId(node);
    if (objectSerial) {
        m_encoder->setObjectSerial(objectSerial);
    }
    m_encoder->setEncoder(PipeWireBaseEncodedStream::H264Main);
    m_encoder->setEncodingPreference(PipeWireBaseEncodedStream::Speed);
    m_encoder->setMaxFramerate(quint32(fps), 1);
    connect(m_encoder.get(), &PipeWireEncodedStream::newPacket, this, &Streamer::onPacket);
    connect(m_encoder.get(), &PipeWireBaseEncodedStream::errorFound, this, [this](const QString &error) {
        qCWarning(THROW) << "encoder:" << error;
        m_error = error;
        Q_EMIT failed(error);
    });
    m_clock.start();
    m_encoder->start();
    qCInfo(THROW) << "encoding H.264 at" << size << fps << "fps, serving on port" << m_server.serverPort();
    return true;
}

void Streamer::stop()
{
    if (m_encoder) {
        m_encoder->stop();
        m_encoder.reset();
    }
    m_writer.reset();
    m_group.clear();
    m_groupBytes = 0;
    if (m_client) {
        m_client->disconnectFromHost();
        m_client = nullptr;
    }
    m_server.close();
}

QString Streamer::url(const QHostAddress &local) const
{
    QString host = local.toString();
    if (local.protocol() == QAbstractSocket::IPv6Protocol) {
        host = QLatin1Char('[') + host + QLatin1Char(']');
    }
    return QStringLiteral("http://%1:%2/%3.mkv").arg(host).arg(m_server.serverPort()).arg(m_token);
}

void Streamer::onConnection()
{
    while (QTcpSocket *socket = m_server.nextPendingConnection()) {
        connect(socket, &QTcpSocket::readyRead, this, [this, socket] {
            if (!socket->canReadLine() && socket->bytesAvailable() < 4096) {
                return;
            }
            const QByteArray request = socket->readAll();
            const QByteArray line = request.left(request.indexOf('\n')).trimmed();
            const auto parts = line.split(' ');
            const QByteArray wanted = "/" + m_token.toUtf8() + ".mkv";
            if (parts.size() < 2 || (parts[0] != "GET" && parts[0] != "HEAD") || parts[1] != wanted) {
                socket->write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                socket->disconnectFromHost();
                return;
            }
            socket->write("HTTP/1.1 200 OK\r\nContent-Type: video/x-matroska\r\nCache-Control: no-cache\r\nConnection: close\r\n"
                          "Access-Control-Allow-Origin: *\r\n\r\n");
            if (parts[0] == "HEAD") {
                socket->disconnectFromHost();
                return;
            }
            // one reader at a time: a device that fetches again replaces its earlier connection
            if (m_client && m_client != socket) {
                m_client->disconnectFromHost();
            }
            m_client = socket;
            m_writer = std::make_unique<MatroskaWriter>(socket);
            m_announced = false;
            qCInfo(THROW) << "the device fetches the stream from" << socket->peerAddress() << "; the current group of pictures:"
                          << m_group.size() << "packets";
            Q_EMIT clientConnected(socket->peerAddress().toString());
            // the current group of pictures first, so the device has a picture at once even on a still screen; with no
            // group yet the writer waits for the encoder's first keyframe
            const auto group = m_group;
            for (const Kept &kept : group) {
                if (!writePacket(kept.packet, kept.ms)) {
                    return;
                }
            }
        });
        connect(socket, &QTcpSocket::disconnected, this, [this, socket] {
            if (m_client == socket) {
                qCInfo(THROW) << "the device closed the stream after" << (m_writer ? m_writer->bytes() : 0) << "bytes";
                m_writer.reset();
                m_client = nullptr;
            }
            socket->deleteLater();
        });
    }
}

void Streamer::onPacket(const PipeWireEncodedStream::Packet &packet)
{
    const qint64 ms = m_clock.elapsed();
    // a group grows until the next keyframe; one that grows past this size is let go and a keyframe asked for, so a
    // device connecting meanwhile waits for that keyframe instead of receiving a long, stale group
    constexpr qint64 GroupLimit = 32 * 1024 * 1024;
    if (packet.isKeyFrame()) {
        m_group.clear();
        m_groupBytes = 0;
    }
    if (packet.isKeyFrame() || !m_group.empty()) {
        m_group.push_back(Kept{packet, ms});
        m_groupBytes += packet.data().size();
        if (m_groupBytes > GroupLimit) {
            m_group.clear();
            m_groupBytes = 0;
            if (m_encoder) {
                m_encoder->requestKeyFrame();
            }
        }
    }
    writePacket(packet, ms);
}

bool Streamer::writePacket(const PipeWireEncodedStream::Packet &packet, qint64 ms)
{
    if (!m_writer) {
        return false;
    }
    if (!m_writer->write(packet, ms, m_size, m_fps)) {
        qCWarning(THROW) << "stream:" << m_writer->error();
        m_writer.reset();
        if (m_client) {
            m_client->disconnectFromHost();
            m_client = nullptr;
        }
        return false;
    }
    if (m_writer->started() && !m_announced) {
        m_announced = true;
        Q_EMIT streaming();
    }
    return true;
}

} // namespace Throw
