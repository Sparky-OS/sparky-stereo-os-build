// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <QMutex>
#include <QRect>
#include <QString>
#include <QThread>
#include <atomic>
#include <deque>

// The thread that owns libf3d: its engine, its GLX window (a child of the program's window, the 3D area) and its event loop.
// The rest of the program talks to it with commands; it answers with signals.
class F3DWorker : public QThread
{
    Q_OBJECT
public:
    struct Command {
        enum Kind { Place, Load, Reset, TogglePlay, Stereo, Quit } kind = Quit;
        QString path;
        bool flag = false;
        quint64 parent = 0;
        QRect rect;      // the place of the 3D area in the parent, in device pixels
        int percent = 100; // the resolution of one eye against the area, in percent
    };
    void post(const Command &command);
    // the id of the window libf3d made, 0 before the first render
    quint64 nativeWindow() const { return m_native.load(); }

Q_SIGNALS:
    void loaded(const QString &path, bool hasAnimation);
    void loadFailed(const QString &path, const QString &reason);
    // 0 not in use, 1 delivered, 2 not offered, 3 not delivered yet, 4 not readable
    void depthState(int state, double sunk, double popped);
    void playingChanged(bool playing);
    void stereoFailed();

protected:
    void run() override;

private:
    QMutex m_mutex;
    std::deque<Command> m_commands;
    std::atomic<quint64> m_native{0};
};
