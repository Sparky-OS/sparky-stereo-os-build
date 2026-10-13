// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include <QImage>
#include <QObject>
#include <QProcess>
#include <QSocketNotifier>
#include <QTimer>

class FrameClient : public QObject
{
    Q_OBJECT
public:
    explicit FrameClient(QObject *parent = nullptr);
    ~FrameClient() override;
    void setRunning(bool running);
    void setCycleSeconds(int seconds);
    const QImage &frame() const { return m_frame; }
Q_SIGNALS:
    void frameChanged();
private:
    friend class NativeFrameTest;
    void readFrame();
    void clear();
    void sendControl(const QByteArray &data);
    QProcess m_process;
    QTimer m_cycle;
    QTimer m_deadline;
    QSocketNotifier *m_notifier = nullptr;
    int m_control = -1;
    int m_pixels = -1;
    int m_childControl = -1;
    int m_childPixels = -1;
    quint32 m_sequence = 0;
    QImage m_frame;
    bool m_running = false;
};
