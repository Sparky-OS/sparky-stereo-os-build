// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "graphicssettings.h"

#include <QList>
#include <QString>
#include <QStringList>

#include <optional>

namespace SparkyGraphics
{

// The machine's record: groups [Measured] and [Decoding] of sparky-stereo-graphicsrc in the system folders
// ($XDG_CONFIG_DIRS, /etc/xdg), beneath the person's own file in ~/.config. One file for the page and for
// libmedia-gpu-route, which reads [Decoding] CopyBack from the same two places.
struct MachineRecord {
    QString bestGpu; // the GPU measured best for players and 3D: "pci-0000:03:00.0" or "1002:6660"; empty when not measured
    QString model; // the model a shipped record was measured on
    QString measurement; // where the numbers come from
    QString origin; // "local" (measured or set on this machine), "shipped" (a known model) or empty (written by hand)
    QString known; // the shipped record's name
    std::optional<bool> copyBack; // the machine's copy-back setting

    bool isEmpty() const;

    // The system folders, the first one the most important, as KConfig reads them
    static MachineRecord read();
    static MachineRecord readFile(const QString &path);
    // root/etc/xdg/sparky-stereo-graphicsrc, the file sparky-stereo-gpu-record writes
    static QString systemFile(const QString &root);
    // "pci-0000:03:00.0" or "1002:6660"
    static bool validGpu(const QString &gpu);
};

// What a shipped record is matched against: the firmware's model strings and the display controllers on the PCI bus
struct MachineIdentity {
    QString vendor; // DMI sys_vendor, "LENOVO"
    QString product; // DMI product_name, "80ST"
    QStringList gpus; // "1002:6660" for every display controller, sorted
    QString cpu; // the processor's model name as the kernel reports it, "AMD Ryzen 5 5600G with Radeon Graphics"

    static MachineIdentity read(const QString &root);
};

// A record shipped for a model that was measured: [Match] says which machines it is for
struct KnownMachine {
    QString name; // the file name without .conf
    QString vendor; // equal to DMI sys_vendor, ignoring case
    QString product; // DMI product_name, a wildcard pattern ("80ST*")
    QStringList gpus; // exactly the display controllers of the machine
    QString cpu; // equal to the processor's model name, ignoring case; for a machine its firmware does not name (ORDER 554)
    MachineRecord record;

    bool matches(const MachineIdentity &machine) const;
    static QList<KnownMachine> readAll(const QString &folder);
};

// What sparky-stereo-gpu-record writes, as root, into root/etc/xdg/sparky-stereo-graphicsrc
namespace RecordWriter
{
enum class Result {
    Written,
    Unchanged,
    Kept, // a local or hand-written record is never replaced by a shipped one
    Removed, // a shipped record for another model: this disk moved to another machine
    NothingKnown,
    Failed,
};

// At boot: the shipped record of this model, when the machine has no record of its own
Result applyKnown(const QString &root, const QString &folder);
// A measurement's result; copyBack empty leaves the machine's copy-back setting as it is
bool writeMeasured(const QString &root, const QString &bestGpu, std::optional<bool> copyBack, const QString &model, const QString &measurement);
bool writeCopyBack(const QString &root, std::optional<bool> copyBack);
// Removes what the tool wrote; the file goes when nothing else is in it
bool forget(const QString &root);
// ORDER 554: the way of painting windows measured on this machine for a program on a card ("cpu", "batch";
// empty: not measured any more), in [MeasuredPaintPrograms]; Automatic on the Graphics page follows it
bool writePaint(const QString &root, const QString &program, const QString &gpu, const QString &way, const QString &source);
}

}
