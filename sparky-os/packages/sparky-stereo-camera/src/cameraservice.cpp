// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "cameraservice.h"

#include <KLocalizedString>

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>

using namespace Sparky::Camera;

QList<CameraInfo> Sparky::Camera::listCameras(QString *error)
{
    QList<CameraInfo> result;
    const NodeList nodes = listCameraNodes();
    *error = nodes.error;
    for (const CameraNode &n : nodes.cameras) {
        CameraInfo info;
        info.node = n;
        if (n.api == QLatin1String("v4l2")) {
            V4l2Camera device(n.v4l2Path);
            if (device.isOpen()) {
                info.card = device.card();
                info.busInfo = device.busInfo();
                info.key = cameraKey(info.busInfo, info.card);
            } else {
                info.openError = device.openError();
                info.note = V4l2Camera::explain({false, device.openError(), QStringLiteral("open")}, n.description);
            }
        } else {
            info.note = i18n("%1 is not a V4L2 camera, so its controls are not available here.", n.description);
        }
        result.append(info);
    }
    return result;
}

CameraInfo Sparky::Camera::findCamera(const QString &nodeName, QString *error)
{
    for (const CameraInfo &c : listCameras(error)) {
        if (c.node.name == nodeName) {
            return c;
        }
    }
    if (error->isEmpty()) {
        *error = i18n("No camera is called %1.", nodeName);
    }
    return {};
}

ApplyReport Sparky::Camera::applyChoice(const CameraInfo &camera)
{
    ApplyReport report;
    if (camera.key.isEmpty()) {
        return report;
    }
    const CameraChoice choice = loadChoice(camera.key);
    V4l2Camera device(camera.node.v4l2Path);
    if (!device.isOpen()) {
        report.messages << V4l2Camera::explain({false, device.openError(), QStringLiteral("open")}, camera.node.description);
        return report;
    }
    if (choice.hasMode) {
        const Result r = device.setMode(choice.mode);
        if (r.ok) {
            ++report.applied;
        } else {
            report.messages << i18n("%1: the saved size and format were not applied. ", camera.node.description) + V4l2Camera::explain(r, camera.node.description);
        }
    }
    const QList<Control> known = device.controls();
    for (auto it = choice.controls.cbegin(); it != choice.controls.cend(); ++it) {
        QString name = choice.controlNames.value(it.key());
        bool present = false;
        for (const Control &c : known) {
            if (c.id == it.key()) {
                present = true;
                name = c.name;
            }
        }
        if (!present) {
            report.messages << i18n("%1: the camera no longer lists the control %2.", camera.node.description, name);
            continue;
        }
        const Result r = device.setControl(it.key(), it.value());
        if (r.ok) {
            ++report.applied;
        } else {
            report.messages << i18n("%1: the saved value of %2 was not applied. ", camera.node.description, name) + V4l2Camera::explain(r, camera.node.description);
        }
    }
    return report;
}

QStringList Sparky::Camera::knownMachineNotes()
{
    // sparky-stereo-hardware's table: the references of the machine matched here that name a camera (a kernel quirk
    // for its USB transfers, say). The table's text is English; the page says it in the person's language.
    QProcess p;
    p.start(QStringLiteral("sparky-stereo-known-machines"), {QStringLiteral("--list")});
    if (!p.waitForStarted(2000) || !p.waitForFinished(5000) || p.exitCode() != 0) {
        return {};
    }
    QStringList notes;
    const QJsonObject doc = QJsonDocument::fromJson(p.readAllStandardOutput()).object();
    for (const QJsonValue &m : doc.value(QStringLiteral("matched")).toArray()) {
        for (const QJsonValue &r : m.toObject().value(QStringLiteral("references")).toArray()) {
            const QString id = r.toObject().value(QStringLiteral("id")).toString();
            if (id.startsWith(QLatin1String("uvc-"))) {
                notes << i18n("This computer's built-in camera has a known fault in how it sends pictures over USB. The system's kernel corrects it, so nothing needs to be done here.");
            }
        }
    }
    notes.removeDuplicates();
    return notes;
}
