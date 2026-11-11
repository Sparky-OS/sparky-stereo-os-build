// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <QString>
namespace SparkyGraphics::VramSettings {
bool enabled(const QString &root = QStringLiteral("/"));
bool writeEnabled(bool enabled, QString *error);
}
