// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include <QChar>

#include <QByteArray>
#include <QMap>
#include <QString>
QString copyModelAssets(
    const QString& source, const QString& project, const QMap<QString, QByteArray>& expected);
QMap<QString, QByteArray> modelFingerprints(const QString& source);
