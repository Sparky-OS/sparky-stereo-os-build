// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "graphicssettings.h"

#include <QMap>
#include <QString>
#include <QStringList>

#include <optional>

namespace SparkyGraphics
{

// ORDER 518. How a program made with Qt Widgets paints its windows: on the processor (Qt's raster engine, as every
// Qt does), on the graphics card in a few draw calls ("batch"), or on the graphics card by Qt's OpenGL paint engine
// ("opengl"). All three stay the person's choice (Daniel, 2026-11-12: "keep as a option"); the edition's qt6-base
// reads the way from QT_WIDGETS_GPU_PAINT, which this page's resolver hands to the launcher with the GPU variables.
enum class PaintWay {
    Processor,
    Batched,
    OpenGL,
};

QString paintWayKey(PaintWay way); // "cpu", "batch", "opengl"
std::optional<PaintWay> paintWayFromKey(const QString &key);

// The person's choices, in ~/.config/sparky-stereo-graphicsrc beside the GPU choices:
//   [Paint] Players= Games= Browsers= Other=     auto (not written), cpu, batch or opengl, for a kind of program
//   [PaintPrograms] ID.desktop=                  cpu, batch or opengl for one program; not written: as its kind
class PaintSettings
{
public:
    PaintSettings();

    QString kindChoice(Category category) const; // "auto", "cpu", "batch", "opengl"
    void setKindChoice(Category category, const QString &choice);
    QString programChoice(const QString &id) const; // "" (as its kind), "cpu", "batch", "opengl"
    void setProgramChoice(const QString &id, const QString &choice);
    QMap<QString, QString> programChoices() const;

    bool isDefault() const;
    void resetToDefaults();
    bool save();

    static bool validKindChoice(const QString &choice);
    static bool validProgramChoice(const QString &choice);

private:
    QStringList m_kinds;
    QMap<QString, QString> m_programs;
};

// What was measured on this machine or its model: [MeasuredPaint] of sparky-stereo-graphicsrc in the system folders
// (the machine record sparky-stereo-gpu-record writes), one way for each kind of program, and where the numbers
// come from. A kind that was not measured has no key.
struct PaintRecord {
    QMap<QString, QString> ways; // "Other" -> "batch"
    QString measurement;
    QString origin; // "local" (measured or set on this machine), "shipped" (a known model) or empty (written by hand)

    bool isEmpty() const;
    // Written by sparky-stereo-gpu-record, as root, into the machine's file (root/etc/xdg/sparky-stereo-graphicsrc):
    // one kind's way from a measurement on this machine (way empty: that kind is not measured any more)
    static bool writeLocal(const QString &path, Category category, const QString &way, const QString &measurement);
    // the record shipped for this model, unless the machine has one of its own; false only when it cannot be written
    static bool writeShipped(const QString &path, const PaintRecord &shipped);
    // removes the shipped record (the disk moved to another model), or everything the tool wrote (all)
    static bool remove(const QString &path, bool all);

    std::optional<PaintWay> wayFor(Category category) const;
    static PaintRecord read();
    static PaintRecord readFile(const QString &path);
};

// What the resolver knows before a program starts
struct PaintFacts {
    bool gpuCanDraw = true; // some GPU of this computer has a render node the account may open
    bool qtPaintsOnGpu = true; // the installed Qt Gui has the painting (sparky's qt6-base)
    QString sessionValue; // QT_WIDGETS_GPU_PAINT as the caller's environment has it: set by hand, it wins

    // gpuCanDraw and the session's value; the Qt question is asked apart, only when a way on the graphics card is wanted
    static PaintFacts read(bool gpuCanDraw);
    // Whether the installed Qt Gui has the painting: the switch's own reader, as the edition's qt6-base exports it.
    // A Qt without it would ignore the variable without a word, so the answer is looked up, not assumed.
    // SPARKY_STEREO_QT_PAINT=0|1 answers for a test.
    static bool qtHasPainting();
};

struct PaintResolution {
    PaintWay way = PaintWay::Processor; // the way the program paints
    PaintWay asked = PaintWay::Processor; // the way the choice or the measurement asks for
    // "program" (the program's own choice), "choice" (its kind's), "measured", "unmeasured" (Automatic without a
    // measurement: the processor, as every Qt paints), "session" (QT_WIDGETS_GPU_PAINT set by hand)
    QString reason;
    // The way asked for cannot be had, so the windows are painted on the processor, and that is said and kept:
    // "no-gpu" (no graphics processor that can draw), "qt" (the installed Qt has no such painting)
    QString problem;
    bool chosen = false; // the person chose it (a program's or a kind's choice), not Automatic
    QStringList environment; // QT_WIDGETS_GPU_PAINT=..., QT_WIDGETS_GPU_PAINT_TELL=...; empty for the processor
};

namespace Paint
{
// id: the program's desktop entry ("org.kde.kate.desktop"), empty for a kind alone
PaintResolution resolve(Category category, const QString &id, const PaintSettings &settings, const PaintRecord &record, const PaintFacts &facts);
// The key a problem of this program or kind is kept under: "paint-org.kde.kate" or "paint-other"
QString problemKey(Category category, const QString &id);
// The key of a failure the program itself told while it ran: "paint-run-org.kde.kate"
QString runKey(const QString &program);
}

}
