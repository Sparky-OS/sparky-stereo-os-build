// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QString>
#include <QVariantMap>

// The page and hand edits share /etc/default/cushion-swap (CUSHION_SWAP=on|off).
namespace MemorySettings
{
QString cushionConfigPath();
QString cushionStatusPath();

QString readValue(const QString &path, const QString &key);
bool writeValue(const QString &path, const QString &key, const QString &value, QString *error);
QVariantMap readKeyValues(const QString &path);
QVariantMap readKeyValues(const QByteArray &text);
}
