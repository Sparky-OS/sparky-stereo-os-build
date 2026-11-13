// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "paint.h"

#include <KConfig>
#include <KConfigGroup>

#include <QFile>
#include <QLibrary>
#include <QStandardPaths>

using namespace Qt::StringLiterals;

namespace SparkyGraphics
{

static const QStringList s_ways = {u"cpu"_s, u"batch"_s, u"opengl"_s};
static const auto s_paint = u"Paint"_s;
static const auto s_programs = u"PaintPrograms"_s;
static const auto s_measured = u"MeasuredPaint"_s;

QString paintWayKey(PaintWay way)
{
    return s_ways.at(int(way));
}

std::optional<PaintWay> paintWayFromKey(const QString &key)
{
    const int index = s_ways.indexOf(key.trimmed().toLower());
    return index < 0 ? std::nullopt : std::optional<PaintWay>(PaintWay(index));
}

bool PaintSettings::validKindChoice(const QString &choice)
{
    return choice == u"auto"_s || s_ways.contains(choice);
}

bool PaintSettings::validProgramChoice(const QString &choice)
{
    return choice.isEmpty() || s_ways.contains(choice);
}

PaintSettings::PaintSettings()
    : m_kinds(allCategories().size(), u"auto"_s)
{
    // Only the person's own file, as GraphicsSettings: a value equal to the default is not stored
    KConfig config(GraphicsSettings::configName(), KConfig::SimpleConfig);
    const KConfigGroup paint = config.group(s_paint);
    for (Category category : allCategories()) {
        const QString choice = paint.readEntry(categoryKey(category), QString()).trimmed().toLower();
        if (s_ways.contains(choice)) {
            m_kinds[int(category)] = choice;
        }
    }
    const KConfigGroup programs = config.group(s_programs);
    for (const QString &id : programs.keyList()) {
        const QString choice = programs.readEntry(id, QString()).trimmed().toLower();
        if (s_ways.contains(choice)) {
            m_programs.insert(id, choice);
        }
    }
}

QString PaintSettings::kindChoice(Category category) const
{
    return m_kinds.at(int(category));
}

void PaintSettings::setKindChoice(Category category, const QString &choice)
{
    if (validKindChoice(choice)) {
        m_kinds[int(category)] = choice;
    }
}

QString PaintSettings::programChoice(const QString &id) const
{
    return m_programs.value(id);
}

void PaintSettings::setProgramChoice(const QString &id, const QString &choice)
{
    if (id.isEmpty() || !validProgramChoice(choice)) {
        return;
    }
    if (choice.isEmpty()) {
        m_programs.remove(id);
    } else {
        m_programs.insert(id, choice);
    }
}

QMap<QString, QString> PaintSettings::programChoices() const
{
    return m_programs;
}

bool PaintSettings::isDefault() const
{
    return m_programs.isEmpty() && m_kinds == QStringList(allCategories().size(), u"auto"_s);
}

void PaintSettings::resetToDefaults()
{
    m_kinds = QStringList(allCategories().size(), u"auto"_s);
    m_programs.clear();
}

bool PaintSettings::save()
{
    KConfig config(GraphicsSettings::configName(), KConfig::SimpleConfig);
    KConfigGroup paint = config.group(s_paint);
    for (Category category : allCategories()) {
        if (m_kinds.at(int(category)) == u"auto"_s) {
            paint.deleteEntry(categoryKey(category));
        } else {
            paint.writeEntry(categoryKey(category), m_kinds.at(int(category)));
        }
    }
    config.deleteGroup(s_programs);
    KConfigGroup programs = config.group(s_programs);
    for (auto it = m_programs.cbegin(); it != m_programs.cend(); ++it) {
        programs.writeEntry(it.key(), it.value());
    }
    return config.sync();
}

std::optional<PaintWay> PaintRecord::wayFor(Category category) const
{
    return paintWayFromKey(ways.value(categoryKey(category)));
}

static void merge(const QString &path, PaintRecord &record)
{
    if (!QFile::exists(path)) {
        return;
    }
    const KConfig config(path, KConfig::SimpleConfig);
    const KConfigGroup measured = config.group(s_measured);
    for (Category category : allCategories()) {
        const QString way = measured.readEntry(categoryKey(category), QString()).trimmed().toLower();
        if (s_ways.contains(way)) {
            record.ways.insert(categoryKey(category), way);
        }
    }
    if (measured.hasKey("Measurement")) {
        record.measurement = measured.readEntry("Measurement", QString());
    }
    if (measured.hasKey("Origin")) {
        record.origin = measured.readEntry("Origin", QString());
    }
}

bool PaintRecord::isEmpty() const
{
    return ways.isEmpty();
}

static bool finishRecord(KConfig &config, const QString &path)
{
    if (!config.sync()) {
        return false;
    }
    QFile::setPermissions(path, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ReadGroup | QFileDevice::ReadOther);
    const KConfig check(path, KConfig::SimpleConfig);
    const QStringList groups = check.groupList();
    bool empty = true;
    for (const QString &group : groups) {
        empty = empty && check.group(group).keyList().isEmpty();
    }
    if (empty) {
        QFile::remove(path);
    }
    return true;
}

bool PaintRecord::writeLocal(const QString &path, Category category, const QString &way, const QString &measurement)
{
    if (!way.isEmpty() && !s_ways.contains(way)) {
        return false;
    }
    KConfig config(path, KConfig::SimpleConfig);
    KConfigGroup measured = config.group(s_measured);
    if (measured.readEntry("Origin", QString()) == u"shipped"_s) {
        // a measurement on this machine takes the place of the model's record, whole
        config.deleteGroup(s_measured);
        measured = config.group(s_measured);
    }
    if (way.isEmpty()) {
        measured.deleteEntry(categoryKey(category));
    } else {
        measured.writeEntry(categoryKey(category), way);
    }
    if (!measurement.isEmpty()) {
        measured.writeEntry("Measurement", measurement);
    }
    bool any = false;
    for (Category c : allCategories()) {
        any = any || measured.hasKey(categoryKey(c));
    }
    if (any) {
        measured.writeEntry("Origin", u"local"_s);
    } else {
        config.deleteGroup(s_measured);
    }
    return finishRecord(config, path);
}

bool PaintRecord::writeShipped(const QString &path, const PaintRecord &shipped)
{
    const PaintRecord existing = readFile(path);
    if (existing.origin == u"local"_s || (existing.origin.isEmpty() && !existing.isEmpty())) {
        return true; // the machine's own
    }
    if (existing.ways == shipped.ways && existing.measurement == shipped.measurement && (shipped.isEmpty() || existing.origin == u"shipped"_s)) {
        return true;
    }
    KConfig config(path, KConfig::SimpleConfig);
    config.deleteGroup(s_measured);
    if (!shipped.isEmpty()) {
        KConfigGroup measured = config.group(s_measured);
        for (auto it = shipped.ways.cbegin(); it != shipped.ways.cend(); ++it) {
            measured.writeEntry(it.key(), it.value());
        }
        if (!shipped.measurement.isEmpty()) {
            measured.writeEntry("Measurement", shipped.measurement);
        }
        measured.writeEntry("Origin", u"shipped"_s);
    }
    return finishRecord(config, path);
}

bool PaintRecord::remove(const QString &path, bool all)
{
    if (!QFile::exists(path)) {
        return true;
    }
    const PaintRecord existing = readFile(path);
    if (!all && existing.origin != u"shipped"_s) {
        return true;
    }
    KConfig config(path, KConfig::SimpleConfig);
    config.deleteGroup(s_measured);
    return finishRecord(config, path);
}

PaintRecord PaintRecord::readFile(const QString &path)
{
    PaintRecord record;
    merge(path, record);
    return record;
}

PaintRecord PaintRecord::read()
{
    // The system folders as MachineRecord reads them: the first of $XDG_CONFIG_DIRS the most important, read last
    QString dirs = qEnvironmentVariable("XDG_CONFIG_DIRS");
    if (dirs.isEmpty()) {
        dirs = u"/etc/xdg"_s;
    }
    QStringList folders = dirs.split(u':', Qt::SkipEmptyParts);
    std::reverse(folders.begin(), folders.end());
    PaintRecord record;
    for (const QString &folder : std::as_const(folders)) {
        merge(folder + u'/' + GraphicsSettings::configName(), record);
    }
    return record;
}

PaintFacts PaintFacts::read(bool gpuCanDraw)
{
    PaintFacts facts;
    facts.gpuCanDraw = gpuCanDraw;
    facts.sessionValue = qEnvironmentVariable("QT_WIDGETS_GPU_PAINT");
    return facts;
}

bool PaintFacts::qtHasPainting()
{
    const QString forced = qEnvironmentVariable("SPARKY_STEREO_QT_PAINT");
    if (!forced.isEmpty()) {
        return forced != u"0"_s;
    }
    QLibrary gui(u"Qt6Gui"_s, 6);
    return gui.resolve("_Z25qt_widgets_gpu_paint_modev") != nullptr;
}

namespace Paint
{

QString problemKey(Category category, const QString &id)
{
    if (id.isEmpty()) {
        return u"paint-"_s + categoryKey(category).toLower();
    }
    QString name = id;
    if (name.endsWith(u".desktop"_s)) {
        name.chop(8);
    }
    return u"paint-"_s + name;
}

QString runKey(const QString &program)
{
    QString name = program;
    if (name.endsWith(u".desktop"_s)) {
        name.chop(8);
    }
    return u"paint-run-"_s + name;
}

PaintResolution resolve(Category category, const QString &id, const PaintSettings &settings, const PaintRecord &record, const PaintFacts &facts)
{
    PaintResolution resolution;
    // A QT_WIDGETS_GPU_PAINT the person set by hand in the session is their explicit choice: it is kept, as a GPU
    // variable set by hand is, and the page says so
    if (!facts.sessionValue.isEmpty()) {
        resolution.reason = u"session"_s;
        resolution.chosen = true;
        const QString value = facts.sessionValue.trimmed().toLower();
        resolution.way = resolution.asked = (value == u"batch"_s || value == u"2"_s)   ? PaintWay::Batched
            : (value == u"1"_s || value == u"opengl"_s) ? PaintWay::OpenGL
                                                        : PaintWay::Processor;
        return resolution;
    }
    const QString program = id.isEmpty() ? QString() : settings.programChoice(id);
    const QString kind = settings.kindChoice(category);
    if (const auto way = paintWayFromKey(program)) {
        resolution.asked = *way;
        resolution.reason = u"program"_s;
        resolution.chosen = true;
    } else if (const auto way = paintWayFromKey(kind)) {
        resolution.asked = *way;
        resolution.reason = u"choice"_s;
        resolution.chosen = true;
    } else if (const auto way = record.wayFor(category)) {
        // Automatic: the way measured for this kind of program on this machine (Daniel, 2026-10-23: "our measured
        // defaults out of the box, every choice the user's")
        resolution.asked = *way;
        resolution.reason = u"measured"_s;
    } else {
        // not measured here: the processor, as every Qt paints; nothing changes until a measurement says otherwise
        resolution.asked = PaintWay::Processor;
        resolution.reason = u"unmeasured"_s;
    }
    resolution.way = resolution.asked;
    if (resolution.asked != PaintWay::Processor) {
        if (!facts.gpuCanDraw) {
            resolution.problem = u"no-gpu"_s;
        } else if (!facts.qtPaintsOnGpu) {
            resolution.problem = u"qt"_s;
        }
        if (!resolution.problem.isEmpty()) {
            resolution.way = PaintWay::Processor;
        }
    }
    if (resolution.way != PaintWay::Processor) {
        resolution.environment << u"QT_WIDGETS_GPU_PAINT="_s + paintWayKey(resolution.way);
        // the program itself says when the painting cannot start after all (no OpenGL in the session, an OpenGL the
        // processor draws): the edition's Qt runs this command, which keeps it for the person
        const QString self = QStandardPaths::findExecutable(u"sparky-stereo-gpu-env"_s);
        if (!self.isEmpty()) {
            resolution.environment << u"QT_WIDGETS_GPU_PAINT_TELL="_s + self;
        }
    }
    return resolution;
}

}

}
