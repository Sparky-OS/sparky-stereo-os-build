// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "controller.h"
#include "session.h"

// Hands what failed to the edition's one engine, sparky-stereo-problems (ORDER 346f-1), which keeps it until it works
// again and shows it in the session. A TV that does not go to standby or wake with the screen, a CEC adapter that cannot
// be used and a login session that cannot be found are failures; a refusal to power another active input (skipped) is
// the helper's design and is not.
class CecProblems : public QObject
{
    Q_OBJECT

public:
    explicit CecProblems(QObject *parent = nullptr);
    // connects the controller's and the session's failures and recoveries
    void watch(CecController &controller, SessionGate &session);

public Q_SLOTS:
    void keep(const QString &output, const QString &kind, const QString &detail, const QString &evidence);
    void acknowledged(const QString &output);
    void sessionFailed(const QString &reason);
    void sessionWorks();
};
