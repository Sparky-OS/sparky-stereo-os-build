// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "pipewirecameras.h"

#include <KLocalizedString>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>

using namespace Sparky::Camera;

namespace
{
// pw-dump and pw-metadata come with PipeWire (package pipewire-bin); arguments go as a list, never through a shell
bool run(const QString &program, const QStringList &arguments, QByteArray *out, QString *error)
{
    QProcess p;
    p.start(program, arguments);
    if (!p.waitForStarted(3000)) {
        *error = i18n("%1 could not be started. Is PipeWire installed?", program);
        return false;
    }
    if (!p.waitForFinished(8000)) {
        p.kill();
        p.waitForFinished(1000);
        *error = i18n("%1 did not answer. PipeWire may not be running in this session.", program);
        return false;
    }
    if (p.exitStatus() != QProcess::NormalExit || p.exitCode() != 0) {
        *error = i18n("%1 failed: %2", program, QString::fromLocal8Bit(p.readAllStandardError()).trimmed());
        return false;
    }
    *out = p.readAllStandardOutput();
    return true;
}

QString valueName(const QJsonValue &v)
{
    // the metadata value is {"name": "node.name"}
    return v.toObject().value(QStringLiteral("name")).toString();
}
}

NodeList Sparky::Camera::listCameraNodes()
{
    NodeList result;
    QByteArray json;
    if (!run(QStringLiteral("pw-dump"), {}, &json, &result.error)) {
        return result;
    }
    QJsonParseError parse;
    const QJsonDocument doc = QJsonDocument::fromJson(json, &parse);
    if (!doc.isArray()) {
        result.error = i18n("PipeWire's answer could not be read.");
        return result;
    }
    QString current;
    QString configured;
    for (const QJsonValue &v : doc.array()) {
        const QJsonObject o = v.toObject();
        if (o.value(QStringLiteral("type")).toString() == QLatin1String("PipeWire:Interface:Metadata")
            && o.value(QStringLiteral("props")).toObject().value(QStringLiteral("metadata.name")).toString() == QLatin1String("default")) {
            for (const QJsonValue &m : o.value(QStringLiteral("metadata")).toArray()) {
                const QJsonObject e = m.toObject();
                if (e.value(QStringLiteral("key")).toString() == QLatin1String("default.video.source")) {
                    current = valueName(e.value(QStringLiteral("value")));
                } else if (e.value(QStringLiteral("key")).toString() == QLatin1String("default.configured.video.source")) {
                    configured = valueName(e.value(QStringLiteral("value")));
                }
            }
        }
    }
    for (const QJsonValue &v : doc.array()) {
        const QJsonObject o = v.toObject();
        if (o.value(QStringLiteral("type")).toString() != QLatin1String("PipeWire:Interface:Node")) {
            continue;
        }
        const QJsonObject info = o.value(QStringLiteral("info")).toObject();
        const QJsonObject props = info.value(QStringLiteral("props")).toObject();
        if (!props.value(QStringLiteral("media.class")).toString().startsWith(QLatin1String("Video/Source"))) {
            continue;
        }
        CameraNode n;
        n.id = o.value(QStringLiteral("id")).toInt();
        n.name = props.value(QStringLiteral("node.name")).toString();
        n.description = props.value(QStringLiteral("node.description")).toString();
        if (n.description.isEmpty()) {
            n.description = props.value(QStringLiteral("node.nick")).toString();
        }
        if (n.description.isEmpty()) {
            n.description = n.name;
        }
        n.state = info.value(QStringLiteral("state")).toString();
        n.v4l2Path = props.value(QStringLiteral("api.v4l2.path")).toString();
        if (n.v4l2Path.isEmpty() && props.value(QStringLiteral("object.path")).toString().startsWith(QLatin1String("v4l2:"))) {
            n.v4l2Path = props.value(QStringLiteral("object.path")).toString().mid(5);
        }
        n.api = !n.v4l2Path.isEmpty() ? QStringLiteral("v4l2")
            : (props.value(QStringLiteral("device.api")).toString() == QLatin1String("libcamera") || props.contains(QStringLiteral("api.libcamera.path")))
            ? QStringLiteral("libcamera")
            : QStringLiteral("other");
        n.isDefault = !n.name.isEmpty() && n.name == current;
        n.isConfigured = !n.name.isEmpty() && n.name == configured;
        result.cameras.append(n);
    }
    return result;
}

QString Sparky::Camera::setDefaultCamera(const QString &nodeName)
{
    // The node name goes into JSON by the JSON writer, so no character of it can end the string
    const QByteArray value = QJsonDocument(QJsonObject{{QStringLiteral("name"), nodeName}}).toJson(QJsonDocument::Compact);
    QByteArray out;
    QString error;
    run(QStringLiteral("pw-metadata"), {QStringLiteral("-n"), QStringLiteral("default"), QStringLiteral("0"), QStringLiteral("default.configured.video.source"), QString::fromUtf8(value), QStringLiteral("Spa:String:JSON")}, &out, &error);
    return error;
}
