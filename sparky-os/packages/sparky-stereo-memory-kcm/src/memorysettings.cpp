// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "memorysettings.h"

#include <QFile>
#include <QRegularExpression>
#include <QSaveFile>

using namespace Qt::StringLiterals;

namespace MemorySettings
{
static QString path(const QString &file)
{
    // Tests only: the files under another root.
    return qEnvironmentVariable("SPARKY_STEREO_MEMORY_ROOT") + file;
}

QString zramConfigPath()
{
    return path(u"/etc/default/sparky-stereo-zram"_s);
}

QString cushionConfigPath()
{
    return path(u"/etc/default/cushion-swap"_s);
}

QString cushionStatusPath()
{
    return path(u"/run/cushion-swap/status"_s);
}

QString zramAutoPath()
{
    return path(u"/usr/libexec/sparky-stereo/zram-auto"_s);
}

QString swapsPath()
{
    return path(u"/proc/swaps"_s);
}

static QString unquote(QString value)
{
    const qsizetype comment = value.indexOf(u" #"_s);
    if (comment >= 0) {
        value.truncate(comment);
    }
    value = value.trimmed();
    if (value.size() >= 2 && (value.startsWith(u'"') || value.startsWith(u'\'')) && value.endsWith(value.front())) {
        value = value.mid(1, value.size() - 2);
    }
    return value;
}

QVariantMap readKeyValues(const QByteArray &text)
{
    static const QRegularExpression line(u"^\\s*([A-Z_][A-Z0-9_]*)=(.*)$"_s);
    QVariantMap values;
    for (const QByteArray &raw : text.split('\n')) {
        const auto match = line.match(QString::fromUtf8(raw));
        if (match.hasMatch()) {
            values.insert(match.captured(1), unquote(match.captured(2)));
        }
    }
    return values;
}

QVariantMap readKeyValues(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    return readKeyValues(file.readAll());
}

QString readValue(const QString &path, const QString &key)
{
    return readKeyValues(path).value(key).toString();
}

bool writeValue(const QString &path, const QString &key, const QString &value, QString *error)
{
    QByteArray text;
    QFile current(path);
    if (current.exists() && current.open(QIODevice::ReadOnly)) {
        text = current.readAll();
        current.close();
    }
    const QRegularExpression keyLine(u"^\\s*%1="_s.arg(key));
    QStringList lines;
    bool written = false;
    for (const QString &line : QString::fromUtf8(text).split(u'\n')) {
        if (keyLine.match(line).hasMatch()) {
            if (!written) {
                lines.append(u"%1=%2"_s.arg(key, value));
                written = true;
            }
            continue;
        }
        lines.append(line);
    }
    while (!lines.isEmpty() && lines.last().isEmpty()) {
        lines.removeLast();
    }
    if (!written) {
        lines.append(u"%1=%2"_s.arg(key, value));
    }
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly) || file.write((lines.join(u'\n') + u'\n').toUtf8()) < 0 || !file.commit()) {
        if (error) {
            *error = file.errorString();
        }
        return false;
    }
    QFile::setPermissions(path, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ReadGroup | QFileDevice::ReadOther);
    return true;
}
}
