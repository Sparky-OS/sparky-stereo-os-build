/*
    SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "umsprofile.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>

namespace
{
const QRegularExpression serverNameLine(QStringLiteral("^\\s*server_name\\s*=(.*)$"));

QString escapeValue(const QString &value)
{
    QString out;
    for (const QChar c : value) {
        if (c == QLatin1Char('\\')) {
            out += QLatin1Char('\\');
        }
        out += c;
    }
    return out;
}

QString unescapeValue(const QString &value)
{
    QString out;
    bool escaped = false;
    for (const QChar c : value.trimmed()) {
        if (!escaped && c == QLatin1Char('\\')) {
            escaped = true;
            continue;
        }
        escaped = false;
        out += c;
    }
    return out;
}

QJsonObject newFolder(const QString &path)
{
    return QJsonObject{
        {QStringLiteral("file"), path},
        {QStringLiteral("monitored"), true},
        {QStringLiteral("metadata"), true},
        {QStringLiteral("active"), true},
        {QStringLiteral("groups"), QJsonArray()},
        {QStringLiteral("type"), QStringLiteral("Folder")},
    };
}

bool isFolder(const QJsonValue &entry)
{
    return entry.isObject() && entry.toObject().value(QStringLiteral("type")).toString() == QLatin1String("Folder");
}
}

UmsProfile::UmsProfile(const QString &directory)
    : m_directory(directory)
{
}

QString UmsProfile::defaultDirectory()
{
    const QString custom = qEnvironmentVariable("UMS_PROFILE");
    if (!custom.isEmpty()) {
        return custom;
    }
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/UMS");
}

QStringList UmsProfile::defaultFolders()
{
    const QString home = QDir::homePath();
    QStringList folders;
    for (const auto location : {QStandardPaths::PicturesLocation, QStandardPaths::MusicLocation, QStandardPaths::MoviesLocation}) {
        const QString path = QDir::cleanPath(QStandardPaths::writableLocation(location));
        if (!path.isEmpty() && path != QDir::cleanPath(home)) {
            folders << path;
        }
    }
    return folders;
}

QString UmsProfile::sharedPath() const
{
    return m_directory + QStringLiteral("/SHARED.conf");
}

QString UmsProfile::configPath() const
{
    return m_directory + QStringLiteral("/UMS.conf");
}

QString UmsProfile::errorString() const
{
    return m_error;
}

QStringList UmsProfile::folders() const
{
    QFile file(sharedPath());
    if (!file.open(QIODevice::ReadOnly)) {
        return defaultFolders();
    }
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    QStringList result;
    for (const QJsonValue entry : doc.array()) {
        if (isFolder(entry)) {
            result << entry.toObject().value(QStringLiteral("file")).toString();
        }
    }
    return result;
}

bool UmsProfile::setFolders(const QStringList &folders)
{
    QJsonArray existing;
    QFile file(sharedPath());
    if (file.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        if (!doc.isArray()) {
            m_error = QStringLiteral("%1 is not a JSON array").arg(sharedPath());
            return false;
        }
        existing = doc.array();
        file.close();
    }

    QJsonArray result;
    QStringList kept;
    for (const QJsonValue entry : std::as_const(existing)) {
        if (!isFolder(entry)) {
            result << entry;
            continue;
        }
        const QString path = entry.toObject().value(QStringLiteral("file")).toString();
        if (folders.contains(path) && !kept.contains(path)) {
            result << entry;
            kept << path;
        }
    }
    for (const QString &path : folders) {
        if (!kept.contains(path)) {
            result << newFolder(path);
            kept << path;
        }
    }

    QDir().mkpath(m_directory);
    QSaveFile out(sharedPath());
    if (!out.open(QIODevice::WriteOnly)) {
        m_error = out.errorString();
        return false;
    }
    out.write(QJsonDocument(result).toJson(QJsonDocument::Indented));
    if (!out.commit()) {
        m_error = out.errorString();
        return false;
    }
    return true;
}

QString UmsProfile::serverName() const
{
    QFile file(configPath());
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    QString name;
    for (const QByteArray &line : file.readAll().split('\n')) {
        const auto match = serverNameLine.match(QString::fromUtf8(line));
        if (match.hasMatch()) {
            name = unescapeValue(match.captured(1));
        }
    }
    return name;
}

bool UmsProfile::setServerName(const QString &name)
{
    QStringList lines;
    QFile file(configPath());
    if (file.open(QIODevice::ReadOnly)) {
        lines = QString::fromUtf8(file.readAll()).split(QLatin1Char('\n'));
        if (lines.last().isEmpty()) {
            lines.removeLast();
        }
        file.close();
    }

    const QString line = QStringLiteral("server_name = ") + escapeValue(name);
    bool replaced = false;
    for (QString &existing : lines) {
        if (serverNameLine.match(existing).hasMatch()) {
            existing = line;
            replaced = true;
        }
    }
    if (!replaced) {
        lines << line;
    }

    QDir().mkpath(m_directory);
    QSaveFile out(configPath());
    if (!out.open(QIODevice::WriteOnly)) {
        m_error = out.errorString();
        return false;
    }
    out.write((lines.join(QLatin1Char('\n')) + QLatin1Char('\n')).toUtf8());
    if (!out.commit()) {
        m_error = out.errorString();
        return false;
    }
    return true;
}
