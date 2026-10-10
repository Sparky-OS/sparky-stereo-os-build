// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QString>
#include <QVariantMap>

// The page shows and changes only these files, so a hand edit and the page
// always agree: /etc/default/sparky-stereo-zram (ZRAM=auto|on|off) and
// /etc/default/cushion-swap (CUSHION_SWAP=on|off).
namespace MemorySettings
{
QString zramConfigPath();
QString cushionConfigPath();
QString cushionStatusPath();
QString zramAutoPath();
QString swapsPath();

QString readValue(const QString &path, const QString &key);
bool writeValue(const QString &path, const QString &key, const QString &value, QString *error);
QVariantMap readKeyValues(const QString &path);
QVariantMap readKeyValues(const QByteArray &text);
}
