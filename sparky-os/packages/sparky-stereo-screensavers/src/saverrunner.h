// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QImage>
#include <QObject>
#include <QProcess>
#include <QSize>
#include <QSocketNotifier>
#include <QTimer>

/* One saver, run by the page's helper on a private display, its pictures
 * taken from the show's frame channel. The checks of a frame are the stereo
 * show's own (gl-stereo, plasma/frameclient.cpp): envelope, sequence, format,
 * size, storage, owner and seals, before a byte is read. */
class SaverRunner : public QObject
{
    Q_OBJECT
public:
    enum Failure { NoFailure = 0, NotOffered = 3, NotInstalled = 4, NoDisplay = 5, Ended = 6, NoPicture = 7, NoHelper = 8, BadFrame = 9 };
    Q_ENUM(Failure)

    explicit SaverRunner(QObject *parent = nullptr);
    ~SaverRunner() override;

    /* SEPARATION below zero leaves the saver's own. */
    void start(const QString &saver, const QSize &view, double separation);
    void stop();
    bool running() const { return m_running; }
    QString saver() const { return m_saver; }
    const QImage &frame() const { return m_frame; }
    static QString helper();

Q_SIGNALS:
    void frameChanged();
    void failed(SaverRunner::Failure failure, const QString &detail);

private:
    void readFrame();
    void fail(Failure failure, const QString &detail);
    void closeSockets();
    QProcess *m_process = nullptr;
    QTimer m_deadline;
    QSocketNotifier *m_notifier = nullptr;
    int m_pixels = -1;
    quint32 m_sequence = 0;
    QImage m_frame;
    QString m_saver;
    QByteArray m_said;
    bool m_running = false;
};
