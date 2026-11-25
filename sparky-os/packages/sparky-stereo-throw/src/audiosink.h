// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// The sound of a Throw: a PipeWire sink named "Throw: <device>" that exists while the Throw runs. The person chooses it
// as any output (the desktop's default moves only by the rule for a newly connected headset or speaker, which a Throw
// sink is not: sparky-stereo-hardware's hook takes Bluetooth and USB sinks only). It is a client node of class
// Audio/Sink (as pw-loopback's capture side), not virtual (KDE's Sound page lists it), processed even when nothing plays
// into it, so the stream's sound never stops while the picture runs: silence is sound too.
#pragma once

#include <QByteArray>
#include <QMutex>
#include <QObject>
#include <QString>
#include <atomic>

struct pw_thread_loop;
struct pw_context;
struct pw_core;
struct pw_stream;

namespace Throw
{

class AudioSink : public QObject
{
    Q_OBJECT
public:
    explicit AudioSink(QObject *parent = nullptr);
    ~AudioSink() override;

    // float samples, interleaved, at rate and channels; false with error() when PipeWire refuses
    bool start(const QString &nodeName, const QString &description, int rate, int channels);
    void stop();
    QString error() const
    {
        return m_error;
    }
    // the samples captured since the last call (float, interleaved)
    QByteArray take();

Q_SIGNALS:
    void samplesReady();

private:
    static void onProcess(void *data);

    pw_thread_loop *m_loop = nullptr;
    pw_context *m_context = nullptr;
    pw_core *m_core = nullptr;
    pw_stream *m_stream = nullptr;
    void *m_listener = nullptr;
    int m_channels = 2;
    QMutex m_mutex;
    QByteArray m_pending;
    std::atomic<bool> m_signalled{false};
    QString m_error;
};

} // namespace Throw
