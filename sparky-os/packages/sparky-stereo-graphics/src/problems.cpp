// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "problems.h"
#include "launchwatch.h"

#include <sparky-stereo-problems.h>

#include <KLocalizedString>

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTextStream>

using namespace Qt::StringLiterals;

namespace SparkyGraphics
{

bool Problem::isEmpty() const
{
    return kind.isEmpty();
}

bool Problem::isDeath() const
{
    return kind == u"app-died"_s;
}

bool Problem::isPaint() const
{
    return kind == u"paint"_s;
}

bool Problem::isChoice() const
{
    return !system && !kind.isEmpty() && kind != u"record-write"_s && kind != u"systemd-reload"_s && !isDeath() && !isPaint();
}

namespace Problems
{

// The problems are kept by the edition's one engine, sparky-stereo-problems (ORDER 350): the machine's in its
// /var/lib store, the person's in their own; these name the stores, and the engine's root for a test's ROOT
QString systemDir(const QString &root)
{
    return QDir::cleanPath(root + u"/var/lib/sparky-stereo-problems"_s);
}

QString userDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation) + u"/sparky-stereo-problems"_s;
}

static const char s_package[] = "sparky-stereo-graphics";

// the engine's scope of a store, and its root (SPARKY_STEREO_ROOT) for a machine store under a test's root
static int scopeOf(const QString &dir)
{
    if (dir == userDir()) {
        return SSP_PERSON;
    }
    const QString root = dir.chopped(QStringLiteral("/var/lib/sparky-stereo-problems").size());
    if (root.isEmpty() || root == u"/"_s) {
        qunsetenv("SPARKY_STEREO_ROOT");
    } else {
        qputenv("SPARKY_STEREO_ROOT", root.toUtf8());
    }
    return SSP_MACHINE;
}

static QString engineError()
{
    return QString::fromUtf8(ssp_error());
}

Problem fromResolution(const QString &key, const Resolution &resolution, const QList<Gpu> &gpus, const QString &root, const ProfileReading &profile)
{
    Problem problem;
    if (resolution.problem.isEmpty()) {
        return problem;
    }
    problem.key = key;
    problem.kind = resolution.problem;
    problem.requested = resolution.requested;
    if (resolution.requestedIndex >= 0 && resolution.requestedIndex < gpus.size()) {
        const Gpu &gpu = gpus.at(resolution.requestedIndex);
        problem.gpu = gpu.name;
        problem.detail = problem.kind == u"gpu-not-allowed"_s ? gpu.renderNode : gpu.driver;
    }
    if (problem.kind == u"gpu-missing"_s && problem.requested.startsWith(u"pci-"_s)) {
        // The kernel lists the device on the PCI bus whether or not a graphics driver gave it a DRM device: when it is
        // there, the GPU is in the computer and its driver is what is missing (an NVIDIA card whose driver did not install)
        // A display controller (PCI base class 03, the kernel's class file) at that address; another kind of device there
        // (a disk controller that took the slot) means the GPU is not in the computer
        const QString device = QDir::cleanPath(root + u"/sys/bus/pci/devices/"_s + problem.requested.mid(4));
        QFile pciClass(device + u"/class"_s);
        if (pciClass.open(QIODevice::ReadOnly) && pciClass.readAll().trimmed().startsWith("0x03")) {
            problem.kind = u"gpu-no-driver"_s;
            problem.detail = QFileInfo(device + u"/driver"_s).symLinkTarget().section(u'/', -1);
        }
    }
    if (problem.kind == u"profile-unreadable"_s) {
        problem.detail = profile.error.isEmpty() ? u"not-read"_s : profile.error;
        problem.extra = profile.detail;
    }
    for (const Gpu &gpu : gpus) {
        // the desktop can be drawn by any GPU that renders; a program also needs the account to open it
        if (key == u"main-gpu"_s ? gpu.canRender : gpu.usable()) {
            problem.alternatives.append({gpu.id, gpu.name});
        }
    }
    return problem;
}

Problem fromDeath(const QString &appName, const QString &appId, const QString &app, const QString &how, int number, const QString &word,
                  const QString &output, int gpuIndex, const QList<Gpu> &gpus, const QList<int> &instead)
{
    Problem problem;
    problem.key = LaunchWatch::keyOf(appName);
    problem.kind = u"app-died"_s;
    problem.app = app.isEmpty() ? appName : app;
    problem.command = appId;
    problem.detail = how;
    problem.extra = word;
    problem.status = number;
    problem.output = output;
    if (gpuIndex >= 0 && gpuIndex < gpus.size()) {
        problem.requested = gpus.at(gpuIndex).id;
        problem.gpu = gpus.at(gpuIndex).name;
    }
    for (int index : instead) {
        if (index >= 0 && index < gpus.size() && index != gpuIndex) {
            problem.alternatives.append({gpus.at(index).id, gpus.at(index).name});
        }
    }
    return problem;
}

Problem fromPaint(const QString &key, const QString &target, const QString &app, const QString &way, const QString &reason, const QString &words)
{
    Problem problem;
    problem.key = key;
    problem.kind = u"paint"_s;
    problem.requested = way;
    problem.detail = reason;
    problem.extra = words;
    problem.app = app;
    problem.command = target;
    return problem;
}

QString profileError(const QString &error, const QString &detail)
{
    if (error == u"no-bus"_s) {
        return i18nc("@info why the power profile could not be read", "the system bus cannot be reached");
    }
    if (error == u"no-answer"_s) {
        return detail.isEmpty() ? i18nc("@info why the power profile could not be read", "power-profiles-daemon did not answer")
                                : i18nc("@info why the power profile could not be read, %1 is the error", "power-profiles-daemon did not answer (%1)", detail);
    }
    if (error == u"unknown"_s) {
        return i18nc("@info why the power profile could not be read, %1 is a profile name",
                     "power-profiles-daemon named a profile this page does not know, %1",
                     detail);
    }
    if (error == u"override"_s) {
        return i18nc("@info why the power profile could not be read, %1 is a value", "SPARKY_STEREO_POWER_PROFILE is %1, which is not a power profile", detail);
    }
    return i18nc("@info why the power profile could not be read", "power-profiles-daemon is not running");
}

static QJsonObject toJson(const Problem &p)
{
    QJsonArray alternatives;
    for (const Alternative &a : p.alternatives) {
        alternatives.append(QJsonObject{{u"id"_s, a.id}, {u"name"_s, a.name}});
    }
    return QJsonObject{
        {u"key"_s, p.key},
        {u"kind"_s, p.kind},
        {u"requested"_s, p.requested},
        {u"gpu"_s, p.gpu},
        {u"detail"_s, p.detail},
        {u"extra"_s, p.extra},
        {u"alternatives"_s, alternatives},
        {u"time"_s, p.time},
        {u"command"_s, p.command},
        {u"status"_s, p.status},
        {u"output"_s, p.output},
        {u"app"_s, p.app},
    };
}

static Problem fromJson(const QJsonObject &o)
{
    Problem p;
    p.key = o.value(u"key"_s).toString();
    p.kind = o.value(u"kind"_s).toString();
    p.requested = o.value(u"requested"_s).toString();
    p.gpu = o.value(u"gpu"_s).toString();
    p.detail = o.value(u"detail"_s).toString();
    p.extra = o.value(u"extra"_s).toString();
    for (const QJsonValue &v : o.value(u"alternatives"_s).toArray()) {
        p.alternatives.append({v.toObject().value(u"id"_s).toString(), v.toObject().value(u"name"_s).toString()});
    }
    p.time = o.value(u"time"_s).toString();
    p.command = o.value(u"command"_s).toString();
    p.status = o.value(u"status"_s).toInt();
    p.output = o.value(u"output"_s).toString();
    p.app = o.value(u"app"_s).toString();
    return p;
}

// the action's label lives in the engine's records only: kept here for the message extraction (Messages.sh, xgettext),
// so the .po files the catalogs are built from keep it
[[maybe_unused]] static QString extractedLabels()
{
    return i18nc("@action:button", "Open Graphics settings") + i18nc("@action:button", "Paint on the processor");
}

static QString ctx(const char *context, const char *text)
{
    return QString::fromUtf8(context) + u'|' + QString::fromUtf8(text);
}

static QString addressOf(const QString &id)
{
    return id.startsWith(u"pci-"_s) ? id.mid(4) : id;
}

static QJsonArray kindArg(const QString &key)
{
    const char *k = "@item kind of program inside a sentence: The GPU you chose for %1";
    const char *word = key == u"players"_s ? "players" : key == u"games"_s ? "games" : key == u"browsers"_s ? "browsers" : "other programs";
    return QJsonArray{ctx(k, word)};
}

static QJsonArray profileArg(const QString &error, const QString &detail)
{
    const char *c = "@info why the power profile could not be read";
    if (error == u"no-bus"_s) {
        return QJsonArray{ctx(c, "the system bus cannot be reached")};
    }
    if (error == u"no-answer"_s) {
        return detail.isEmpty() ? QJsonArray{ctx(c, "power-profiles-daemon did not answer")}
                                : QJsonArray{ctx("@info why the power profile could not be read, %1 is the error", "power-profiles-daemon did not answer (%1)"), detail};
    }
    if (error == u"unknown"_s) {
        return QJsonArray{ctx("@info why the power profile could not be read, %1 is a profile name", "power-profiles-daemon named a profile this page does not know, %1"),
                          detail};
    }
    if (error == u"override"_s) {
        return QJsonArray{ctx("@info why the power profile could not be read, %1 is a value", "SPARKY_STEREO_POWER_PROFILE is %1, which is not a power profile"), detail};
    }
    return QJsonArray{ctx(c, "power-profiles-daemon is not running")};
}

// Why painting on the graphics card cannot be used, as a message inside the sentence
static QJsonArray paintArg(const Problem &p)
{
    const char *c = "@info why windows cannot be painted on the graphics card";
    if (p.detail == u"no-gpu"_s) {
        return QJsonArray{ctx(c, "this computer has no graphics processor that can draw now")};
    }
    if (p.detail == u"qt"_s) {
        return QJsonArray{ctx(c, "the installed Qt cannot paint on the graphics card")};
    }
    if (p.detail == u"no-opengl"_s) {
        return QJsonArray{ctx(c, "this session has no OpenGL")};
    }
    if (p.detail == u"software"_s) {
        return QJsonArray{ctx("@info why windows cannot be painted on the graphics card, %1 is a renderer's name", "the OpenGL of this session is drawn by the processor (%1)"),
                          p.extra};
    }
    if (p.detail == u"library"_s) {
        return QJsonArray{ctx("@info why windows cannot be painted on the graphics card, %1 is the error", "Qt's OpenGL library could not be loaded (%1)"), p.extra};
    }
    return QJsonArray{ctx("@info why windows cannot be painted on the graphics card, %1 is the error", "the drawing surface could not be made (%1)"), p.extra};
}

static QString paintText(const Problem &p)
{
    const char *c = "@info why windows cannot be painted on the graphics card";
    if (p.detail == u"no-gpu"_s) {
        return i18nc(c, "this computer has no graphics processor that can draw now");
    }
    if (p.detail == u"qt"_s) {
        return i18nc(c, "the installed Qt cannot paint on the graphics card");
    }
    if (p.detail == u"no-opengl"_s) {
        return i18nc(c, "this session has no OpenGL");
    }
    if (p.detail == u"software"_s) {
        return i18nc("@info why windows cannot be painted on the graphics card, %1 is a renderer's name", "the OpenGL of this session is drawn by the processor (%1)", p.extra);
    }
    if (p.detail == u"library"_s) {
        return i18nc("@info why windows cannot be painted on the graphics card, %1 is the error", "Qt's OpenGL library could not be loaded (%1)", p.extra);
    }
    return i18nc("@info why windows cannot be painted on the graphics card, %1 is the error", "the drawing surface could not be made (%1)", p.extra);
}

// The kind a paint problem without a program belongs to, from its key ("paint-other")
static QString paintKind(const Problem &p)
{
    return p.key.mid(6);
}

// How a program stopped, as a message inside the sentence ([KEY, ARG...], like profileArg)
static QJsonArray howArg(const Problem &p)
{
    if (p.detail == u"crash"_s) {
        return QJsonArray{ctx("@info how a program stopped, %1 is a signal number", "it crashed (signal %1)"), QString::number(p.status)};
    }
    if (p.detail == u"exit"_s) {
        return QJsonArray{ctx("@info how a program stopped, %1 is an exit status", "it exited with status %1"), QString::number(p.status)};
    }
    return QJsonArray{ctx("@info how a program stopped, %1 is the word systemd gives the result", "systemd reports %1"), p.extra};
}

static QString howText(const Problem &p)
{
    if (p.detail == u"crash"_s) {
        return i18nc("@info how a program stopped, %1 is a signal number", "it crashed (signal %1)", p.status);
    }
    if (p.detail == u"exit"_s) {
        return i18nc("@info how a program stopped, %1 is an exit status", "it exited with status %1", p.status);
    }
    return i18nc("@info how a program stopped, %1 is the word systemd gives the result", "systemd reports %1", p.extra);
}

Sentences sentences(const Problem &p)
{
    if (p.isDeath()) {
        Sentences d;
        d.key = ctx("@info %1 is a program, %2 a GPU name, %3 says how it stopped", "%1 stopped right after it started on %2: %3.");
        d.args = QJsonArray{p.app, p.gpu, howArg(p)};
        d.more.append(QJsonArray{ctx("@info what to do",
                                     "It was not started again on another GPU. If this GPU is the cause, choose another one for it below, or in System Settings, Graphics.")});
        return d;
    }
    if (p.isPaint()) {
        Sentences d;
        d.key = ctx("@info %1 is a program or a kind of program, %2 says why",
                    "Painting on the graphics card cannot be used for %1: %2. The windows are painted on the processor.");
        d.args = p.app.isEmpty() ? QJsonArray{kindArg(paintKind(p)), paintArg(p)} : QJsonArray{p.app, paintArg(p)};
        d.more.append(QJsonArray{ctx("@info what to do",
                                     "Choose On the processor for it in System Settings, Graphics, or repair the graphics driver and start the program again.")});
        return d;
    }
    // the same sentences as message(), named by their catalog keys (CONTEXT|MSGID of this package's .po files), so the
    // engine says them in each reader's language; autotests/enginetextstest.sh checks the two agree
    const bool main = p.key == u"main-gpu"_s;
    const QJsonArray kind = kindArg(p.key);
    const QString address = addressOf(p.requested);
    Sentences s;
    auto todo = [&s](const char *text) {
        s.more.append(QJsonArray{ctx("@info what to do", text)});
    };
    if (p.kind == u"gpu-missing"_s) {
        s.key = main ? ctx("@info %1 is a PCI address", "The GPU you chose to draw the desktop, at PCI address %1, is not in this computer now.")
                     : ctx("@info %1 is a kind of program, %2 a PCI address", "The GPU you chose for %1, at PCI address %2, is not in this computer now.");
        s.args = main ? QJsonArray{address} : QJsonArray{kind, address};
        todo("Put the GPU back, or choose another GPU in System Settings, Graphics.");
    } else if (p.kind == u"gpu-no-driver"_s) {
        if (p.detail.isEmpty()) {
            s.key = main ? ctx("@info %1 is a PCI address", "The GPU you chose to draw the desktop, at PCI address %1, is in this computer, but no graphics driver is loaded for it.")
                         : ctx("@info %1 is a kind of program, %2 a PCI address",
                               "The GPU you chose for %1, at PCI address %2, is in this computer, but no graphics driver is loaded for it.");
            s.args = main ? QJsonArray{address} : QJsonArray{kind, address};
        } else {
            s.key = main ? ctx("@info %1 is a PCI address, %2 a kernel driver",
                               "The GPU you chose to draw the desktop, at PCI address %1, is in this computer, but its driver, %2, gives it no graphics device.")
                         : ctx("@info %1 is a kind of program, %2 a PCI address, %3 a kernel driver",
                               "The GPU you chose for %1, at PCI address %2, is in this computer, but its driver, %3, gives it no graphics device.");
            s.args = main ? QJsonArray{address, p.detail} : QJsonArray{kind, address, p.detail};
        }
        todo("Install or repair its driver, or choose another GPU in System Settings, Graphics.");
    } else if (p.kind == u"gpu-cannot-render"_s) {
        const QJsonArray why{ctx("@info why a GPU cannot draw, %1 is a kernel driver", "its driver, %1, gives it no render node"), p.detail};
        s.key = main ? ctx("@info %1 is a GPU name, %2 says why", "The GPU you chose to draw the desktop, %1, cannot draw now: %2.")
                     : ctx("@info %1 is a kind of program, %2 a GPU name, %3 says why", "The GPU you chose for %1, %2, cannot draw now: %3.");
        s.args = main ? QJsonArray{p.gpu, why} : QJsonArray{kind, p.gpu, why};
        todo("Choose a GPU that can draw in System Settings, Graphics.");
    } else if (p.kind == u"gpu-not-allowed"_s) {
        s.key = ctx("@info %1 is a kind of program, %2 a GPU name, %3 a device file", "The GPU you chose for %1, %2, cannot be used by your account: %3 cannot be opened.");
        s.args = QJsonArray{kind, p.gpu, p.detail};
        todo("Add your account to the render group (sudo adduser $USER render) and log in again, or choose another GPU in System Settings, Graphics.");
    } else if (p.kind == u"kind-missing"_s) {
        s.key = p.requested == u"integrated"_s
            ? ctx("@info %1 is a kind of program", "You chose the integrated GPU for %1, and this computer has none that can draw now.")
            : ctx("@info %1 is a kind of program", "You chose the discrete GPU for %1, and this computer has none that can draw now.");
        s.args = QJsonArray{kind};
        todo("Choose another GPU in System Settings, Graphics.");
    } else if (p.kind == u"profile-unreadable"_s) {
        s.key = ctx("@info %1 is a kind of program, %2 says why", "The GPU for %1 follows the power profile, and the power profile could not be read: %2.");
        s.args = QJsonArray{kind, profileArg(p.detail, p.extra)};
        todo("Start power-profiles-daemon (sudo systemctl start power-profiles-daemon), or choose a GPU in System Settings, Graphics.");
    } else if (p.kind == u"record-write"_s) {
        s.key = ctx("@info %1 is a file",
                    "The machine's GPU record, %1, could not be written. Until it is, Automatic treats this computer as not measured. Run: sudo "
                    "sparky-stereo-gpu-record --apply-known");
        s.args = QJsonArray{p.detail};
    } else if (p.kind == u"systemd-reload"_s) {
        s.key = ctx("@info %1 is an exit status",
                    "systemd could not reload its units after the Graphics page was installed (exit status %1). The boot service that writes the "
                    "machine's GPU record may not start. Run: sudo systemctl daemon-reload");
        s.args = QJsonArray{QString::number(p.status)};
    } else {
        s.key = ctx("@info %1 is a file", "A kept problem of the Graphics page cannot be read: %1.");
        s.args = QJsonArray{p.file};
    }
    if (main && p.isChoice()) {
        s.more.append(QJsonArray{ctx("@info", "At this login the desktop draws on the GPU the system picks.")});
    }
    return s;
}

bool keep(Problem problem, const QString &dir)
{
    // the same problem kept again keeps its first time and its hide (the engine), so it is shown once
    const int scope = scopeOf(dir);
    const Sentences s = sentences(problem);
    QJsonArray actions;
    if (problem.isDeath()) {
        // the other GPUs are only ever the person's explicit choice, for this program only (its desktop entry's own key)
        for (const Alternative &gpu : problem.alternatives) {
            actions.append(QJsonObject{{u"id"_s, QString(u"use:"_s + gpu.id)},
                                       {u"label"_s, QJsonArray{ctx("@action:button %1 is a GPU name", "Use %1"), gpu.name}},
                                       {u"command"_s, QJsonArray{u"sparky-stereo-gpu-env"_s, u"--use-app"_s, problem.command, gpu.id}}});
        }
        actions.append(QJsonObject{{u"id"_s, u"open"_s},
                                   {u"label"_s, QJsonArray{ctx("@action:button", "Open Graphics settings")}},
                                   {u"command"_s, QJsonArray{u"systemsettings"_s, u"kcm_sparkystereo_graphics"_s}}});
    } else if (problem.isPaint()) {
        // the processor is offered as the person's explicit choice for this program or kind; nothing is changed without it
        // (a program without a menu entry has no choice of its own to save: the page is where its kind is chosen)
        if (!problem.command.isEmpty()) {
            actions.append(QJsonObject{{u"id"_s, u"paint:cpu"_s},
                                       {u"label"_s, QJsonArray{ctx("@action:button", "Paint on the processor")}},
                                       {u"command"_s, QJsonArray{u"sparky-stereo-gpu-env"_s, u"--use-paint"_s, problem.command, u"cpu"_s}}});
        }
        actions.append(QJsonObject{{u"id"_s, u"open"_s},
                                   {u"label"_s, QJsonArray{ctx("@action:button", "Open Graphics settings")}},
                                   {u"command"_s, QJsonArray{u"systemsettings"_s, u"kcm_sparkystereo_graphics"_s}}});
    } else if (problem.isChoice()) {
        // the other GPUs are only ever the person's explicit choice: "Use NAME", which saves that GPU as the choice
        for (const Alternative &gpu : problem.alternatives) {
            if (gpu.id != problem.requested) {
                actions.append(QJsonObject{{u"id"_s, QString(u"use:"_s + gpu.id)},
                                           {u"label"_s, QJsonArray{ctx("@action:button %1 is a GPU name", "Use %1"), gpu.name}},
                                           {u"command"_s, QJsonArray{u"sparky-stereo-gpu-env"_s, u"--use"_s, problem.key, gpu.id}}});
            }
        }
        actions.append(QJsonObject{{u"id"_s, u"open"_s},
                                   {u"label"_s, QJsonArray{ctx("@action:button", "Open Graphics settings")}},
                                   {u"command"_s, QJsonArray{u"systemsettings"_s, u"kcm_sparkystereo_graphics"_s}}});
    }
    QJsonObject details{{u"args"_s, s.args}, {u"more"_s, s.more}, {u"data"_s, toJson(problem)}, {u"actions"_s, actions}};
    if (problem.status != 0) {
        details[u"status"_s] = problem.status;
    }
    if (!problem.output.isEmpty()) {
        details[u"output"_s] = problem.output;
    }
    if (problem.kind == u"record-write"_s) {
        details[u"repair"_s] = QJsonArray{QJsonArray{u"sparky-stereo-gpu-record"_s, u"--apply-known"_s}};
    } else if (problem.kind == u"systemd-reload"_s) {
        details[u"repair"_s] = QJsonArray{QJsonArray{u"systemctl"_s, u"daemon-reload"_s}};
    }
    const QByteArray package(s_package);
    const QByteArray key = problem.key.toUtf8();
    const QByteArray message = s.key.toUtf8();
    const QByteArray json = QJsonDocument(details).toJson(QJsonDocument::Compact);
    if (ssp_keep(scope, package.constData(), key.constData(), message.constData(), nullptr, 0, json.constData()) != 0) {
        QTextStream(stderr) << "sparky-stereo-graphics: " << engineError() << '\n';
        return false;
    }
    return true;
}

bool clear(const QString &key, const QString &dir)
{
    const int scope = scopeOf(dir);
    const QByteArray k = key.toUtf8();
    if (ssp_clear(scope, s_package, k.constData()) != 0) {
        QTextStream(stderr) << "sparky-stereo-graphics: " << engineError() << '\n';
        return false;
    }
    return true;
}

QList<Problem> read(const QString &dir, bool system)
{
    QList<Problem> list;
    const QString wanted = system ? u"machine"_s : u"person"_s;
    scopeOf(dir);
    char *text = ssp_list_json(s_package, nullptr);
    if (!text) {
        QTextStream(stderr) << "sparky-stereo-graphics: " << engineError() << '\n';
        return list;
    }
    const QJsonArray all = QJsonDocument::fromJson(QByteArray(text)).array();
    ssp_free(text);
    for (const QJsonValue &v : all) {
        const QJsonObject r = v.toObject();
        if (r.value(u"scope"_s).toString() != wanted) {
            continue;
        }
        Problem p = fromJson(r.value(u"data"_s).toObject());
        if (r.contains(u"unreadable"_s) || p.key.isEmpty()) {
            // a record that cannot be read is still a problem kept: it is shown with its file
            p.key = r.value(u"key"_s).toString(r.value(u"file"_s).toString().section(u'/', -1));
            p.kind = u"unreadable"_s;
        }
        p.time = r.value(u"first"_s).toString();
        p.file = r.value(u"file"_s).toString();
        p.system = system;
        list.append(p);
    }
    return list;
}

QJsonArray records(const QStringList &packages)
{
    QJsonArray selected;
    char *text = ssp_list_json(nullptr, nullptr);
    if (!text) {
        QTextStream(stderr) << "sparky-stereo-graphics: " << engineError() << '\n';
        return selected;
    }
    const auto records = QJsonDocument::fromJson(QByteArray(text)).array();
    ssp_free(text);
    for (const auto &value : records) {
        if (packages.contains(value.toObject().value(u"package"_s).toString())) {
            selected.append(value);
        }
    }
    return selected;
}

QList<Problem> all(const QString &root)
{
    return read(systemDir(root), true) + read(userDir());
}

QString kindInSentence(const QString &key)
{
    if (key == u"players"_s) {
        return i18nc("@item kind of program inside a sentence: The GPU you chose for %1", "players");
    }
    if (key == u"games"_s) {
        return i18nc("@item kind of program inside a sentence: The GPU you chose for %1", "games");
    }
    if (key == u"browsers"_s) {
        return i18nc("@item kind of program inside a sentence: The GPU you chose for %1", "browsers");
    }
    return i18nc("@item kind of program inside a sentence: The GPU you chose for %1", "other programs");
}

QString title(const Problem &problem)
{
    if (problem.isDeath()) {
        return i18nc("@title notification", "A program stopped on its GPU");
    }
    if (problem.isPaint()) {
        return i18nc("@title notification", "Painting on the graphics card cannot be used");
    }
    if (problem.isChoice()) {
        return i18nc("@title notification", "A graphics choice cannot be used");
    }
    return i18nc("@title notification", "Graphics needs a repair");
}

static QString address(const QString &id)
{
    return id.startsWith(u"pci-"_s) ? id.mid(4) : id;
}

QString message(const Problem &p)
{
    if (p.isDeath()) {
        return i18nc("@info %1 is a program, %2 a GPU name, %3 says how it stopped", "%1 stopped right after it started on %2: %3.", p.app, p.gpu, howText(p))
            + u' '
            + i18nc("@info what to do",
                    "It was not started again on another GPU. If this GPU is the cause, choose another one for it below, or in System Settings, Graphics.");
    }
    if (p.isPaint()) {
        return i18nc("@info %1 is a program or a kind of program, %2 says why",
                     "Painting on the graphics card cannot be used for %1: %2. The windows are painted on the processor.",
                     p.app.isEmpty() ? kindInSentence(paintKind(p)) : p.app,
                     paintText(p))
            + u' '
            + i18nc("@info what to do",
                    "Choose On the processor for it in System Settings, Graphics, or repair the graphics driver and start the program again.");
    }
    const bool main = p.key == u"main-gpu"_s;
    const QString kind = kindInSentence(p.key);
    QStringList text;
    if (p.kind == u"gpu-missing"_s) {
        text << (main ? i18nc("@info %1 is a PCI address", "The GPU you chose to draw the desktop, at PCI address %1, is not in this computer now.", address(p.requested))
                      : i18nc("@info %1 is a kind of program, %2 a PCI address", "The GPU you chose for %1, at PCI address %2, is not in this computer now.", kind, address(p.requested)));
        text << i18nc("@info what to do", "Put the GPU back, or choose another GPU in System Settings, Graphics.");
    } else if (p.kind == u"gpu-no-driver"_s) {
        if (p.detail.isEmpty()) {
            text << (main ? i18nc("@info %1 is a PCI address",
                                  "The GPU you chose to draw the desktop, at PCI address %1, is in this computer, but no graphics driver is loaded for it.",
                                  address(p.requested))
                          : i18nc("@info %1 is a kind of program, %2 a PCI address",
                                  "The GPU you chose for %1, at PCI address %2, is in this computer, but no graphics driver is loaded for it.",
                                  kind,
                                  address(p.requested)));
        } else {
            text << (main ? i18nc("@info %1 is a PCI address, %2 a kernel driver",
                                  "The GPU you chose to draw the desktop, at PCI address %1, is in this computer, but its driver, %2, gives it no graphics device.",
                                  address(p.requested),
                                  p.detail)
                          : i18nc("@info %1 is a kind of program, %2 a PCI address, %3 a kernel driver",
                                  "The GPU you chose for %1, at PCI address %2, is in this computer, but its driver, %3, gives it no graphics device.",
                                  kind,
                                  address(p.requested),
                                  p.detail));
        }
        text << i18nc("@info what to do", "Install or repair its driver, or choose another GPU in System Settings, Graphics.");
    } else if (p.kind == u"gpu-cannot-render"_s) {
        const QString why = i18nc("@info why a GPU cannot draw, %1 is a kernel driver", "its driver, %1, gives it no render node", p.detail);
        text << (main ? i18nc("@info %1 is a GPU name, %2 says why", "The GPU you chose to draw the desktop, %1, cannot draw now: %2.", p.gpu, why)
                      : i18nc("@info %1 is a kind of program, %2 a GPU name, %3 says why", "The GPU you chose for %1, %2, cannot draw now: %3.", kind, p.gpu, why));
        text << i18nc("@info what to do", "Choose a GPU that can draw in System Settings, Graphics.");
    } else if (p.kind == u"gpu-not-allowed"_s) {
        text << i18nc("@info %1 is a kind of program, %2 a GPU name, %3 a device file",
                      "The GPU you chose for %1, %2, cannot be used by your account: %3 cannot be opened.",
                      kind,
                      p.gpu,
                      p.detail);
        text << i18nc("@info what to do",
                      "Add your account to the render group (sudo adduser $USER render) and log in again, or choose another GPU in System Settings, Graphics.");
    } else if (p.kind == u"kind-missing"_s) {
        text << (p.requested == u"integrated"_s
                     ? i18nc("@info %1 is a kind of program", "You chose the integrated GPU for %1, and this computer has none that can draw now.", kind)
                     : i18nc("@info %1 is a kind of program", "You chose the discrete GPU for %1, and this computer has none that can draw now.", kind));
        text << i18nc("@info what to do", "Choose another GPU in System Settings, Graphics.");
    } else if (p.kind == u"profile-unreadable"_s) {
        text << i18nc("@info %1 is a kind of program, %2 says why",
                      "The GPU for %1 follows the power profile, and the power profile could not be read: %2.",
                      kind,
                      profileError(p.detail, p.extra));
        text << i18nc("@info what to do", "Start power-profiles-daemon (sudo systemctl start power-profiles-daemon), or choose a GPU in System Settings, Graphics.");
    } else if (p.kind == u"record-write"_s) {
        text << i18nc("@info %1 is a file",
                      "The machine's GPU record, %1, could not be written. Until it is, Automatic treats this computer as not measured. Run: sudo "
                      "sparky-stereo-gpu-record --apply-known",
                      p.detail);
    } else if (p.kind == u"systemd-reload"_s) {
        text << i18nc("@info %1 is an exit status",
                      "systemd could not reload its units after the Graphics page was installed (exit status %1). The boot service that writes the "
                      "machine's GPU record may not start. Run: sudo systemctl daemon-reload",
                      p.status);
    } else {
        text << i18nc("@info %1 is a file", "A kept problem of the Graphics page cannot be read: %1.", p.file);
    }
    if (main && p.isChoice()) {
        text << i18nc("@info", "At this login the desktop draws on the GPU the system picks.");
    }
    return text.join(u' ');
}

}

}
