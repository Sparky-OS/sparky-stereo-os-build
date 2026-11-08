// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "gpuinventory.h"
#include "resolver.h"

#include <QJsonArray>
#include <QList>
#include <QString>
#include <QStringList>

namespace SparkyGraphics
{

struct Alternative {
    QString id; // "pci-0000:03:00.0"
    QString name;
};

// A saved choice that cannot be used, or a step of the package that failed: what failed, why and what to do, kept with
// its evidence until it is repaired, by the edition's one engine (sparky-stereo-problems, ORDER 350): the person's own
// in $XDG_STATE_HOME/sparky-stereo-problems, the machine's in /var/lib/sparky-stereo-problems; the engine's session
// notifier shows each at login and when it is kept, with "Use NAME" for each GPU that can draw, and the Graphics page too.
struct Problem {
    // Where it belongs, and the file it is kept in: "main-gpu", the kind of program ("players", "games", "browsers",
    // "other"), or a step of the machine ("machine-record", "systemd-reload")
    QString key;
    // "gpu-missing", "gpu-no-driver" (on the PCI bus with no graphics device), "gpu-cannot-render", "gpu-not-allowed",
    // "kind-missing", "profile-unreadable", "record-write", "systemd-reload"; and (ORDER 467) "app-died": a program sent to
    // a GPU stopped right after it started (key "died-NAME", NAME of its desktop entry)
    QString kind;
    QString requested; // the choice: a GPU id, "integrated", "discrete", "auto" or "profile"
    QString gpu; // the name of the GPU asked for, when it is here
    QString detail; // the driver, the render node, the profile's error ("not-running", ...), the file
    QString extra; // the error's own text (D-Bus, the profile name)
    QList<Alternative> alternatives; // the GPUs a program can be sent to now, offered only as an explicit choice
    QString time; // when it was kept, UTC
    QString command; // the command whose failure it is
    int status = 0; // its exit status
    QString output; // the end of its output
    QString app; // "app-died": the program's name, as its desktop entry gives it
    QString file; // the record's file, once read or kept
    bool system = false; // the machine's, not the person's

    bool isEmpty() const;
    // One GPU choice of the person's (main GPU or a kind of program): the page and the notification offer the others
    bool isChoice() const;
    // A program that stopped right after it started on its GPU (ORDER 467), not a saved choice that cannot be used
    bool isDeath() const;
};

// What the edition's one engine keeps of a problem: its message (CONTEXT|MSGID of this package's .po files), the
// message's arguments (strings, or [KEY, ARG...] for a message inside it) and the sentences after it (what to do)
struct Sentences {
    QString key;
    QJsonArray args;
    QJsonArray more;
};

namespace Problems
{
// root/var/lib/sparky-stereo-graphics/problems
QString systemDir(const QString &root = QStringLiteral("/"));
// $XDG_STATE_HOME/sparky-stereo-graphics/problems
QString userDir();

// The problem of a resolution of a saved choice (key: "main-gpu" or a kind), with what the computer has now
Problem fromResolution(const QString &key, const Resolution &resolution, const QList<Gpu> &gpus, const QString &root,
                       const ProfileReading &profile = ProfileReading());
// A program the Graphics page sent to a GPU and that stopped right after it started: how it ended is `how` ("crash":
// number is the signal, "exit": the exit status, "result": systemd's word in extra), the GPUs it can be sent to instead
// are only those its desktop entry can name (the desktop's GPU, or the discrete one), and only as the person's choice
Problem fromDeath(const QString &appName, const QString &appId, const QString &app, const QString &how, int number, const QString &word,
                  const QString &output, int gpuIndex, const QList<Gpu> &gpus, const QList<int> &instead);
// The profile's reading as words, for the messages: "power-profiles-daemon is not running", ...
QString profileError(const QString &error, const QString &detail);

// Writes DIR/KEY.json (the time is set when it is new or changed); false, said on stderr, when it cannot be kept
bool keep(Problem problem, const QString &dir);
// The choice works again: its record goes; false when a record that is there cannot be removed
bool clear(const QString &key, const QString &dir);
QList<Problem> read(const QString &dir, bool system = false);
// The person's and the machine's, the machine's first
QJsonArray records(const QStringList &packages);
QList<Problem> all(const QString &root = QStringLiteral("/"));

QString title(const Problem &problem);
// What failed, why and what to do, in the person's language
QString message(const Problem &problem);
// The same, as the engine keeps it
Sentences sentences(const Problem &problem);
// The kind of program as it reads inside a sentence ("players")
QString kindInSentence(const QString &key);
}

}
