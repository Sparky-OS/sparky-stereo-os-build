// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#include "vramsettings.h"
#include <QFile>
#include <QLockFile>
#include <QRegularExpression>
#include <QSaveFile>
using namespace Qt::StringLiterals;
namespace SparkyGraphics::VramSettings {
static const QString path = u"/etc/default/sparky-stereo-vram-boost"_s;
static const QRegularExpression assignment(u"^\\s*(?:export\\s+)?SPARKY_STEREO_VRAM_BOOST=(.*)$"_s);
bool enabled(const QString &root)
{
    QFile file(root + path);
    if (!file.open(QIODevice::ReadOnly)) {
        return false;
    }
    QString value;
    for (const QString &line : QString::fromUtf8(file.readAll()).split(u'\n')) {
        const auto match = assignment.match(line);
        if (match.hasMatch()) {
            value = match.captured(1).section(u'#', 0, 0).trimmed();
            if (value.size() >= 2 && (value.front() == u'"' || value.front() == u'\'') && value.back() == value.front()) {
                value = value.mid(1, value.size() - 2);
            }
        }
    }
    return value == u"yes"_s || value == u"amd-dgpu"_s;
}
bool writeEnabled(bool enabled, QString *error)
{
    QLockFile lock(path + u".lock"_s);
    if (!lock.tryLock(3000)) {
        *error = u"The video memory setting is busy"_s;
        return false;
    }
    QFile current(path);
    QStringList lines;
    if (current.exists()) {
        if (!current.open(QIODevice::ReadOnly)) {
            *error = current.errorString();
            return false;
        }
        for (const QString &line : QString::fromUtf8(current.readAll()).split(u'\n')) {
            if (!assignment.match(line).hasMatch()) {
                lines.append(line);
            }
        }
        current.close();
    }
    while (!lines.isEmpty() && lines.last().isEmpty()) {
        lines.removeLast();
    }
    lines.append(u"SPARKY_STEREO_VRAM_BOOST="_s + (enabled ? u"yes"_s : u"no"_s));
    QSaveFile file(path);
    const QByteArray bytes = (lines.join(u'\n') + u'\n').toUtf8();
    if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size() || !file.commit()) {
        *error = file.errorString();
        return false;
    }
    return true;
}
}
