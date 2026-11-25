// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include "audiosink.h"
#include "logging.h"

#include <QMetaObject>
#include <QMutexLocker>

#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>
#include <spa/pod/builder.h>
#include <spa/utils/result.h>

namespace Throw
{

AudioSink::AudioSink(QObject *parent)
    : QObject(parent)
{
}

AudioSink::~AudioSink()
{
    stop();
}

void AudioSink::onProcess(void *data)
{
    auto self = static_cast<AudioSink *>(data);
    pw_buffer *b = pw_stream_dequeue_buffer(self->m_stream);
    if (!b) {
        return;
    }
    spa_buffer *buf = b->buffer;
    if (buf->n_datas > 0 && buf->datas[0].data && buf->datas[0].chunk) {
        const auto *chunk = buf->datas[0].chunk;
        const uint32_t offset = qMin<uint32_t>(chunk->offset, buf->datas[0].maxsize);
        const uint32_t size = qMin<uint32_t>(chunk->size, buf->datas[0].maxsize - offset);
        {
            QMutexLocker lock(&self->m_mutex);
            self->m_pending.append(static_cast<const char *>(buf->datas[0].data) + offset, size);
        }
        if (!self->m_signalled.exchange(true)) {
            QMetaObject::invokeMethod(self, &AudioSink::samplesReady, Qt::QueuedConnection);
        }
    }
    pw_stream_queue_buffer(self->m_stream, b);
}

bool AudioSink::start(const QString &nodeName, const QString &description, int rate, int channels)
{
    pw_init(nullptr, nullptr);
    m_channels = channels;
    m_loop = pw_thread_loop_new("throw-sound", nullptr);
    if (!m_loop) {
        m_error = QStringLiteral("PipeWire's thread loop could not be made");
        return false;
    }
    m_context = pw_context_new(pw_thread_loop_get_loop(m_loop), nullptr, 0);
    if (!m_context || pw_thread_loop_start(m_loop) < 0) {
        m_error = QStringLiteral("PipeWire's context could not be made");
        stop();
        return false;
    }
    pw_thread_loop_lock(m_loop);
    m_core = pw_context_connect(m_context, nullptr, 0);
    if (!m_core) {
        pw_thread_loop_unlock(m_loop);
        m_error = QStringLiteral("PipeWire is not running in this session");
        stop();
        return false;
    }
    pw_properties *props = pw_properties_new(PW_KEY_MEDIA_TYPE, "Audio", PW_KEY_MEDIA_CLASS, "Audio/Sink", PW_KEY_NODE_VIRTUAL, "false",
                                             "node.always-process", "true", PW_KEY_NODE_WANT_DRIVER, "true", "device.icon-name", "video-display",
                                             nullptr);
    pw_properties_set(props, PW_KEY_NODE_NAME, nodeName.toUtf8().constData());
    pw_properties_set(props, PW_KEY_NODE_DESCRIPTION, description.toUtf8().constData());
    pw_properties_set(props, PW_KEY_MEDIA_NAME, description.toUtf8().constData());
    static const pw_stream_events ev = [] {
        pw_stream_events e{};
        e.version = PW_VERSION_STREAM_EVENTS;
        e.process = &AudioSink::onProcess;
        return e;
    }();
    m_stream = pw_stream_new(m_core, description.toUtf8().constData(), props);
    auto hook = new spa_hook{};
    m_listener = hook;
    if (!m_stream) {
        pw_thread_loop_unlock(m_loop);
        m_error = QStringLiteral("PipeWire refused the sink");
        stop();
        return false;
    }
    pw_stream_add_listener(m_stream, hook, &ev, this);

    uint8_t buffer[1024];
    spa_pod_builder builder = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
    spa_audio_info_raw info{};
    info.format = SPA_AUDIO_FORMAT_F32;
    info.rate = uint32_t(rate);
    info.channels = uint32_t(channels);
    info.position[0] = SPA_AUDIO_CHANNEL_FL;
    info.position[1] = SPA_AUDIO_CHANNEL_FR;
    const spa_pod *params[1] = {spa_format_audio_raw_build(&builder, SPA_PARAM_EnumFormat, &info)};
    const int res = pw_stream_connect(m_stream, PW_DIRECTION_INPUT, PW_ID_ANY,
                                      pw_stream_flags(PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS | PW_STREAM_FLAG_RT_PROCESS), params, 1);
    pw_thread_loop_unlock(m_loop);
    if (res < 0) {
        m_error = QStringLiteral("PipeWire refused the sink's format: %1").arg(QString::fromUtf8(spa_strerror(res)));
        stop();
        return false;
    }
    qCInfo(THROW) << "the sound sink" << description << "is ready," << rate << "Hz," << channels << "channels";
    return true;
}

void AudioSink::stop()
{
    if (m_loop) {
        pw_thread_loop_lock(m_loop);
        if (m_stream) {
            pw_stream_destroy(m_stream);
            m_stream = nullptr;
        }
        if (m_core) {
            pw_core_disconnect(m_core);
            m_core = nullptr;
        }
        pw_thread_loop_unlock(m_loop);
        pw_thread_loop_stop(m_loop);
        if (m_context) {
            pw_context_destroy(m_context);
            m_context = nullptr;
        }
        pw_thread_loop_destroy(m_loop);
        m_loop = nullptr;
    }
    delete static_cast<spa_hook *>(m_listener);
    m_listener = nullptr;
}

QByteArray AudioSink::take()
{
    QMutexLocker lock(&m_mutex);
    m_signalled = false;
    QByteArray out;
    out.swap(m_pending);
    return out;
}

} // namespace Throw
