// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "cameraservice.h"

#include <KLocalizedString>

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QSet>

#include <cmath>
#include <linux/videodev2.h>

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

namespace
{
// One problem for each camera and cause (Daniel 2026-11-02: a failure that must be kept goes to the one engine). The key is the
// cause and the camera; the engine keeps it once, however often the choice fails, and the next successful apply clears it.
QString problemKey(const QString &cause, const QString &cameraKey)
{
    QString key = cause + QLatin1Char(':') + cameraKey;
    for (QChar &c : key) {
        if (!c.isLetterOrNumber() && QStringLiteral("_@+-.:").indexOf(c) < 0) {
            c = QLatin1Char('_');
        }
    }
    return key.left(120);
}

void keepProblem(const QString &key, const QString &message, const QStringList &arguments)
{
    QProcess::execute(QStringLiteral("sparky-stereo-problems"),
                      QStringList{QStringLiteral("keep"), QStringLiteral("--person"), QStringLiteral("--quiet"), QStringLiteral("sparky-stereo-camera"), key, message} + arguments);
}

void clearProblem(const QString &key)
{
    QProcess::execute(QStringLiteral("sparky-stereo-problems"), {QStringLiteral("clear"), QStringLiteral("sparky-stereo-camera"), key});
}

QString modeText(const Mode &m)
{
    return QStringLiteral("%1 %2x%3 %4 fps").arg(m.fourcc).arg(m.size.width).arg(m.size.height).arg(m.fps);
}

bool sameMode(const Mode &a, const Mode &b)
{
    return a.fourcc == b.fourcc && a.size == b.size && (a.fps <= 0 || b.fps <= 0 || std::abs(a.fps - b.fps) < 0.01);
}
}

ApplyReport Sparky::Camera::applyChoice(const CameraInfo &camera)
{
    ApplyReport report;
    if (camera.key.isEmpty()) {
        return report;
    }
    CameraChoice choice = loadChoice(camera.key);
    V4l2Camera device(camera.node.v4l2Path);
    if (!device.isOpen()) {
        // The camera is not there to be set (plugged out, held open elsewhere): not a saved choice that fails
        report.messages << V4l2Camera::explain({false, device.openError(), QStringLiteral("open")}, camera.node.description);
        return report;
    }
    const QString name = camera.node.description;
    const bool oldEntry = choice.exists && choice.version < StoreVersion;
    bool refused = false;
    bool cleaned = false;
    QList<quint32> stillInactive;
    QList<quint32> atDefault; // an old entry's value equal to what the camera holds as its default: 0.1.3 never saves one

    QSet<quint32> layout;
    for (const Control &c : device.controls()) {
        if (c.flags & V4L2_CTRL_FLAG_MODIFY_LAYOUT) {
            layout.insert(c.id);
        }
    }
    QList<QPair<quint32, qint64>> layoutValues;
    QList<QPair<quint32, qint64>> values;
    for (auto it = choice.controls.cbegin(); it != choice.controls.cend(); ++it) {
        (layout.contains(it.key()) ? layoutValues : values).append({it.key(), it.value()});
    }

    const auto handle = [&](const QList<V4l2Camera::SetOutcome> &outcomes) {
        for (const V4l2Camera::SetOutcome &o : outcomes) {
            const QString controlName = o.control ? o.control->name : choice.controlNames.value(o.id, QString::number(o.id));
            const QString key = problemKey(QStringLiteral("control-%1").arg(o.id), camera.key);
            switch (o.state) {
            case V4l2Camera::SetOutcome::Applied:
                ++report.applied;
                clearProblem(key);
                if (oldEntry && o.control && choice.controls.value(o.id) == effectiveDefault(*o.control)) {
                    atDefault.append(o.id);
                }
                break;
            case V4l2Camera::SetOutcome::Refused: {
                refused = true;
                const QString why = V4l2Camera::explain(o.result, name);
                report.messages << i18n("%1: the saved value of %2 was not applied. ", name, controlName) + why;
                keepProblem(key, QStringLiteral("LOCAL3"), {name, controlName, why});
                break;
            }
            case V4l2Camera::SetOutcome::Missing:
                report.messages << i18n("%1: the camera no longer lists the control %2.", name, controlName);
                keepProblem(key, QStringLiteral("LOCAL4"), {name, controlName});
                break;
            case V4l2Camera::SetOutcome::NotSetting:
                // the camera says this control is not a setting (a movement, an action, read-only, without a range...): never kept
                clearProblem(key);
                choice.controls.remove(o.id);
                choice.controlNames.remove(o.id);
                cleaned = true;
                report.log << QStringLiteral("camera %1: removed the saved value of %2 (%3): not a setting")
                                  .arg(camera.node.name, controlName, keepName(keepRule(*o.control)));
                break;
            case V4l2Camera::SetOutcome::Inactive:
                // waiting for its governing control: not a failure (an earlier version may have kept a problem for it)
                clearProblem(key);
                stillInactive.append(o.id);
                break;
            }
        }
    };

    handle(device.setControls(layoutValues));
    const QString formatKey = problemKey(QStringLiteral("format"), camera.key);
    if (choice.hasMode) {
        const Result r = device.setMode(choice.mode);
        if (r.ok) {
            ++report.applied;
            clearProblem(formatKey);
        } else {
            refused = true;
            const QString why = V4l2Camera::explain(r, name);
            report.messages << i18n("%1: the saved size and format were not applied. ", name) + why;
            keepProblem(formatKey, QStringLiteral("LOCAL2"), {name, why});
        }
    } else {
        // Nobody chose a mode for this camera: it starts at its best one (ORDER 682). The person chose nothing, so a camera that
        // cannot take it now (another program streams with a mode of its own) is a line in the journal, not a problem.
        const BestModeChoice best = bestModeFor(device);
        if (!best.mode) {
            report.log << QStringLiteral("camera %1: no best mode: %2").arg(camera.node.name, best.note);
        } else if (!sameMode(device.currentMode(), *best.mode)) {
            const Result r = device.setMode(*best.mode);
            report.log << (r.ok ? QStringLiteral("camera %1: best mode %2%3").arg(camera.node.name, modeText(*best.mode),
                                                                                  best.allowedFormats.isEmpty() ? QString() : QStringLiteral(" (this machine: %1 only)").arg(best.allowedFormats.join(QLatin1Char(','))))
                                : QStringLiteral("camera %1: the best mode %2 was not set: %3").arg(camera.node.name, modeText(*best.mode), V4l2Camera::explain(r, name)));
        }
    }
    handle(device.setControls(values));

    if (oldEntry) {
        if (refused) {
            report.log << QStringLiteral("camera %1: the entry written by an earlier version is cleaned at the next apply without a refusal").arg(camera.node.name);
        } else {
            // 0.1.0 to 0.1.2 saved every control whose reading differed from its default. A value of a control that is still inactive
            // once every saved governing control has its value was read while that control was not in use: never the person's setting.
            for (quint32 id : std::as_const(stillInactive)) {
                report.log << QStringLiteral("camera %1: removed the saved value %2 of %3: it was saved while the control was inactive")
                                  .arg(camera.node.name)
                                  .arg(choice.controls.value(id))
                                  .arg(choice.controlNames.value(id, QString::number(id)));
                choice.controls.remove(id);
                choice.controlNames.remove(id);
            }
            for (quint32 id : std::as_const(atDefault)) {
                report.log << QStringLiteral("camera %1: removed the saved value %2 of %3: it is what the camera holds as its default")
                                  .arg(camera.node.name)
                                  .arg(choice.controls.value(id))
                                  .arg(choice.controlNames.value(id, QString::number(id)));
                choice.controls.remove(id);
                choice.controlNames.remove(id);
            }
            choice.version = StoreVersion;
            cleaned = true;
        }
    } else {
        for (quint32 id : std::as_const(stillInactive)) {
            report.log << QStringLiteral("camera %1: %2 is inactive now; its saved value waits for it").arg(camera.node.name, choice.controlNames.value(id, QString::number(id)));
        }
    }
    if (cleaned && choice.exists) {
        saveChoice(camera.key, choice);
    }
    return report;
}

CameraChoice Sparky::Camera::choiceFromDevice(V4l2Camera &device, const CameraChoice &stored, bool withMode)
{
    CameraChoice c = stored;
    if (withMode) {
        c.hasMode = true;
        c.mode = device.currentMode();
    }
    c.controls.clear();
    c.controlNames.clear();
    for (const Control &ctl : device.controls()) {
        if (!isSetting(ctl)) {
            continue;
        }
        if (ctl.inactive || ctl.grabbed || !ctl.valueKnown) {
            // not changeable by the person now: what the camera reports is not their setting; keep the one saved while it was
            if (stored.version >= StoreVersion && stored.controls.contains(ctl.id)) {
                c.controls.insert(ctl.id, stored.controls.value(ctl.id));
                c.controlNames.insert(ctl.id, ctl.name);
            }
            continue;
        }
        if (ctl.value != effectiveDefault(ctl)) {
            c.controls.insert(ctl.id, ctl.value);
            c.controlNames.insert(ctl.id, ctl.name);
        }
    }
    c.version = StoreVersion;
    return c;
}

QString Sparky::Camera::usbIdOf(const QString &v4l2Path)
{
    // /sys/class/video4linux/videoN/device is the USB interface; its parent is the USB device with idVendor and idProduct.
    // SPARKY_STEREO_CAMERA_SYSFS replaces /sys for the rig's virtual cameras.
    const QString root = qEnvironmentVariable("SPARKY_STEREO_CAMERA_SYSFS", QStringLiteral("/sys"));
    const QString device = QFileInfo(root + QStringLiteral("/class/video4linux/") + QFileInfo(v4l2Path).fileName() + QStringLiteral("/device")).canonicalFilePath();
    if (device.isEmpty()) {
        return {};
    }
    const QString usb = QFileInfo(device).absolutePath();
    QFile vendor(usb + QStringLiteral("/idVendor"));
    QFile product(usb + QStringLiteral("/idProduct"));
    if (!vendor.open(QIODevice::ReadOnly) || !product.open(QIODevice::ReadOnly)) {
        return {};
    }
    return QString::fromLatin1(vendor.readAll().trimmed()).toLower() + QLatin1Char(':') + QString::fromLatin1(product.readAll().trimmed()).toLower();
}

QJsonArray Sparky::Camera::knownMachineReferences()
{
    QProcess p;
    p.start(QStringLiteral("sparky-stereo-known-machines"), {QStringLiteral("--list")});
    if (!p.waitForStarted(2000) || !p.waitForFinished(5000) || p.exitCode() != 0) {
        return {};
    }
    QJsonArray references;
    const QJsonObject doc = QJsonDocument::fromJson(p.readAllStandardOutput()).object();
    for (const QJsonValue &m : doc.value(QStringLiteral("matched")).toArray()) {
        for (const QJsonValue &r : m.toObject().value(QStringLiteral("references")).toArray()) {
            references.append(r);
        }
    }
    return references;
}

QStringList Sparky::Camera::machineFormatsFor(const QJsonArray &references, const QString &usbId)
{
    QStringList formats;
    if (usbId.isEmpty()) {
        return formats;
    }
    for (const QJsonValue &v : references) {
        const QJsonObject r = v.toObject();
        if (r.value(QStringLiteral("owner")).toString() != QLatin1String("sparky-stereo-camera")
            || r.value(QStringLiteral("camera")).toString().toLower() != usbId) {
            continue;
        }
        for (const QJsonValue &f : r.value(QStringLiteral("formats")).toArray()) {
            if (f.isString() && !formats.contains(f.toString())) {
                formats << f.toString();
            }
        }
    }
    return formats;
}

BestModeChoice Sparky::Camera::bestModeFor(V4l2Camera &device)
{
    BestModeChoice choice;
    choice.allowedFormats = machineFormatsFor(knownMachineReferences(), usbIdOf(device.path()));
    const QList<ModeCandidate> candidates = device.modeCandidates();
    choice.mode = bestMode(candidates, choice.allowedFormats);
    if (!choice.mode) {
        choice.note = candidates.isEmpty() ? QStringLiteral("the camera lists no mode")
                                           : QStringLiteral("this machine's table names formats the camera does not offer (%1); the camera keeps its own mode")
                                                 .arg(choice.allowedFormats.join(QLatin1Char(',')));
    }
    return choice;
}

QStringList Sparky::Camera::knownMachineNotes()
{
    // sparky-stereo-hardware's table: the references of the machine matched here that name a camera (a kernel quirk
    // for its USB transfers, say). The table's text is English; the page says it in the person's language.
    QStringList notes;
    for (const QJsonValue &r : knownMachineReferences()) {
        const QString id = r.toObject().value(QStringLiteral("id")).toString();
        if (id.startsWith(QLatin1String("uvc-"))) {
            notes << i18n("This computer's built-in camera has a known fault in how it sends pictures over USB. The system's kernel corrects it, so nothing needs to be done here.");
        }
    }
    notes.removeDuplicates();
    return notes;
}
