// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "problems.h"

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

bool Problem::isChoice() const
{
    return !system && !kind.isEmpty() && kind != u"record-write"_s && kind != u"systemd-reload"_s;
}

namespace Problems
{

QString systemDir(const QString &root)
{
    return QDir::cleanPath(root + u"/var/lib/sparky-stereo-graphics/problems"_s);
}

QString userDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation) + u"/sparky-stereo-graphics/problems"_s;
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
        const QString device = QDir::cleanPath(root + u"/sys/bus/pci/devices/"_s + problem.requested.mid(4));
        if (QFileInfo::exists(device)) {
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
    return p;
}

static bool sameProblem(const Problem &a, const Problem &b)
{
    QJsonObject x = toJson(a);
    QJsonObject y = toJson(b);
    x.remove(u"time"_s);
    y.remove(u"time"_s);
    return x == y;
}

bool keep(Problem problem, const QString &dir)
{
    const QString path = dir + u'/' + problem.key + u".json"_s;
    // the same problem kept again keeps its first time, so a notification is shown once for it
    const QList<Problem> kept = read(dir);
    for (const Problem &old : kept) {
        if (old.key == problem.key && sameProblem(old, problem)) {
            return true;
        }
    }
    problem.time = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
    QSaveFile file(path);
    if (!QDir().mkpath(dir) || !file.open(QIODevice::WriteOnly)) {
        QTextStream(stderr) << path << ": " << file.errorString() << '\n';
        return false;
    }
    file.write(QJsonDocument(toJson(problem)).toJson());
    if (!file.commit()) {
        QTextStream(stderr) << path << ": " << file.errorString() << '\n';
        return false;
    }
    QFile::setPermissions(path, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ReadGroup | QFileDevice::ReadOther);
    return true;
}

bool clear(const QString &key, const QString &dir)
{
    const QString path = dir + u'/' + key + u".json"_s;
    if (!QFile::exists(path)) {
        return true;
    }
    QFile file(path);
    if (!file.remove()) {
        QTextStream(stderr) << path << ": " << file.errorString() << '\n';
        return false;
    }
    return true;
}

QList<Problem> read(const QString &dir, bool system)
{
    QList<Problem> list;
    const QStringList names = QDir(dir).entryList({u"*.json"_s}, QDir::Files, QDir::Name);
    for (const QString &name : names) {
        QFile file(dir + u'/' + name);
        Problem p;
        if (file.open(QIODevice::ReadOnly)) {
            p = fromJson(QJsonDocument::fromJson(file.readAll()).object());
        }
        if (p.key.isEmpty()) {
            // a record that cannot be read is still a problem kept: it is shown with its file
            p.key = name.chopped(5);
            p.kind = u"unreadable"_s;
        }
        p.file = file.fileName();
        p.system = system;
        list.append(p);
    }
    return list;
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
