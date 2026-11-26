// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

// sparky-stereo-camera: the page's engine as a command, for scripts, the tests and the unit that applies the saved
// choices when a camera is plugged in.

#include "cameraservice.h"
#include "packings.h"

#include <KLocalizedString>

#include <QCoreApplication>
#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <QTextStream>
#include <QTimer>

using namespace Sparky::Camera;

namespace
{
QTextStream out(stdout);
QTextStream err(stderr);

int fail(const QString &text, int code = 1)
{
    err << text << Qt::endl;
    return code;
}

QJsonObject sizeJson(Size s)
{
    return {{QStringLiteral("width"), s.width}, {QStringLiteral("height"), s.height}};
}

QJsonObject modeJson(const Mode &m)
{
    return {{QStringLiteral("format"), m.fourcc}, {QStringLiteral("width"), m.size.width}, {QStringLiteral("height"), m.size.height}, {QStringLiteral("fps"), m.fps}};
}

void print(const QJsonValue &v)
{
    out << QJsonDocument(v.isArray() ? QJsonDocument(v.toArray()) : QJsonDocument(v.toObject())).toJson(QJsonDocument::Indented);
}

int usage()
{
    err << "usage: sparky-stereo-camera list | default [NAME] | formats NAME | best NAME | mode NAME [FOURCC WxH FPS] | controls NAME"
           " | control NAME CONTROL [VALUE] | reset NAME | packing NAME [ID|list] | save NAME | apply [NAME] | watch\n"
           "A change on the device is saved for the camera too unless --no-save comes first.\n";
    return 2;
}

QJsonObject controlJson(const Control &c)
{
    QJsonArray menu;
    for (const auto &m : c.menu) {
        menu.append(QJsonObject{{QStringLiteral("index"), double(m.index)}, {QStringLiteral("text"), m.text}});
    }
    static const char *kinds[] = {"integer", "boolean", "menu", "integer-menu", "button", "other"};
    QJsonObject o{{QStringLiteral("id"), double(c.id)},
                  {QStringLiteral("name"), c.name},
                  {QStringLiteral("kind"), QString::fromLatin1(kinds[c.kind])},
                  {QStringLiteral("min"), double(c.minimum)},
                  {QStringLiteral("max"), double(c.maximum)},
                  {QStringLiteral("step"), double(c.step)},
                  {QStringLiteral("default"), double(c.defaultValue)},
                  {QStringLiteral("effectiveDefault"), double(effectiveDefault(c))},
                  {QStringLiteral("value"), double(c.value)},
                  {QStringLiteral("valueKnown"), c.valueKnown},
                  {QStringLiteral("flags"), double(c.flags)},
                  {QStringLiteral("inactive"), c.inactive},
                  {QStringLiteral("readOnly"), c.readOnly},
                  {QStringLiteral("grabbed"), c.grabbed},
                  {QStringLiteral("keep"), keepName(keepRule(c))},
                  {QStringLiteral("menu"), menu}};
    return o;
}

// The saved choice of a camera: its settings that differ from their default, each taken while it is active (choiceFromDevice)
void saveState(const CameraInfo &cam, V4l2Camera &dev, bool withMode)
{
    saveChoice(cam.key, choiceFromDevice(dev, loadChoice(cam.key), withMode));
}

void printReport(const ApplyReport &r)
{
    for (const QString &m : r.messages) {
        err << m << Qt::endl;
    }
    for (const QString &l : r.log) {
        out << l << Qt::endl;
    }
}

int cmdList()
{
    QString error;
    const QList<CameraInfo> cams = listCameras(&error);
    if (!error.isEmpty()) {
        return fail(error);
    }
    QJsonArray a;
    for (const CameraInfo &c : cams) {
        QJsonObject o{{QStringLiteral("name"), c.node.name}, {QStringLiteral("description"), c.node.description}, {QStringLiteral("default"), c.node.isDefault},
                      {QStringLiteral("configured"), c.node.isConfigured}, {QStringLiteral("api"), c.node.api}, {QStringLiteral("path"), c.node.v4l2Path},
                      {QStringLiteral("key"), c.key}, {QStringLiteral("note"), c.note}, {QStringLiteral("state"), c.node.state}};
        if (!c.key.isEmpty()) {
            V4l2Camera d(c.node.v4l2Path);
            if (d.isOpen()) {
                o.insert(QStringLiteral("mode"), modeJson(d.currentMode()));
            }
            const CameraChoice ch = loadChoice(c.key);
            o.insert(QStringLiteral("packing"), ch.packing.isEmpty() ? QStringLiteral("mono") : ch.packing);
        }
        a.append(o);
    }
    print(a);
    return 0;
}
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    KLocalizedString::setApplicationDomain("kcm_sparkystereo_camera");
    QStringList args = app.arguments().mid(1);
    bool save = true;
    if (!args.isEmpty() && args.first() == QLatin1String("--no-save")) {
        save = false;
        args.removeFirst();
    }
    if (args.isEmpty()) {
        return usage();
    }
    const QString verb = args.takeFirst();
    if (verb == QLatin1String("list")) {
        return cmdList();
    }
    if (verb == QLatin1String("watch")) {
        // Apply the saved choices to every camera now and again whenever the set of cameras changes (a plug-in). A camera is done
        // once its device was reached; one that PipeWire lists while its device does not open or answer yet (being plugged in,
        // going away, starting up) is tried again at every pass until it answers, and that is said once.
        QSet<QString> seen;
        QSet<QString> told;
        auto pass = [&seen, &told]() {
            QString error;
            const QList<CameraInfo> cams = listCameras(&error);
            if (!error.isEmpty()) {
                qWarning().noquote() << error;
                return;
            }
            QSet<QString> now;
            QSet<QString> waiting;
            for (const CameraInfo &c : cams) {
                // a camera unplugged and plugged in again between two passes can get its old id back, never its old serial
                const QString sig = c.node.name + QLatin1Char('@') + QString::number(c.node.serial ? c.node.serial : c.node.id);
                if (seen.contains(sig)) {
                    now.insert(sig);
                    continue;
                }
                const ApplyReport r = applyChoice(c);
                // a V4L2 camera whose device did not open, or opened and did not answer; a camera of another kind has nothing to apply
                const bool unreachable = c.key.isEmpty() ? c.openError != 0 : !r.reached;
                if (unreachable) {
                    waiting.insert(sig);
                    if (!told.contains(sig)) {
                        qWarning().noquote() << QStringLiteral("camera %1: not reached yet, tried again at the next pass: %2")
                                                    .arg(c.node.name, r.messages.isEmpty() ? c.note : r.messages.join(QLatin1Char(' ')));
                    }
                    continue;
                }
                now.insert(sig);
                for (const QString &m : r.messages) {
                    qWarning().noquote() << m;
                }
                for (const QString &l : r.log) {
                    qInfo().noquote() << l;
                }
                qInfo().noquote() << QStringLiteral("camera %1: %2 saved settings applied").arg(c.node.name).arg(r.applied);
            }
            seen = now;
            told = waiting;
        };
        pass();
        QTimer t;
        QObject::connect(&t, &QTimer::timeout, pass);
        t.start(2000);
        return app.exec();
    }
    QString error;
    if (verb == QLatin1String("default")) {
        if (args.isEmpty()) {
            for (const CameraInfo &c : listCameras(&error)) {
                if (c.node.isDefault) {
                    out << c.node.name << Qt::endl;
                    return 0;
                }
            }
            return error.isEmpty() ? fail(i18n("There is no default camera."), 3) : fail(error);
        }
        const CameraInfo c = findCamera(args.first(), &error);
        if (c.node.name.isEmpty()) {
            return fail(error);
        }
        const QString e = setDefaultCamera(c.node.name);
        return e.isEmpty() ? 0 : fail(e);
    }
    if (verb == QLatin1String("apply") && args.isEmpty()) {
        int bad = 0;
        for (const CameraInfo &c : listCameras(&error)) {
            const ApplyReport r = applyChoice(c);
            printReport(r);
            bad += r.messages.size();
        }
        return error.isEmpty() ? (bad ? 1 : 0) : fail(error);
    }
    if (args.isEmpty()) {
        return usage();
    }
    const CameraInfo cam = findCamera(args.takeFirst(), &error);
    if (cam.node.name.isEmpty()) {
        return fail(error);
    }
    if (verb == QLatin1String("apply")) {
        const ApplyReport r = applyChoice(cam);
        printReport(r);
        return r.ok() ? 0 : 1;
    }
    if (cam.key.isEmpty()) {
        return fail(cam.note);
    }
    V4l2Camera dev(cam.node.v4l2Path);
    if (!dev.isOpen()) {
        return fail(V4l2Camera::explain({false, dev.openError(), QStringLiteral("open")}, cam.node.description));
    }
    // a device that opens and does not answer (going away, still starting) is said, never answered with an empty list
    dev.currentMode();
    if (dev.lastError()) {
        return fail(V4l2Camera::explain({false, dev.lastError(), QStringLiteral("VIDIOC_G_FMT")}, cam.node.description));
    }
    if (verb == QLatin1String("best")) {
        // the mode this camera starts at when nobody chose one (ORDER 682), and the known machine's caveat that limits it
        const BestModeChoice best = bestModeFor(dev);
        QJsonObject o{{QStringLiteral("usb"), usbIdOf(dev.path())}, {QStringLiteral("allowedFormats"), QJsonArray::fromStringList(best.allowedFormats)}};
        if (best.mode) {
            o.insert(QStringLiteral("mode"), modeJson(*best.mode));
        } else {
            o.insert(QStringLiteral("note"), best.note);
        }
        print(o);
        return best.mode ? 0 : 1;
    }
    if (verb == QLatin1String("formats")) {
        QJsonArray fs;
        const QList<Format> formats = dev.formats();
        if (dev.lastError()) {
            return fail(V4l2Camera::explain({false, dev.lastError(), QStringLiteral("VIDIOC_ENUM_FMT")}, cam.node.description));
        }
        if (formats.isEmpty()) {
            return fail(i18n("%1 lists no picture format. It may be starting up or going away: try again, or plug it in again.", cam.node.description));
        }
        for (const Format &f : formats) {
            QJsonArray sizes;
            for (const SizeEntry &s : f.sizes) {
                QJsonObject so = sizeJson(s.size);
                if (s.stepwise) {
                    so.insert(QStringLiteral("max"), sizeJson(s.max));
                    so.insert(QStringLiteral("step"), sizeJson(s.step));
                }
                QJsonArray rates;
                for (double r : dev.frameRates(f.fourcc, s.size)) {
                    rates.append(r);
                }
                so.insert(QStringLiteral("rates"), rates);
                sizes.append(so);
            }
            fs.append(QJsonObject{{QStringLiteral("format"), f.fourcc}, {QStringLiteral("description"), f.description}, {QStringLiteral("compressed"), f.compressed}, {QStringLiteral("sizes"), sizes}});
        }
        print(fs);
        return 0;
    }
    if (verb == QLatin1String("mode")) {
        if (args.isEmpty()) {
            print(modeJson(dev.currentMode()));
            return 0;
        }
        const QStringList wh = args.value(1).split(QLatin1Char('x'));
        if (args.size() != 3 || wh.size() != 2) {
            return usage();
        }
        const Mode m{args.at(0), {wh[0].toInt(), wh[1].toInt()}, args.at(2).toDouble()};
        const Result r = dev.setMode(m);
        if (!r.ok) {
            return fail(V4l2Camera::explain(r, cam.node.description));
        }
        if (save) {
            saveState(cam, dev, true);
        }
        return 0;
    }
    if (verb == QLatin1String("controls")) {
        QJsonArray a;
        const QList<Control> controls = dev.controls();
        if (dev.lastError()) {
            return fail(V4l2Camera::explain({false, dev.lastError(), QStringLiteral("VIDIOC_QUERY_EXT_CTRL")}, cam.node.description));
        }
        for (const Control &c : controls) {
            a.append(controlJson(c));
        }
        print(a);
        return 0;
    }
    if (verb == QLatin1String("control")) {
        if (args.isEmpty()) {
            return usage();
        }
        const QList<Control> controls = dev.controls();
        QSet<quint32> wasInactive;
        for (const Control &c : controls) {
            if (c.inactive) {
                wasInactive.insert(c.id);
            }
        }
        for (const Control &c : controls) {
            if (c.name != args.first()) {
                continue;
            }
            if (args.size() == 1) {
                print(controlJson(c));
                return 0;
            }
            if (c.kind == Control::Other) {
                return fail(i18n("This page cannot change this kind of control (%1).", c.otherKind));
            }
            const Result r = dev.setControl(c.id, c.kind == Control::Button ? 1 : args.at(1).toLongLong());
            if (!r.ok) {
                return fail(V4l2Camera::explain(r, cam.node.description));
            }
            // a saved value that waited for this control's change (automatic white balance off) is set before the camera is saved
            for (const QString &l : applyWaiting(dev, loadChoice(cam.key), wasInactive)) {
                out << l << Qt::endl;
            }
            if (save) {
                saveState(cam, dev, false);
            }
            return 0;
        }
        return fail(i18n("%1 has no control called %2.", cam.node.description, args.first()));
    }
    if (verb == QLatin1String("reset")) {
        QStringList failed;
        const Result r = dev.resetControls(&failed);
        if (save) {
            saveState(cam, dev, false);
        }
        return r.ok ? 0 : fail(V4l2Camera::explain(r, cam.node.description) + QLatin1Char(' ') + failed.join(QStringLiteral(", ")));
    }
    if (verb == QLatin1String("packing")) {
        if (args.isEmpty()) {
            const QString p = loadChoice(cam.key).packing;
            out << (p.isEmpty() ? QStringLiteral("mono") : p) << Qt::endl;
            return 0;
        }
        if (args.first() == QLatin1String("list")) {
            for (const Packing &p : packings()) {
                out << p.id << '\t' << p.text << Qt::endl;
            }
            return 0;
        }
        bool known = false;
        for (const Packing &p : packings()) {
            known |= p.id == args.first();
        }
        if (!known) {
            return fail(i18n("%1 is not one of the packings. See: sparky-stereo-camera packing %2 list", args.first(), cam.node.name));
        }
        CameraChoice c = loadChoice(cam.key);
        c.packing = args.first() == QLatin1String("mono") ? QString() : args.first();
        saveChoice(cam.key, c);
        return 0;
    }
    if (verb == QLatin1String("save")) {
        saveState(cam, dev, false);
        return 0;
    }
    return usage();
}
