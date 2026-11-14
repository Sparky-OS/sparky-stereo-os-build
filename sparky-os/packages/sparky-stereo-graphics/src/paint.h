// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "graphicssettings.h"

#include <QList>
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

// ORDER 554. What was measured: the processor a program takes for the same work on each way of painting, on one
// graphics card of one machine. Automatic follows it for each program (Daniel, 2026-11-13: "I want the automatic per
// program for sure"); a program with no row, or on a card with no row, stays on the processor.
// In sparky-stereo-graphicsrc of the system folders (the machine record sparky-stereo-gpu-record writes), one group
// for each program and card:
//   [MeasuredPaintPrograms][org.kde.konsole.desktop][1002:1638]
//   Way=batch                      the way Automatic gives the program on that card: cpu or batch
//   Load.animation=14.8 8.6 35.9   processor milliseconds for each frame asked, the program and the compositor
//                                  together: the processor, batched, Qt's OpenGL engine (one key for each fixed work)
//   Runs.animation=1 2 1           the quiet runs behind each number
//   Source=...                     where the numbers come from
struct PaintProgramRow {
    QString program; // "org.kde.konsole.desktop"
    QString gpu; // "1002:1638", the card the program paints on
    QString way; // "cpu" or "batch": Qt's OpenGL engine took more processor in every measurement, so no row names it
    QMap<QString, QString> loads; // "animation" -> "14.8 8.6 35.9"
    QMap<QString, QString> runs; // "animation" -> "1 2 1"
    QString source;

    bool operator==(const PaintProgramRow &other) const = default;
    // The rule a row's way follows (README, "Automatic for each program"): batched only when every fixed work
    // took at least a fifth less processor batched than on the processor. False for a row that says batch
    // against its own numbers, or that has no numbers; a row that says cpu is not judged
    bool followsItsLoads() const;
};

struct PaintRecord {
    QList<PaintProgramRow> programs;
    QString origin; // "local" (measured or set on this machine), "shipped" (a known model) or empty (written by hand)

    bool isEmpty() const;
    // the row of a program on a card; nothing when that was not measured
    std::optional<PaintProgramRow> rowFor(const QString &program, const QString &gpu) const;
    // Written by sparky-stereo-gpu-record, as root, into the machine's file (root/etc/xdg/sparky-stereo-graphicsrc):
    // one program's way on one card ("cpu" or "batch") from a measurement on this machine (way empty: not measured any more)
    static bool writeLocal(const QString &path, const QString &program, const QString &gpu, const QString &way, const QString &source);
    // the record shipped for this model, unless the machine has one of its own; false only when it cannot be written
    static bool writeShipped(const QString &path, const PaintRecord &shipped);
    // removes the shipped record (the disk moved to another model), or everything the tool wrote (all)
    static bool remove(const QString &path, bool all);

    static PaintRecord read();
    static PaintRecord readFile(const QString &path);
    // "1002:1638" from a card's vendor and device numbers
    static QString gpuKey(quint16 vendor, quint16 device);
    static bool validGpuKey(const QString &gpu);
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
    // "program" (the program's own choice), "choice" (its kind's), "session" (QT_WIDGETS_GPU_PAINT set by hand), and
    // for Automatic: "measured" (this program was measured on this card and takes less processor on the way named),
    // "measured-processor" (measured, and no way on the graphics card took less), "unmeasured" (no row for this
    // program on this card, or no program named: the processor, as every Qt paints)
    QString reason;
    // The way asked for cannot be had, so the windows are painted on the processor, and that is said and kept:
    // "no-gpu" (no graphics processor that can draw), "qt" (the installed Qt has no such painting)
    QString problem;
    bool chosen = false; // the person chose it (a program's or a kind's choice), not Automatic
    QStringList environment; // QT_WIDGETS_GPU_PAINT=..., QT_WIDGETS_GPU_PAINT_TELL=...; empty for the processor
};

namespace Paint
{
// id: the program's desktop entry ("org.kde.kate.desktop"), empty for a kind alone; gpu: the card the program is
// drawn on ("1002:1638"), empty when none is known
PaintResolution resolve(Category category, const QString &id, const QString &gpu, const PaintSettings &settings, const PaintRecord &record,
                        const PaintFacts &facts);
// The key a problem of this program or kind is kept under: "paint-org.kde.kate" or "paint-other"
QString problemKey(Category category, const QString &id);
// The key of a failure the program itself told while it ran: "paint-run-org.kde.kate"
QString runKey(const QString &program);
}

}
