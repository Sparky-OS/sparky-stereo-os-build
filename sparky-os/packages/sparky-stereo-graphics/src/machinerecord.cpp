// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "machinerecord.h"
#include "graphicssettings.h"

#include <KConfig>
#include <KConfigGroup>

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>

#include <algorithm>

using namespace Qt::StringLiterals;

namespace SparkyGraphics
{

static const auto s_measured = u"Measured"_s;
static const auto s_decoding = u"Decoding"_s;
static const auto s_record = u"Record"_s;

bool MachineRecord::isEmpty() const
{
    return bestGpu.isEmpty() && !copyBack.has_value();
}

bool MachineRecord::validGpu(const QString &gpu)
{
    static const QRegularExpression pattern(QStringLiteral(R"(^(pci-[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]|[0-9a-f]{4}:[0-9a-f]{4})$)"));
    return pattern.match(gpu).hasMatch();
}

// Takes from one file every key that is there and valid, over what a less important file gave
static void merge(const QString &path, MachineRecord &record)
{
    if (!QFile::exists(path)) {
        return;
    }
    const KConfig config(path, KConfig::SimpleConfig);
    const KConfigGroup measured = config.group(s_measured);
    const QString best = measured.readEntry("BestGpu", QString()).trimmed().toLower();
    if (MachineRecord::validGpu(best)) {
        record.bestGpu = best;
    }
    if (measured.hasKey("Model")) {
        record.model = measured.readEntry("Model", QString());
    }
    if (measured.hasKey("Measurement")) {
        record.measurement = measured.readEntry("Measurement", QString());
    }
    const KConfigGroup origin = config.group(s_record);
    if (origin.hasKey("Origin")) {
        record.origin = origin.readEntry("Origin", QString());
    }
    if (origin.hasKey("Known")) {
        record.known = origin.readEntry("Known", QString());
    }
    if (const auto copyBack = GraphicsSettings::parseBool(config.group(s_decoding).readEntry("CopyBack", QString()))) {
        record.copyBack = copyBack;
    }
}

MachineRecord MachineRecord::readFile(const QString &path)
{
    MachineRecord record;
    merge(path, record);
    return record;
}

MachineRecord MachineRecord::read()
{
    // As the XDG base directory specification and libmedia-gpu-route read them: $XDG_CONFIG_DIRS, else /etc/xdg,
    // the first folder the most important, so it is read last
    QString dirs = qEnvironmentVariable("XDG_CONFIG_DIRS");
    if (dirs.isEmpty()) {
        dirs = u"/etc/xdg"_s;
    }
    QStringList folders = dirs.split(u':', Qt::SkipEmptyParts);
    std::reverse(folders.begin(), folders.end());
    MachineRecord record;
    for (const QString &folder : std::as_const(folders)) {
        merge(folder + u'/' + GraphicsSettings::configName(), record);
    }
    return record;
}

QString MachineRecord::systemFile(const QString &root)
{
    return QDir::cleanPath(root + u"/etc/xdg/"_s + GraphicsSettings::configName());
}

static QString readLine(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    return QString::fromUtf8(file.readLine()).trimmed();
}

MachineIdentity MachineIdentity::read(const QString &root)
{
    MachineIdentity identity;
    identity.vendor = readLine(root + u"/sys/class/dmi/id/sys_vendor"_s);
    identity.product = readLine(root + u"/sys/class/dmi/id/product_name"_s);
    // Every display controller (PCI base class 03), with or without a driver, so the record is found before
    // the graphics drivers load
    const QDir bus(root + u"/sys/bus/pci/devices"_s);
    const QStringList devices = bus.entryList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::System);
    for (const QString &device : devices) {
        const QString path = bus.filePath(device);
        const uint cls = readLine(path + u"/class"_s).toUInt(nullptr, 16);
        if ((cls >> 16) != 0x03) {
            continue;
        }
        const quint16 vendor = readLine(path + u"/vendor"_s).toUShort(nullptr, 16);
        const quint16 id = readLine(path + u"/device"_s).toUShort(nullptr, 16);
        identity.gpus << QStringLiteral("%1:%2").arg(vendor, 4, 16, QLatin1Char('0')).arg(id, 4, 16, QLatin1Char('0'));
    }
    identity.gpus.sort();
    return identity;
}

bool KnownMachine::matches(const MachineIdentity &machine) const
{
    if (vendor.isEmpty() && product.isEmpty() && gpus.isEmpty()) {
        return false; // a record that says nothing about its machine is for none
    }
    if (!vendor.isEmpty() && vendor.compare(machine.vendor, Qt::CaseInsensitive) != 0) {
        return false;
    }
    if (!product.isEmpty()) {
        const QRegularExpression pattern(QRegularExpression::wildcardToRegularExpression(product), QRegularExpression::CaseInsensitiveOption);
        if (!pattern.match(machine.product).hasMatch()) {
            return false;
        }
    }
    // exactly the GPUs that were measured: a third card changes what is best
    return gpus.isEmpty() || gpus == machine.gpus;
}

QList<KnownMachine> KnownMachine::readAll(const QString &folder)
{
    QList<KnownMachine> list;
    const QDir dir(folder);
    static const QRegularExpression separators(u"[,\\s]+"_s);
    for (const QString &name : dir.entryList({u"*.conf"_s}, QDir::Files, QDir::Name)) {
        const QString path = dir.filePath(name);
        KnownMachine known;
        known.name = QFileInfo(name).completeBaseName();
        const KConfig config(path, KConfig::SimpleConfig);
        const KConfigGroup match = config.group(u"Match"_s);
        known.vendor = match.readEntry("Vendor", QString()).trimmed();
        known.product = match.readEntry("Product", QString()).trimmed();
        known.gpus = match.readEntry("Gpus", QString()).toLower().split(separators, Qt::SkipEmptyParts);
        known.gpus.sort();
        merge(path, known.record);
        known.record.origin.clear();
        known.record.known.clear();
        list << known;
    }
    return list;
}

namespace RecordWriter
{

static bool finish(KConfig &config, const QString &path)
{
    if (!config.sync()) {
        return false;
    }
    // Every program of every account reads it
    QFile::setPermissions(path, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ReadGroup | QFileDevice::ReadOther);
    // A file with nothing left in it goes
    const KConfig check(path, KConfig::SimpleConfig);
    const QStringList groups = check.groupList();
    const bool empty = std::none_of(groups.cbegin(), groups.cend(), [&check](const QString &group) {
        return !check.group(group).keyList().isEmpty();
    });
    if (empty) {
        QFile::remove(path);
    }
    return true;
}

static void setOrDelete(KConfigGroup group, const char *key, const QString &value)
{
    if (value.isEmpty()) {
        group.deleteEntry(key);
    } else {
        group.writeEntry(key, value);
    }
}

static void setOrDelete(KConfigGroup group, const char *key, std::optional<bool> value)
{
    if (value.has_value()) {
        group.writeEntry(key, *value);
    } else {
        group.deleteEntry(key);
    }
}

static bool prepare(const QString &path)
{
    const QFileInfo folder(QFileInfo(path).path());
    return (folder.isDir() || QDir().mkpath(folder.filePath())) && QFileInfo(folder.filePath()).isWritable();
}

static bool removeOurs(const QString &path)
{
    if (!QFile::exists(path)) {
        return true;
    }
    KConfig config(path, KConfig::SimpleConfig);
    KConfigGroup measured = config.group(s_measured);
    measured.deleteEntry("BestGpu");
    measured.deleteEntry("Model");
    measured.deleteEntry("Measurement");
    config.group(s_decoding).deleteEntry("CopyBack");
    KConfigGroup origin = config.group(s_record);
    origin.deleteEntry("Origin");
    origin.deleteEntry("Known");
    return finish(config, path);
}

Result applyKnown(const QString &root, const QString &folder)
{
    const QString path = MachineRecord::systemFile(root);
    const MachineRecord existing = MachineRecord::readFile(path);
    // a record made on this machine, or written by hand, is the machine's own
    if (existing.origin == u"local"_s || (existing.origin.isEmpty() && !existing.isEmpty())) {
        return Result::Kept;
    }
    const MachineIdentity machine = MachineIdentity::read(root);
    const QList<KnownMachine> known = KnownMachine::readAll(folder);
    const auto match = std::find_if(known.cbegin(), known.cend(), [&machine](const KnownMachine &k) {
        return k.matches(machine);
    });
    if (match == known.cend()) {
        if (existing.origin == u"shipped"_s) {
            return removeOurs(path) ? Result::Removed : Result::Failed;
        }
        return Result::NothingKnown;
    }
    const MachineRecord &wanted = match->record;
    if (existing.origin == u"shipped"_s && existing.known == match->name && existing.bestGpu == wanted.bestGpu && existing.model == wanted.model
        && existing.measurement == wanted.measurement && existing.copyBack == wanted.copyBack) {
        return Result::Unchanged;
    }
    if (!prepare(path)) {
        return Result::Failed;
    }
    KConfig config(path, KConfig::SimpleConfig);
    KConfigGroup measured = config.group(s_measured);
    setOrDelete(measured, "BestGpu", wanted.bestGpu);
    setOrDelete(measured, "Model", wanted.model);
    setOrDelete(measured, "Measurement", wanted.measurement);
    setOrDelete(config.group(s_decoding), "CopyBack", wanted.copyBack);
    KConfigGroup origin = config.group(s_record);
    origin.writeEntry("Origin", u"shipped"_s);
    origin.writeEntry("Known", match->name);
    return finish(config, path) ? Result::Written : Result::Failed;
}

bool writeMeasured(const QString &root, const QString &bestGpu, std::optional<bool> copyBack, const QString &model, const QString &measurement)
{
    const QString best = bestGpu.trimmed().toLower();
    const QString path = MachineRecord::systemFile(root);
    if (!MachineRecord::validGpu(best) || !prepare(path)) {
        return false;
    }
    KConfig config(path, KConfig::SimpleConfig);
    KConfigGroup measured = config.group(s_measured);
    measured.writeEntry("BestGpu", best);
    setOrDelete(measured, "Model", model);
    setOrDelete(measured, "Measurement", measurement);
    if (copyBack.has_value()) {
        config.group(s_decoding).writeEntry("CopyBack", *copyBack);
    }
    KConfigGroup origin = config.group(s_record);
    origin.writeEntry("Origin", u"local"_s);
    origin.deleteEntry("Known");
    return finish(config, path);
}

bool writeCopyBack(const QString &root, std::optional<bool> copyBack)
{
    const QString path = MachineRecord::systemFile(root);
    if (!prepare(path)) {
        return false;
    }
    KConfig config(path, KConfig::SimpleConfig);
    setOrDelete(config.group(s_decoding), "CopyBack", copyBack);
    config.group(s_record).writeEntry("Origin", u"local"_s);
    return finish(config, path);
}

bool forget(const QString &root)
{
    return removeOurs(MachineRecord::systemFile(root));
}

}

}
