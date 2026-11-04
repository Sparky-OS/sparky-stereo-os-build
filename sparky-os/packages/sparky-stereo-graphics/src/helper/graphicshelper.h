// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <KAuth/ActionReply>
#include <QObject>
class GraphicsHelper : public QObject {
    Q_OBJECT
public Q_SLOTS:
    KAuth::ActionReply savevram(const QVariantMap &args);
};
