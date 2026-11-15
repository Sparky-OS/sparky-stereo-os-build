// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QPointer>
#include <QVideoFrame>
#include <QVideoSink>

struct spa_pod;
struct pw_thread_loop;
struct pw_context;
struct pw_core;
struct pw_stream;

namespace Sparky::Camera
{
// A PipeWire video stream from one camera node, handed to a QVideoSink. A QML VideoOutput shows it, so the page draws a
// two-lens camera's preview the way the edition's players draw a film: VideoOutput's stereoInput takes the packing apart
// and declares the pair to Stereo KWin.
class PreviewSource : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int nodeId READ nodeId WRITE setNodeId NOTIFY nodeIdChanged)
    Q_PROPERTY(QVideoSink *videoSink READ videoSink WRITE setVideoSink NOTIFY videoSinkChanged)
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    Q_PROPERTY(QString error READ error NOTIFY stateChanged)
    Q_PROPERTY(QSize frameSize READ frameSize NOTIFY stateChanged)

public:
    explicit PreviewSource(QObject *parent = nullptr);
    ~PreviewSource() override;

    int nodeId() const { return m_nodeId; }
    void setNodeId(int id);
    QVideoSink *videoSink() const { return m_sink; }
    void setVideoSink(QVideoSink *sink);
    QString state() const { return m_state; }
    QString error() const { return m_error; }
    QSize frameSize() const { return m_frameSize; }

    // called from the PipeWire thread
    void streamState(int state, const char *error);
    void streamFormat(const spa_pod *param);
    void streamProcess();

Q_SIGNALS:
    void nodeIdChanged();
    void videoSinkChanged();
    void stateChanged();

private Q_SLOTS:
    void deliver(const QVideoFrame &frame);
    void report(const QString &state, const QString &error, const QSize &size);

private:
    void start();
    void stop();

    int m_nodeId = -1;
    QPointer<QVideoSink> m_sink;
    QString m_state = QStringLiteral("idle");
    QString m_error;
    QSize m_frameSize;
    pw_thread_loop *m_loop = nullptr;
    pw_context *m_context = nullptr;
    pw_core *m_core = nullptr;
    pw_stream *m_stream = nullptr;
    struct Hooks;
    Hooks *m_hooks = nullptr;
    int m_format = 0; // the SPA video format negotiated
    QSize m_size;
    QSize m_reported;
};
}
