// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "previewsource.h"

#include <KLocalizedString>

#include <QMetaObject>
#include <QVideoFrameFormat>

#include <pipewire/pipewire.h>
#include <spa/param/video/format-utils.h>
#include <spa/utils/result.h>
#include <spa/param/video/raw.h>
#include <spa/pod/builder.h>

using namespace Sparky::Camera;

struct PreviewSource::Hooks {
    spa_hook stream;
};

namespace
{
QVideoFrameFormat::PixelFormat qtFormat(int spaFormat)
{
    switch (spaFormat) {
    case SPA_VIDEO_FORMAT_BGRx:
        return QVideoFrameFormat::Format_BGRX8888;
    case SPA_VIDEO_FORMAT_BGRA:
        return QVideoFrameFormat::Format_BGRA8888;
    case SPA_VIDEO_FORMAT_RGBx:
        return QVideoFrameFormat::Format_RGBX8888;
    case SPA_VIDEO_FORMAT_RGBA:
        return QVideoFrameFormat::Format_RGBA8888;
    default:
        return QVideoFrameFormat::Format_Invalid;
    }
}

void onState(void *data, pw_stream_state, pw_stream_state state, const char *error)
{
    static_cast<PreviewSource *>(data)->streamState(int(state), error);
}
void onParam(void *data, uint32_t id, const spa_pod *param)
{
    if (param && id == SPA_PARAM_Format) {
        static_cast<PreviewSource *>(data)->streamFormat(param);
    }
}
void onProcess(void *data)
{
    static_cast<PreviewSource *>(data)->streamProcess();
}
const pw_stream_events streamEvents = [] {
    pw_stream_events e{};
    e.version = PW_VERSION_STREAM_EVENTS;
    e.state_changed = onState;
    e.param_changed = onParam;
    e.process = onProcess;
    return e;
}();
}

PreviewSource::PreviewSource(QObject *parent)
    : QObject(parent)
{
    pw_init(nullptr, nullptr);
}

PreviewSource::~PreviewSource()
{
    stop();
}

void PreviewSource::setNodeId(int id)
{
    if (id == m_nodeId) {
        return;
    }
    m_nodeId = id;
    Q_EMIT nodeIdChanged();
    stop();
    start();
}

void PreviewSource::setVideoSink(QVideoSink *sink)
{
    if (sink == m_sink) {
        return;
    }
    m_sink = sink;
    Q_EMIT videoSinkChanged();
}

void PreviewSource::report(const QString &state, const QString &error, const QSize &size)
{
    m_state = state;
    m_error = error;
    m_frameSize = size;
    Q_EMIT stateChanged();
}

void PreviewSource::deliver(const QVideoFrame &frame)
{
    if (m_sink) {
        m_sink->setVideoFrame(frame);
    }
}

void PreviewSource::start()
{
    if (m_nodeId < 0) {
        report(QStringLiteral("idle"), QString(), QSize());
        return;
    }
    m_loop = pw_thread_loop_new("sparky-camera-preview", nullptr);
    if (!m_loop) {
        report(QStringLiteral("error"), i18n("The preview could not start: PipeWire's loop was not created."), QSize());
        return;
    }
    m_context = pw_context_new(pw_thread_loop_get_loop(m_loop), nullptr, 0);
    pw_thread_loop_start(m_loop);
    pw_thread_loop_lock(m_loop);
    m_core = m_context ? pw_context_connect(m_context, nullptr, 0) : nullptr;
    if (!m_core) {
        pw_thread_loop_unlock(m_loop);
        report(QStringLiteral("error"), i18n("The preview could not start: PipeWire did not accept the connection."), QSize());
        stop();
        return;
    }
    pw_properties *props = pw_properties_new(PW_KEY_MEDIA_TYPE, "Video", PW_KEY_MEDIA_CATEGORY, "Capture", PW_KEY_MEDIA_ROLE, "Camera", PW_KEY_APP_NAME, "Camera settings", nullptr);
    m_stream = pw_stream_new(m_core, "camera-settings-preview", props);
    m_hooks = new Hooks;
    pw_stream_add_listener(m_stream, &m_hooks->stream, &streamEvents, this);

    uint8_t buffer[1024];
    spa_pod_builder b = SPA_POD_BUILDER_INIT(buffer, sizeof buffer);
    spa_rectangle minSize = SPA_RECTANGLE(1, 1);
    spa_rectangle maxSize = SPA_RECTANGLE(8192, 8192);
    spa_rectangle defSize = SPA_RECTANGLE(1280, 720);
    spa_fraction minRate = SPA_FRACTION(0, 1);
    spa_fraction maxRate = SPA_FRACTION(1000, 1);
    spa_fraction defRate = SPA_FRACTION(30, 1);
    const spa_pod *params[1];
    params[0] = static_cast<const spa_pod *>(spa_pod_builder_add_object(&b,
        SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat,
        SPA_FORMAT_mediaType, SPA_POD_Id(SPA_MEDIA_TYPE_video),
        SPA_FORMAT_mediaSubtype, SPA_POD_Id(SPA_MEDIA_SUBTYPE_raw),
        SPA_FORMAT_VIDEO_format, SPA_POD_CHOICE_ENUM_Id(5, SPA_VIDEO_FORMAT_BGRx, SPA_VIDEO_FORMAT_BGRx, SPA_VIDEO_FORMAT_BGRA, SPA_VIDEO_FORMAT_RGBx, SPA_VIDEO_FORMAT_RGBA),
        SPA_FORMAT_VIDEO_size, SPA_POD_CHOICE_RANGE_Rectangle(&defSize, &minSize, &maxSize),
        SPA_FORMAT_VIDEO_framerate, SPA_POD_CHOICE_RANGE_Fraction(&defRate, &minRate, &maxRate)));
    const int r = pw_stream_connect(m_stream, PW_DIRECTION_INPUT, uint32_t(m_nodeId), pw_stream_flags(PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS), params, 1);
    pw_thread_loop_unlock(m_loop);
    if (r < 0) {
        report(QStringLiteral("error"), i18n("The preview could not start: %1", QString::fromLocal8Bit(spa_strerror(r))), QSize());
        return;
    }
    report(QStringLiteral("connecting"), QString(), QSize());
}

void PreviewSource::stop()
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
        if (m_context) {
            pw_context_destroy(m_context);
            m_context = nullptr;
        }
        pw_thread_loop_unlock(m_loop);
        pw_thread_loop_stop(m_loop);
        pw_thread_loop_destroy(m_loop);
        m_loop = nullptr;
    }
    delete m_hooks;
    m_hooks = nullptr;
    m_format = 0;
}

void PreviewSource::streamState(int state, const char *error)
{
    QString s = QStringLiteral("connecting");
    QString e;
    switch (state) {
    case PW_STREAM_STATE_ERROR:
        s = QStringLiteral("error");
        e = i18n("The preview stopped: %1", QString::fromUtf8(error ? error : "unknown error"));
        break;
    case PW_STREAM_STATE_STREAMING:
        s = QStringLiteral("streaming");
        break;
    case PW_STREAM_STATE_UNCONNECTED:
        s = QStringLiteral("idle");
        break;
    default:
        break;
    }
    const QSize size = m_size;
    QMetaObject::invokeMethod(this, "report", Qt::QueuedConnection, Q_ARG(QString, s), Q_ARG(QString, e), Q_ARG(QSize, size));
}

void PreviewSource::streamFormat(const spa_pod *param)
{
    spa_video_info_raw info{};
    if (spa_format_video_raw_parse(param, &info) < 0) {
        return;
    }
    m_format = int(info.format);
    m_size = QSize(int(info.size.width), int(info.size.height));
}

void PreviewSource::streamProcess()
{
    pw_buffer *buf = pw_stream_dequeue_buffer(m_stream);
    if (!buf) {
        return;
    }
    spa_data &d = buf->buffer->datas[0];
    const QVideoFrameFormat::PixelFormat pf = qtFormat(m_format);
    if (d.data && d.chunk->size && pf != QVideoFrameFormat::Format_Invalid && !m_size.isEmpty()) {
        QVideoFrame frame(QVideoFrameFormat(m_size, pf));
        if (frame.map(QVideoFrame::WriteOnly)) {
            const int stride = d.chunk->stride ? d.chunk->stride : m_size.width() * 4;
            const uchar *src = static_cast<const uchar *>(d.data) + d.chunk->offset;
            const int rows = qMin(m_size.height(), int(d.chunk->size / stride));
            for (int y = 0; y < rows; ++y) {
                memcpy(frame.bits(0) + y * frame.bytesPerLine(0), src + y * stride, qMin(stride, frame.bytesPerLine(0)));
            }
            frame.unmap();
            QMetaObject::invokeMethod(this, "deliver", Qt::QueuedConnection, Q_ARG(QVideoFrame, frame));
            if (m_size != m_reported) {
                m_reported = m_size;
                QMetaObject::invokeMethod(this, "report", Qt::QueuedConnection, Q_ARG(QString, QStringLiteral("streaming")), Q_ARG(QString, QString()), Q_ARG(QSize, m_size));
            }
        }
    }
    pw_stream_queue_buffer(m_stream, buf);
}
