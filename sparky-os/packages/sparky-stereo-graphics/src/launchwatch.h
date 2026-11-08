// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QString>
#include <QStringList>

namespace SparkyGraphics
{

// What the session's systemd knows of an application it ran: KIO starts every program from a desktop entry as a
// transient service, app-NAME@ID.service (XDG standardization for applications, systemd.io/DESKTOP_ENVIRONMENTS), and
// systemd keeps how that service ended. ORDER 467 asks it, never a watcher of our own.
struct UnitFacts {
    bool found = false; // the unit is on the session's systemd
    QString error; // why not, when it is not
    QString result; // Result: success, exit-code, signal, core-dump, timeout, oom-kill, ...
    QString sourcePath; // the desktop file KIO started it from
    int exitCode = 0; // ExecMainStatus: the exit status, or the signal number when it was killed
    qint64 activeEnter = 0; // microseconds on the monotonic clock
    qint64 inactiveEnter = 0;
    QStringList environment; // KEY=value, what the program was started with

    // Seconds the program ran; -1 when systemd gives no time
    double seconds() const;
};

namespace LaunchWatch
{
// How many seconds after its start a program's death still counts as "dying at start". [Launch] DiedWithin in
// sparky-stereo-graphicsrc; 0 turns the notice off. The default is the measured one (README, "Dying at start").
int window();
constexpr int defaultWindow = 10;

// "sparky-stereo-browser" of "app-sparky\x2dstereo\x2dbrowser@3f2a....service"; empty when the unit is not one of
// KIO's applications
QString appNameOf(const QString &unit);
// The key a death is kept under
QString keyOf(const QString &appName);

UnitFacts read(const QString &unit);
// The last lines the program wrote, from the session's journal ("" when there are none)
QString lastLines(const QString &unit);
}

}
