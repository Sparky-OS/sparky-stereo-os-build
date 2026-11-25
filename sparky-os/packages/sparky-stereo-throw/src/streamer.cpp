// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include "streamer.h"
#include "logging.h"

#include <QHash>
#include <QRandomGenerator>
#include <QTimer>
#include <QUdpSocket>

#include <algorithm>
#include <cmath>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/audio_fifo.h>
#include <libavutil/channel_layout.h>
#include <libavutil/mem.h>
#include <libavutil/opt.h>
}

namespace Throw
{

namespace
{
constexpr int IoBufferSize = 64 * 1024;
constexpr int RequestTimeoutMs = 5000; // a connection that sends no request line within this is closed
constexpr qint64 GroupLimit = 32 * 1024 * 1024;
constexpr qint64 RecentSoundMs = 3000;
constexpr int PictureTimeoutMs = 30000;

// the parameter sets of an Annex B keyframe, with their start codes (H.264 SPS and PPS; HEVC VPS, SPS and PPS): the
// muxer turns them into the track's avcC or hvcC
QByteArray parameterSets(const QByteArray &annexB, bool hevc)
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
            const int type = hevc ? (data[nalStart] >> 1) & 0x3f : data[nalStart] & 0x1f;
            if ((!hevc && (type == 7 || type == 8)) || (hevc && type >= 32 && type <= 34)) {
                out.append("\x00\x00\x00\x01", 4);
                out.append(annexB.mid(nalStart, next - nalStart));
            }
        }
        i = next;
    }
    return out;
}

AVCodecID videoCodecId(const QString &codec)
{
    if (codec == QLatin1String("hevc")) {
        return AV_CODEC_ID_HEVC;
    }
    if (codec == QLatin1String("vp9")) {
        return AV_CODEC_ID_VP9;
    }
    if (codec == QLatin1String("vp8")) {
        return AV_CODEC_ID_VP8;
    }
    return AV_CODEC_ID_H264;
}

AVCodecID soundCodecId(const QString &sound)
{
    static const QHash<QString, AVCodecID> ids = {
        {QStringLiteral("pcm24"), AV_CODEC_ID_PCM_S24LE}, {QStringLiteral("pcm16"), AV_CODEC_ID_PCM_S16LE},
        {QStringLiteral("flac"), AV_CODEC_ID_FLAC},       {QStringLiteral("opus"), AV_CODEC_ID_OPUS},
        {QStringLiteral("aac"), AV_CODEC_ID_AAC},         {QStringLiteral("vorbis"), AV_CODEC_ID_VORBIS},
        {QStringLiteral("mp3"), AV_CODEC_ID_MP3},         {QStringLiteral("ac3-5.1"), AV_CODEC_ID_AC3},
        {QStringLiteral("eac3-5.1"), AV_CODEC_ID_EAC3},
    };
    return ids.value(sound, AV_CODEC_ID_FLAC);
}

QString averror(int code)
{
    char text[AV_ERROR_MAX_STRING_SIZE] = {};
    av_strerror(code, text, sizeof text);
    return QString::fromUtf8(text);
}
} // namespace

Muxer::Muxer(QTcpSocket *socket, const Tracks &tracks)
    : m_socket(socket)
    , m_tracks(tracks)
{
}

Muxer::~Muxer()
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

int Muxer::writeCallback(void *opaque, const uint8_t *buf, int size)
{
    auto writer = static_cast<Muxer *>(opaque);
    if (!writer->m_socket || writer->m_socket->state() != QAbstractSocket::ConnectedState) {
        return AVERROR(EPIPE);
    }
    writer->m_socket->write(reinterpret_cast<const char *>(buf), size);
    writer->m_bytes += size;
    return size;
}

bool Muxer::begin(const QByteArray &keyFrame)
{
    if (avformat_alloc_output_context2(&m_context, nullptr, m_tracks.format.toUtf8().constData(), nullptr) < 0 || !m_context) {
        m_error = QStringLiteral("libavformat has no %1 muxer").arg(m_tracks.format);
        m_context = nullptr;
        return false;
    }
    auto buffer = static_cast<unsigned char *>(av_malloc(IoBufferSize));
    m_io = avio_alloc_context(buffer, IoBufferSize, 1, this, nullptr, &Muxer::writeCallback, nullptr);
    m_context->pb = m_io;
    m_context->flags |= AVFMT_FLAG_CUSTOM_IO;
    if (m_tracks.format == QLatin1String("mp4")) {
        // FLAC in MP4 (its 'fLaC' sample entry) is still marked experimental in libavformat
        m_context->strict_std_compliance = FF_COMPLIANCE_EXPERIMENTAL;
    }
    if (m_tracks.video) {
        AVStream *st = avformat_new_stream(m_context, nullptr);
        st->time_base = AVRational{1, 1000};
        AVCodecParameters *par = st->codecpar;
        par->codec_type = AVMEDIA_TYPE_VIDEO;
        par->codec_id = videoCodecId(m_tracks.codec);
        par->width = m_tracks.size.width();
        par->height = m_tracks.size.height();
        if (par->codec_id == AV_CODEC_ID_H264 || par->codec_id == AV_CODEC_ID_HEVC) {
            const QByteArray sets = parameterSets(keyFrame, par->codec_id == AV_CODEC_ID_HEVC);
            if (sets.isEmpty()) {
                m_error = QStringLiteral("the encoder's keyframe carries no parameter sets");
                return false;
            }
            par->extradata = static_cast<uint8_t *>(av_mallocz(sets.size() + AV_INPUT_BUFFER_PADDING_SIZE));
            memcpy(par->extradata, sets.constData(), sets.size());
            par->extradata_size = int(sets.size());
        }
        st->avg_frame_rate = AVRational{m_tracks.fps, 1};
        m_videoIndex = st->index;
    }
    if (m_tracks.audio) {
        AVStream *st = avformat_new_stream(m_context, nullptr);
        st->time_base = AVRational{1, m_tracks.rate};
        AVCodecParameters *par = st->codecpar;
        par->codec_type = AVMEDIA_TYPE_AUDIO;
        par->codec_id = soundCodecId(m_tracks.audioCodec);
        par->sample_rate = m_tracks.rate;
        av_channel_layout_default(&par->ch_layout, m_tracks.channels);
        par->frame_size = m_tracks.audioFrameSize;
        par->initial_padding = m_tracks.audioInitialPadding;
        if (par->codec_id == AV_CODEC_ID_FLAC) {
            par->bits_per_raw_sample = 24;
        }
        if (par->codec_id == AV_CODEC_ID_PCM_S24LE || par->codec_id == AV_CODEC_ID_PCM_S16LE) {
            // Matroska's A_PCM/INT/LIT says its depth in BitDepth
            par->bits_per_coded_sample = av_get_bits_per_sample(par->codec_id);
            par->block_align = par->bits_per_coded_sample / 8 * m_tracks.channels;
        }
        if (!m_tracks.audioExtradata.isEmpty()) {
            par->extradata = static_cast<uint8_t *>(av_mallocz(m_tracks.audioExtradata.size() + AV_INPUT_BUFFER_PADDING_SIZE));
            memcpy(par->extradata, m_tracks.audioExtradata.constData(), m_tracks.audioExtradata.size());
            par->extradata_size = int(m_tracks.audioExtradata.size());
        }
        m_audioIndex = st->index;
    }
    AVDictionary *options = nullptr;
    if (m_tracks.format == QLatin1String("matroska") || m_tracks.format == QLatin1String("webm")) {
        // a live stream: no cues and no sizes to seek back to, clusters closed often so the device can start soon
        av_dict_set(&options, "live", "1", 0);
        av_dict_set(&options, "cluster_time_limit", "1000", 0);
        av_dict_set(&options, "write_crc32", "0", 0);
    } else if (m_tracks.format == QLatin1String("mp4")) {
        // fragmented MP4 written as it goes: an empty moov, one fragment at each keyframe and at least every half second
        av_dict_set(&options, "movflags", "frag_keyframe+empty_moov+default_base_moof", 0);
        av_dict_set(&options, "frag_duration", "500000", 0);
    }
    const int ret = avformat_write_header(m_context, &options);
    av_dict_free(&options);
    if (ret < 0) {
        m_error = QStringLiteral("the %1 header could not be written: %2").arg(m_tracks.format, averror(ret));
        avformat_free_context(m_context);
        m_context = nullptr;
        return false;
    }
    avio_flush(m_io);
    return true;
}

bool Muxer::write(const Kept &packet)
{
    if (!m_context) {
        if (m_tracks.video && (!packet.video || !packet.key)) {
            return true; // the stream starts at a keyframe
        }
        if (!begin(packet.video ? packet.data : QByteArray())) {
            return false;
        }
        m_firstMs = packet.ms;
    }
    if (packet.ms < m_firstMs) {
        return true; // sound from before the picture's start
    }
    const int index = packet.video ? m_videoIndex : m_audioIndex;
    if (index < 0) {
        return true;
    }
    qint64 &last = packet.video ? m_lastVideo : m_lastAudio;
    qint64 ms = packet.ms - m_firstMs;
    if (ms <= last) {
        ms = last + 1; // each track's times only go forward
    }
    last = ms;
    AVStream *st = m_context->streams[index];
    AVPacket *pkt = av_packet_alloc();
    if (av_new_packet(pkt, int(packet.data.size())) < 0) {
        av_packet_free(&pkt);
        m_error = QStringLiteral("out of memory for a packet");
        return false;
    }
    memcpy(pkt->data, packet.data.constData(), packet.data.size());
    pkt->stream_index = index;
    pkt->pts = pkt->dts = av_rescale_q(ms, AVRational{1, 1000}, st->time_base);
    pkt->duration = av_rescale_q(qMax<qint64>(1, packet.durationMs), AVRational{1, 1000}, st->time_base);
    if (packet.key || !packet.video) {
        pkt->flags |= AV_PKT_FLAG_KEY;
    }
    const int ret = av_write_frame(m_context, pkt);
    av_packet_free(&pkt);
    if (ret < 0) {
        m_error = QStringLiteral("the device stopped reading the stream (%1)").arg(averror(ret));
        return false;
    }
    avio_flush(m_io);
    return true;
}

Streamer::Streamer(QObject *parent)
    : QObject(parent)
{
    connect(&m_server, &QTcpServer::newConnection, this, &Streamer::onConnection);
    connect(&m_sink, &AudioSink::samplesReady, this, &Streamer::onSamples);
}

Streamer::~Streamer()
{
    stop();
}

bool Streamer::start(const Plan &plan, quint64 objectSerial, quint32 node, const QHostAddress &device, const QString &sinkName,
                     const QString &sinkDescription)
{
    m_plan = plan;
    m_device = device;
    const quint64 a = QRandomGenerator::system()->generate64();
    const quint64 b = QRandomGenerator::system()->generate64();
    m_token = QString::number(a, 36) + QString::number(b, 36);
    // the address of this computer that faces the device: a UDP socket "connected" to it sends nothing and names it
    QUdpSocket route;
    route.connectToHost(device, 9);
    const QHostAddress local = route.localAddress();
    route.abort();
    if (local.isNull()) {
        m_error = QStringLiteral("no address of this computer reaches %1").arg(device.toString());
        return false;
    }
    if (!m_server.listen(local, 0)) {
        m_error = QStringLiteral("the stream's HTTP server cannot listen on %1: %2").arg(local.toString(), m_server.errorString());
        return false;
    }
    m_clock.start();
    if (!m_sink.start(sinkName, sinkDescription, plan.audioRate, plan.audioChannels)) {
        m_error = QStringLiteral("the sound sink could not be made: %1").arg(m_sink.error());
        return false;
    }
    if (!openAudioEncoder()) {
        return false;
    }
    if (plan.video) {
        m_encoder = std::make_unique<PipeWireEncodedStream>();
        // KPipeWire 6.7.4's recorder starts only with a node id ("Cannot start recording on a stream without a node ID"),
        // even when the object serial, which the protocol says to prefer, is given too: both are set
        m_encoder->setNodeId(node);
        if (objectSerial) {
            m_encoder->setObjectSerial(objectSerial);
        }
        m_encoder->setEncoder(PipeWireBaseEncodedStream::Encoder(plan.info.encoder));
        // KPipeWire 6.7.4 gives every encoder, for the Speed preference, x264's options preset=ultrafast and
        // tune=zerolatency; libvpx and libvpx-vp9 refuse that tune ("Error setting option tune"), so no encoder is made
        // (upstream has since moved those options out of the shared ones). VP8 and VP9 get no preference: no tune, and
        // KPipeWire's VP8 and VP9 encoders set their own realtime deadline.
        const bool vpx = plan.info.codec == QLatin1String("vp8") || plan.info.codec == QLatin1String("vp9");
        m_encoder->setEncodingPreference(vpx ? PipeWireBaseEncodedStream::NoPreference : PipeWireBaseEncodedStream::Speed);
        m_encoder->setMaxFramerate(quint32(plan.mode.hz), 1);
        // KWin sends a frame only when the screen changes; a still screen gave a Cast receiver two pictures and then none,
        // and its player waited for the next one for ever (row 81, part D, on a real Chromecast). KPipeWire encodes the last
        // frame again at the mode's rate while no new one comes, as GNOME Network Displays' intervideosrc does.
        m_encoder->setConstantFramerate(true);
        connect(m_encoder.get(), &PipeWireEncodedStream::newPacket, this, &Streamer::onVideoPacket);
        connect(m_encoder.get(), &PipeWireBaseEncodedStream::errorFound, this, [this](const QString &error) {
            qCWarning(THROW) << "encoder:" << error;
            m_error = error;
            Q_EMIT failed(error);
        });
        m_encoder->start();
        // KPipeWire says nothing when it cannot make an encoder ("No encoder could be created" in its log only): a picture
        // that does not come is said, never left as a Throw with no picture. KWin sends a frame when the stream starts,
        // so the first packet comes within seconds even on a still screen (a 4K software encode on a loaded machine took
        // up to 20 s in the loopback proof)
        QTimer::singleShot(PictureTimeoutMs, this, [this] {
            if (m_encoder && !m_gotVideo) {
                m_error = QStringLiteral("no picture came from the %1 encoder within %2 seconds").arg(m_plan.info.label).arg(PictureTimeoutMs / 1000);
                Q_EMIT failed(m_error);
            }
        });
    }
    qCInfo(THROW) << "streaming" << (plan.video ? plan.info.label : QStringLiteral("sound alone")) << plan.mode.text() << "in" << plan.info.format
                  << "with" << plan.info.audioCodec << "sound, serving on" << local << m_server.serverPort() << "for" << device;
    return true;
}

bool Streamer::openAudioEncoder()
{
    const Sound sound = Codecs::sound(m_plan.info.audioCodec);
    const AVCodec *codec = avcodec_find_encoder_by_name(sound.encoder.toUtf8().constData());
    if (!codec) {
        m_error = QStringLiteral("libavcodec has no %1 encoder (%2)").arg(sound.label, sound.encoder);
        return false;
    }
    m_audio = avcodec_alloc_context3(codec);
    m_audio->sample_rate = m_plan.audioRate;
    av_channel_layout_default(&m_audio->ch_layout, m_plan.audioChannels);
    m_audio->time_base = AVRational{1, m_plan.audioRate};
    AVDictionary *options = nullptr;
    // the sample layout the encoder takes, the deepest first: float, then 32, then 16 bit
    const AVSampleFormat *formats = nullptr;
    avcodec_get_supported_config(m_audio, codec, AV_CODEC_CONFIG_SAMPLE_FORMAT, 0, reinterpret_cast<const void **>(&formats), nullptr);
    AVSampleFormat chosen = AV_SAMPLE_FMT_NONE;
    for (AVSampleFormat want : {AV_SAMPLE_FMT_FLT, AV_SAMPLE_FMT_FLTP, AV_SAMPLE_FMT_S32, AV_SAMPLE_FMT_S32P, AV_SAMPLE_FMT_S16, AV_SAMPLE_FMT_S16P}) {
        for (const AVSampleFormat *f = formats; f && *f != AV_SAMPLE_FMT_NONE; ++f) {
            if (*f == want) {
                chosen = want;
                break;
            }
        }
        if (chosen != AV_SAMPLE_FMT_NONE) {
            break;
        }
    }
    m_audio->sample_fmt = chosen != AV_SAMPLE_FMT_NONE ? chosen : (formats ? formats[0] : AV_SAMPLE_FMT_FLT);
    if (sound.bitRate > 0) {
        m_audio->bit_rate = sound.bitRate;
    }
    if (sound.id == QLatin1String("opus")) {
        av_dict_set(&options, "application", "audio", 0);
        av_dict_set(&options, "frame_duration", "20", 0);
    } else if (sound.id == QLatin1String("flac")) {
        // 24 bit lossless; the samples are given as 32-bit integers and the encoder keeps their top 24 bits
        m_audio->bits_per_raw_sample = 24;
        av_dict_set(&options, "compression_level", "5", 0);
    } else if (sound.id == QLatin1String("pcm24")) {
        m_audio->bits_per_raw_sample = 24;
    }
    const int ret = avcodec_open2(m_audio, codec, &options);
    av_dict_free(&options);
    if (ret < 0) {
        m_error = QStringLiteral("the sound encoder could not start: %1").arg(averror(ret));
        avcodec_free_context(&m_audio);
        return false;
    }
    m_fifo = av_audio_fifo_alloc(AV_SAMPLE_FMT_FLT, m_plan.audioChannels, 8192);
    m_frame = av_frame_alloc();
    m_frame->format = m_audio->sample_fmt;
    // PCM has no frame size of its own: 1024 samples (21 ms at 48 kHz) a block
    m_frame->nb_samples = m_audio->frame_size > 0 ? m_audio->frame_size : 1024;
    av_channel_layout_copy(&m_frame->ch_layout, &m_audio->ch_layout);
    m_frame->sample_rate = m_plan.audioRate;
    if (av_frame_get_buffer(m_frame, 0) < 0) {
        m_error = QStringLiteral("out of memory for the sound");
        return false;
    }
    return true;
}

void Streamer::onSamples()
{
    const QByteArray data = m_sink.take();
    if (!m_audio || data.isEmpty()) {
        return;
    }
    const int channels = m_plan.audioChannels;
    const int samples = int(data.size() / (sizeof(float) * channels));
    if (m_audioStartMs < 0) {
        m_audioStartMs = m_clock.elapsed() - qint64(samples) * 1000 / m_plan.audioRate;
    }
    void *planes[1] = {const_cast<char *>(data.constData())};
    av_audio_fifo_write(m_fifo, planes, samples);
    encodeAudio();
}

void Streamer::encodeAudio()
{
    const int frameSize = m_frame->nb_samples;
    const int channels = m_plan.audioChannels;
    QByteArray block(int(sizeof(float)) * frameSize * channels, Qt::Uninitialized);
    AVPacket *pkt = av_packet_alloc();
    while (av_audio_fifo_size(m_fifo) >= frameSize) {
        void *planes[1] = {block.data()};
        av_audio_fifo_read(m_fifo, planes, frameSize);
        if (av_frame_make_writable(m_frame) < 0) {
            break;
        }
        const auto *in = reinterpret_cast<const float *>(block.constData());
        const AVSampleFormat fmt = AVSampleFormat(m_frame->format);
        const bool planar = av_sample_fmt_is_planar(fmt);
        for (int i = 0; i < frameSize * channels; ++i) {
            const int ch = i % channels, n = i / channels;
            const double v = std::clamp(double(in[i]), -1.0, 1.0);
            const int index = planar ? n : i;
            uint8_t *plane = m_frame->data[planar ? ch : 0];
            switch (av_get_packed_sample_fmt(fmt)) {
            case AV_SAMPLE_FMT_FLT:
                reinterpret_cast<float *>(plane)[index] = float(v);
                break;
            case AV_SAMPLE_FMT_S32:
                reinterpret_cast<int32_t *>(plane)[index] = int32_t(std::lrint(v * 2147483647.0));
                break;
            case AV_SAMPLE_FMT_S16:
                reinterpret_cast<int16_t *>(plane)[index] = int16_t(std::lrint(v * 32767.0));
                break;
            default:
                break;
            }
        }
        m_frame->pts = m_samplesOut;
        m_samplesOut += frameSize;
        if (avcodec_send_frame(m_audio, m_frame) < 0) {
            break;
        }
        while (avcodec_receive_packet(m_audio, pkt) == 0) {
            Kept k;
            k.video = false;
            k.data = QByteArray(reinterpret_cast<const char *>(pkt->data), pkt->size);
            k.ms = m_audioStartMs + pkt->pts * 1000 / m_plan.audioRate;
            k.durationMs = pkt->duration * 1000 / m_plan.audioRate;
            av_packet_unref(pkt);
            keep(k);
            writePacket(k);
        }
    }
    av_packet_free(&pkt);
}

void Streamer::stop()
{
    if (m_encoder) {
        m_encoder->stop();
        m_encoder.reset();
    }
    m_sink.stop();
    m_writer.reset();
    m_group.clear();
    m_groupBytes = 0;
    m_recentSound.clear();
    if (m_audio) {
        avcodec_free_context(&m_audio);
    }
    if (m_fifo) {
        av_audio_fifo_free(m_fifo);
        m_fifo = nullptr;
    }
    if (m_frame) {
        av_frame_free(&m_frame);
    }
    if (m_client) {
        m_client->disconnectFromHost();
        m_client = nullptr;
    }
    m_server.close();
}

QString Streamer::url() const
{
    const QHostAddress local = m_server.serverAddress();
    QString host = local.toString();
    if (local.protocol() == QAbstractSocket::IPv6Protocol) {
        // RFC 6874: a zone in a URL is written %25zone
        host = QLatin1Char('[') + host.replace(QLatin1Char('%'), QStringLiteral("%25")) + QLatin1Char(']');
    }
    return QStringLiteral("http://%1:%2/%3.%4")
        .arg(host)
        .arg(m_server.serverPort())
        .arg(m_token, m_plan.info.format == QLatin1String("matroska") ? QStringLiteral("mkv") : m_plan.info.format);
}

void Streamer::onConnection()
{
    while (QTcpSocket *socket = m_server.nextPendingConnection()) {
        // only the device the Throw was started for gets the stream: another address is closed at once, with nothing
        if (!socket->peerAddress().isEqual(m_device, QHostAddress::ConvertV4MappedToIPv4)) {
            qCWarning(THROW) << "closed a connection from" << socket->peerAddress() << ": the stream is for" << m_device << "only";
            socket->abort();
            socket->deleteLater();
            continue;
        }
        // a connection that sends no request line in time is closed
        QTimer::singleShot(RequestTimeoutMs, socket, [socket] {
            if (!socket->property("answered").toBool()) {
                qCInfo(THROW) << "closed a connection that sent no request in time";
                socket->abort();
            }
        });
        connect(socket, &QTcpSocket::readyRead, this, [this, socket] {
            if (socket->property("answered").toBool()) {
                socket->readAll();
                return;
            }
            if (!socket->canReadLine()) {
                if (socket->bytesAvailable() > 8192) {
                    socket->abort();
                }
                return;
            }
            const QByteArray line = socket->readLine().trimmed();
            socket->readAll();
            socket->setProperty("answered", true);
            const auto parts = line.split(' ');
            const QByteArray wanted = "/" + url().section(QLatin1Char('/'), 3).toUtf8();
            if (parts.size() < 2 || (parts[0] != "GET" && parts[0] != "HEAD") || parts[1] != wanted) {
                socket->write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                socket->disconnectFromHost();
                return;
            }
            socket->write("HTTP/1.1 200 OK\r\nContent-Type: " + m_plan.info.mime.toUtf8()
                          + "\r\nCache-Control: no-cache\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\n\r\n");
            if (parts[0] == "HEAD") {
                socket->disconnectFromHost();
                return;
            }
            serve(socket);
        });
        connect(socket, &QTcpSocket::disconnected, this, [this, socket] {
            if (m_client == socket) {
                qCInfo(THROW) << "the device closed the stream after" << (m_writer ? m_writer->bytes() : 0) << "bytes";
                m_bytesBefore += m_writer ? m_writer->bytes() : 0;
                m_writer.reset();
                m_client = nullptr;
            }
            socket->deleteLater();
        });
    }
}

void Streamer::serve(QTcpSocket *socket)
{
    // one reader at a time: a device that fetches again replaces its earlier connection
    if (m_client && m_client != socket) {
        m_bytesBefore += m_writer ? m_writer->bytes() : 0;
        m_client->disconnectFromHost();
    }
    m_client = socket;
    Muxer::Tracks tracks;
    tracks.format = m_plan.info.format;
    tracks.video = m_plan.video;
    tracks.codec = m_plan.info.codec;
    tracks.size = m_plan.mode.size;
    tracks.fps = qMax(1, m_plan.mode.hz);
    tracks.audio = m_audio != nullptr;
    tracks.audioCodec = m_plan.info.audioCodec;
    tracks.rate = m_plan.audioRate;
    tracks.channels = m_plan.audioChannels;
    if (m_audio) {
        tracks.audioExtradata = QByteArray(reinterpret_cast<const char *>(m_audio->extradata), m_audio->extradata_size);
        tracks.audioFrameSize = m_audio->frame_size;
        tracks.audioInitialPadding = m_audio->initial_padding;
    }
    m_writer = std::make_unique<Muxer>(socket, tracks);
    m_announced = false;
    qCInfo(THROW) << "the device fetches the stream from" << socket->peerAddress() << "; the current group of pictures:" << m_group.size()
                  << "packets";
    Q_EMIT clientConnected(socket->peerAddress().toString());
    // the current group of pictures, moved to now so that its sound (the last seconds kept) plays with it, then live
    std::vector<Kept> replay;
    if (m_plan.video && !m_group.empty()) {
        const qint64 shift = m_clock.elapsed() - m_group.back().ms;
        for (Kept k : m_group) {
            k.ms += shift;
            replay.push_back(k);
        }
        const qint64 from = replay.front().ms;
        for (const Kept &k : m_recentSound) {
            if (k.ms >= from) {
                replay.push_back(k);
            }
        }
        std::stable_sort(replay.begin(), replay.end(), [](const Kept &x, const Kept &y) {
            return x.ms < y.ms;
        });
    }
    for (const Kept &k : replay) {
        if (!writePacket(k)) {
            return;
        }
    }
}

void Streamer::keep(const Kept &packet)
{
    if (!packet.video) {
        m_recentSound.push_back(packet);
        while (!m_recentSound.empty() && m_recentSound.front().ms < packet.ms - RecentSoundMs) {
            m_recentSound.pop_front();
        }
        return;
    }
    if (packet.key) {
        m_group.clear();
        m_groupBytes = 0;
    }
    if (packet.key || !m_group.empty()) {
        m_group.push_back(packet);
        m_groupBytes += packet.data.size();
        if (m_groupBytes > GroupLimit) {
            // a group past this size is let go and a keyframe asked for, rather than handing a device a long stale group
            m_group.clear();
            m_groupBytes = 0;
            if (m_encoder) {
                m_encoder->requestKeyFrame();
            }
        }
    }
}

void Streamer::onVideoPacket(const PipeWireEncodedStream::Packet &packet)
{
    m_gotVideo = true;
    Kept k;
    k.video = true;
    k.data = packet.data();
    k.key = packet.isKeyFrame();
    k.ms = m_clock.elapsed();
    k.durationMs = 1000 / qMax(1, m_plan.mode.hz);
    keep(k);
    writePacket(k);
}

bool Streamer::writePacket(const Kept &packet)
{
    if (!m_writer) {
        return false;
    }
    if (!m_writer->write(packet)) {
        qCWarning(THROW) << "stream:" << m_writer->error();
        m_bytesBefore += m_writer->bytes();
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
