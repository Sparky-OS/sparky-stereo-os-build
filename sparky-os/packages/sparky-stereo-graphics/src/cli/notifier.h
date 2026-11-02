// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "problems.h"

#include <QFileSystemWatcher>
#include <QHash>
#include <QObject>
#include <QSet>

// sparky-stereo-gpu-env --notify, the session's side (sparky-stereo-graphics-problems.service): each kept problem as a
// notification (org.freedesktop.Notifications, critical, so it stays until the person closes it), once per session and
// record. A GPU choice that cannot be used offers each GPU that can as an action, "Use NAME", which saves that GPU as the
// person's choice: the other GPUs are only ever the person's explicit choice. "Open Graphics settings" opens the page.
// It runs while one of its notifications is open, and shows the problems kept meanwhile too.
class Notifier : public QObject
{
    Q_OBJECT

public:
    explicit Notifier(const QString &root, QObject *parent = nullptr);
    // 0 when every problem was shown, 1 when one could not be
    int run();

private Q_SLOTS:
    void actionInvoked(uint id, const QString &action);
    void notificationClosed(uint id, uint reason);
    void rescan();

private:
    void use(const SparkyGraphics::Problem &problem, const QString &gpu);
    void finishIfDone();

    QString m_root;
    QHash<uint, SparkyGraphics::Problem> m_shown;
    QSet<QString> m_seen;
    QString m_seenFile;
    QFileSystemWatcher m_watcher;
    int m_failures = 0;
};
