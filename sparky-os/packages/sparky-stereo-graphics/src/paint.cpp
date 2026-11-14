// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "paint.h"

#include <KConfig>
#include <KConfigGroup>

#include <QFile>
#include <QLibrary>
#include <QRegularExpression>
#include <QStandardPaths>

using namespace Qt::StringLiterals;

namespace SparkyGraphics
{

static const QStringList s_ways = {u"cpu"_s, u"batch"_s, u"opengl"_s};
static const auto s_paint = u"Paint"_s;
static const auto s_programs = u"PaintPrograms"_s;

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

static const auto s_measuredPrograms = u"MeasuredPaintPrograms"_s;

bool PaintProgramRow::followsItsLoads() const
{
    if (way != u"batch"_s) {
        return way == u"cpu"_s;
    }
    if (loads.isEmpty()) {
        return false;
    }
    for (const QString &text : loads) {
        const QStringList numbers = text.split(u' ', Qt::SkipEmptyParts);
        bool okProcessor = false;
        bool okBatched = false;
        const double processor = numbers.value(0).toDouble(&okProcessor);
        const double batched = numbers.value(1).toDouble(&okBatched);
        if (!okProcessor || !okBatched || processor <= 0 || batched > processor * 0.8) {
            return false;
        }
    }
    return true;
}

QString PaintRecord::gpuKey(quint16 vendor, quint16 device)
{
    return QStringLiteral("%1:%2").arg(vendor, 4, 16, QLatin1Char('0')).arg(device, 4, 16, QLatin1Char('0'));
}

bool PaintRecord::validGpuKey(const QString &gpu)
{
    static const QRegularExpression pattern(u"^[0-9a-f]{4}:[0-9a-f]{4}$"_s);
    return pattern.match(gpu).hasMatch();
}

std::optional<PaintProgramRow> PaintRecord::rowFor(const QString &program, const QString &gpu) const
{
    for (const PaintProgramRow &row : programs) {
        if (row.program == program && row.gpu == gpu) {
            return row;
        }
    }
    return std::nullopt;
}

static void merge(const QString &path, PaintRecord &record)
{
    if (!QFile::exists(path)) {
        return;
    }
    const KConfig config(path, KConfig::SimpleConfig);
    const KConfigGroup measured = config.group(s_measuredPrograms);
    for (const QString &program : measured.groupList()) {
        const KConfigGroup cards = measured.group(program);
        for (const QString &gpu : cards.groupList()) {
            const KConfigGroup group = cards.group(gpu);
            PaintProgramRow row;
            row.program = program;
            row.gpu = gpu.toLower();
            row.way = group.readEntry("Way", QString()).trimmed().toLower();
            // a row whose way is not one of the three, or whose card is not a card, says nothing
            if ((row.way != u"cpu"_s && row.way != u"batch"_s) || !PaintRecord::validGpuKey(row.gpu)) {
                continue;
            }
            for (const QString &key : group.keyList()) {
                if (key.startsWith(u"Load."_s)) {
                    row.loads.insert(key.mid(5), group.readEntry(key, QString()).simplified());
                } else if (key.startsWith(u"Runs."_s)) {
                    row.runs.insert(key.mid(5), group.readEntry(key, QString()).simplified());
                }
            }
            row.source = group.readEntry("Source", QString());
            // the more important folder's row takes the place of the other's
            record.programs.removeIf([&row](const PaintProgramRow &other) {
                return other.program == row.program && other.gpu == row.gpu;
            });
            record.programs << row;
        }
    }
    if (measured.hasKey("Origin")) {
        record.origin = measured.readEntry("Origin", QString());
    }
}

bool PaintRecord::isEmpty() const
{
    return programs.isEmpty();
}

static bool finishRecord(KConfig &config, const QString &path)
{
    if (!config.sync()) {
        return false;
    }
    QFile::setPermissions(path, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ReadGroup | QFileDevice::ReadOther);
    const KConfig check(path, KConfig::SimpleConfig);
    if (check.groupList().isEmpty()) {
        QFile::remove(path);
    }
    return true;
}

static void writeRow(KConfigGroup measured, const PaintProgramRow &row)
{
    KConfigGroup group = measured.group(row.program).group(row.gpu);
    group.writeEntry("Way", row.way);
    for (auto it = row.loads.cbegin(); it != row.loads.cend(); ++it) {
        group.writeEntry(u"Load."_s + it.key(), it.value());
    }
    for (auto it = row.runs.cbegin(); it != row.runs.cend(); ++it) {
        group.writeEntry(u"Runs."_s + it.key(), it.value());
    }
    if (!row.source.isEmpty()) {
        group.writeEntry("Source", row.source);
    }
}

bool PaintRecord::writeLocal(const QString &path, const QString &program, const QString &gpu, const QString &way, const QString &source)
{
    if (program.isEmpty() || !validGpuKey(gpu) || (!way.isEmpty() && way != u"cpu"_s && way != u"batch"_s)) {
        return false;
    }
    KConfig config(path, KConfig::SimpleConfig);
    if (config.group(s_measuredPrograms).readEntry("Origin", QString()) == u"shipped"_s) {
        // a measurement on this machine takes the place of the model's record, whole
        config.deleteGroup(s_measuredPrograms);
    }
    KConfigGroup measured = config.group(s_measuredPrograms);
    measured.group(program).deleteGroup(gpu);
    if (!way.isEmpty()) {
        PaintProgramRow row;
        row.program = program;
        row.gpu = gpu;
        row.way = way;
        row.source = source;
        writeRow(measured, row);
    }
    bool any = false;
    for (const QString &name : measured.groupList()) {
        if (measured.group(name).groupList().isEmpty()) {
            measured.deleteGroup(name);
        } else {
            any = true;
        }
    }
    if (any) {
        measured.writeEntry("Origin", u"local"_s);
    } else {
        config.deleteGroup(s_measuredPrograms);
    }
    return finishRecord(config, path);
}

bool PaintRecord::writeShipped(const QString &path, const PaintRecord &shipped)
{
    const PaintRecord existing = readFile(path);
    if (existing.origin == u"local"_s || (existing.origin.isEmpty() && !existing.isEmpty())) {
        return true; // the machine's own
    }
    if (existing.programs == shipped.programs && (shipped.isEmpty() || existing.origin == u"shipped"_s)) {
        return true;
    }
    KConfig config(path, KConfig::SimpleConfig);
    config.deleteGroup(s_measuredPrograms);
    if (!shipped.isEmpty()) {
        KConfigGroup measured = config.group(s_measuredPrograms);
        for (const PaintProgramRow &row : shipped.programs) {
            writeRow(measured, row);
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
    config.deleteGroup(s_measuredPrograms);
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

PaintResolution resolve(Category category, const QString &id, const QString &gpu, const PaintSettings &settings, const PaintRecord &record,
                        const PaintFacts &facts)
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
    } else if (const auto row = id.isEmpty() ? std::nullopt : record.rowFor(id, gpu)) {
        // Automatic: the way measured for this program on the card it is drawn on (Daniel, 2026-11-13: "I want the
        // automatic per program for sure"). A row that says batch against its own numbers is not followed
        if (row->way == u"batch"_s && row->followsItsLoads()) {
            resolution.asked = PaintWay::Batched;
            resolution.reason = u"measured"_s;
        } else {
            resolution.asked = PaintWay::Processor;
            resolution.reason = u"measured-processor"_s;
        }
    } else {
        // not measured here: the processor, as every Qt paints; nothing is guessed for a program or a machine
        // that was not measured (Daniel, 2026-11-13: "no need complicated measurements now, leave it to iso 2")
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
