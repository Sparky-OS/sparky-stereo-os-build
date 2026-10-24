// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "appentries.h"

#include <KConfigGroup>
#include <KDesktopFile>

#include <QCryptographicHash>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QMap>
#include <QStandardPaths>

using namespace Qt::StringLiterals;

namespace SparkyGraphics
{

static const QString s_preferenceKey = u"PrefersNonDefaultGPU"_s;
static const QString s_legacyKey = u"X-KDE-RunOnDiscreteGpu"_s;
static const QString s_copyOfKey = u"X-SparkyStereo-GraphicsCopyOf"_s;
static const QString s_digestKey = u"X-SparkyStereo-GraphicsCopyDigest"_s;

namespace
{
struct Paths {
    QString user; // the file in the person's own folder
    QString system; // the first system file with that id
};

using Content = QMap<QString, QMap<QString, QString>>;

Content contentOf(KDesktopFile &file, const QStringList &ignoredKeys)
{
    Content content;
    for (const QString &group : file.groupList()) {
        QMap<QString, QString> entries = file.group(group).entryMap();
        for (const QString &key : ignoredKeys) {
            entries.remove(key);
        }
        content.insert(group, entries);
    }
    return content;
}

QString digestOf(KDesktopFile &file)
{
    QCryptographicHash hash(QCryptographicHash::Sha1);
    const Content content = contentOf(file, {s_digestKey});
    for (auto group = content.cbegin(); group != content.cend(); ++group) {
        for (auto entry = group.value().cbegin(); entry != group.value().cend(); ++entry) {
            hash.addData((group.key() + u'\0' + entry.key() + u'\0' + entry.value() + u'\n').toUtf8());
        }
    }
    return QString::fromLatin1(hash.result().toHex());
}

QString fileDigest(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    return QString::fromLatin1(QCryptographicHash::hash(file.readAll(), QCryptographicHash::Sha1).toHex());
}

AppPreference preferenceIn(KDesktopFile &file)
{
    const KConfigGroup group = file.desktopGroup();
    if (group.hasKey(s_preferenceKey)) {
        return group.readEntry(s_preferenceKey, false) ? AppPreference::OtherGpu : AppPreference::MainGpu;
    }
    if (group.readEntry(s_legacyKey, false)) {
        return AppPreference::OtherGpu;
    }
    return AppPreference::Unset;
}

QMap<QString, Paths> collect(const QString &dataHome, const QStringList &dataDirs)
{
    QMap<QString, Paths> map;
    const auto scan = [&map](const QString &base, bool user) {
        const QString apps = base + u"/applications"_s;
        QDirIterator it(apps, {u"*.desktop"_s}, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QString path = it.next();
            QString id = path.mid(apps.size() + 1);
            id.replace(u'/', u'-');
            Paths &paths = map[id];
            QString &slot = user ? paths.user : paths.system;
            if (slot.isEmpty()) {
                slot = path;
            }
        }
    };
    scan(dataHome, true);
    for (const QString &dir : dataDirs) {
        scan(dir, false);
    }
    return map;
}

AppEntry entryFrom(const QString &id, const Paths &paths)
{
    AppEntry entry;
    entry.id = id;
    entry.fromUserCopy = !paths.user.isEmpty();
    entry.path = entry.fromUserCopy ? paths.user : paths.system;
    KDesktopFile file(entry.path);
    entry.name = file.readName();
    entry.icon = file.readIcon();
    entry.categories = file.desktopGroup().readXdgListEntry("Categories");
    entry.category = AppEntries::categoryFor(entry.categories);
    entry.preference = preferenceIn(file);
    if (!paths.system.isEmpty()) {
        KDesktopFile system(paths.system);
        entry.systemPrefersOther = preferenceIn(system) == AppPreference::OtherGpu;
    }
    return entry;
}

bool hiddenFromMenu(const QString &path)
{
    KDesktopFile file(path);
    return file.noDisplay() || file.desktopGroup().readEntry("Hidden", false) || file.readType() != u"Application"_s;
}
}

Category AppEntries::categoryFor(const QStringList &categories)
{
    if (categories.contains(u"Game"_s)) {
        return Category::Games;
    }
    if (categories.contains(u"WebBrowser"_s)) {
        return Category::Browsers;
    }
    if (categories.contains(u"AudioVideoEditing"_s)) {
        return Category::Other; // an editor is not a player
    }
    // an audio application without video (Desktop Menu Specification: Audio, Video) draws no pictures that need a GPU
    if (categories.contains(u"Audio"_s) && !categories.contains(u"Video"_s)) {
        return Category::Other;
    }
    if (categories.contains(u"Player"_s) || categories.contains(u"Video"_s)) {
        return Category::Players;
    }
    return Category::Other;
}

AppEntries::AppEntries(const QString &dataHome, const QStringList &dataDirs)
    : m_dataHome(dataHome)
    , m_dataDirs(dataDirs)
{
    // QStandardPaths lists the person's folder first among all data folders: it is not a system folder
    m_dataDirs.removeAll(dataHome);
    m_dataDirs.removeAll(dataHome + u'/');
}

AppEntries AppEntries::fromEnvironment()
{
    return AppEntries(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation), QStandardPaths::standardLocations(QStandardPaths::GenericDataLocation));
}

QString AppEntries::userPath(const QString &id) const
{
    return m_dataHome + u"/applications/"_s + id;
}

QString AppEntries::systemPath(const QString &id) const
{
    return collect(m_dataHome, m_dataDirs).value(id).system;
}

QList<AppEntry> AppEntries::list() const
{
    QList<AppEntry> entries;
    const QMap<QString, Paths> map = collect(m_dataHome, m_dataDirs);
    for (auto it = map.cbegin(); it != map.cend(); ++it) {
        const QString winner = it.value().user.isEmpty() ? it.value().system : it.value().user;
        if (hiddenFromMenu(winner)) {
            continue;
        }
        entries.append(entryFrom(it.key(), it.value()));
    }
    return entries;
}

AppEntry AppEntries::find(const QString &id) const
{
    const QMap<QString, Paths> map = collect(m_dataHome, m_dataDirs);
    const auto it = map.constFind(id);
    return it == map.constEnd() ? AppEntry() : entryFrom(id, it.value());
}

AppEntry AppEntries::fromFile(const QString &path)
{
    if (!QFileInfo(path).isFile()) {
        return {};
    }
    return entryFrom(QFileInfo(path).fileName(), Paths{QString(), path});
}

bool AppEntries::setPreference(const QString &id, AppPreference preference)
{
    const Paths paths = collect(m_dataHome, m_dataDirs).value(id);
    const QString user = userPath(id);
    const bool hasUser = QFile::exists(user);

    if (preference == AppPreference::Unset) {
        if (!hasUser) {
            return true;
        }
        KDesktopFile copy(user);
        const bool stamped = copy.desktopGroup().hasKey(s_digestKey) && copy.desktopGroup().readEntry(s_digestKey) == digestOf(copy);
        copy.desktopGroup().deleteEntry(s_preferenceKey);
        copy.desktopGroup().deleteEntry(s_legacyKey);
        if (!paths.system.isEmpty()) {
            KDesktopFile system(paths.system);
            // Only a copy this page made and nobody edited goes away: it then equals the system entry again
            if (contentOf(copy, {s_copyOfKey, s_digestKey}) == contentOf(system, {s_preferenceKey, s_legacyKey}) && stamped) {
                return QFile::remove(user);
            }
        }
        if (stamped) {
            copy.desktopGroup().writeEntry(s_digestKey, digestOf(copy));
        }
        return copy.sync();
    }

    if (!hasUser) {
        if (paths.system.isEmpty()) {
            return false;
        }
        QDir().mkpath(QFileInfo(user).path());
        if (!QFile::copy(paths.system, user)) {
            return false;
        }
        QFile::setPermissions(user, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ReadGroup | QFileDevice::ReadOther);
        KDesktopFile fresh(user);
        fresh.desktopGroup().writeEntry(s_copyOfKey, fileDigest(paths.system));
        fresh.desktopGroup().writeEntry(s_preferenceKey, preference == AppPreference::OtherGpu);
        fresh.desktopGroup().writeEntry(s_digestKey, digestOf(fresh));
        return fresh.sync();
    }

    KDesktopFile copy(user);
    const bool stamped = copy.desktopGroup().hasKey(s_digestKey) && copy.desktopGroup().readEntry(s_digestKey) == digestOf(copy);
    copy.desktopGroup().deleteEntry(s_legacyKey);
    copy.desktopGroup().writeEntry(s_preferenceKey, preference == AppPreference::OtherGpu);
    if (stamped) {
        copy.desktopGroup().writeEntry(s_digestKey, digestOf(copy));
    }
    return copy.sync();
}

int AppEntries::refreshCopies()
{
    int rewritten = 0;
    const QMap<QString, Paths> map = collect(m_dataHome, m_dataDirs);
    for (auto it = map.cbegin(); it != map.cend(); ++it) {
        const Paths &paths = it.value();
        if (paths.user.isEmpty() || paths.system.isEmpty() || QFileInfo(paths.user).path() != m_dataHome + u"/applications"_s) {
            continue;
        }
        KDesktopFile copy(paths.user);
        const KConfigGroup group = copy.desktopGroup();
        if (!group.hasKey(s_digestKey) || group.readEntry(s_digestKey) != digestOf(copy)) {
            continue; // not ours, or the person edited it
        }
        const QString current = fileDigest(paths.system);
        if (group.readEntry(s_copyOfKey) == current) {
            continue;
        }
        const AppPreference preference = preferenceIn(copy);
        if (!QFile::remove(paths.user) || !QFile::copy(paths.system, paths.user)) {
            continue;
        }
        QFile::setPermissions(paths.user, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ReadGroup | QFileDevice::ReadOther);
        KDesktopFile fresh(paths.user);
        fresh.desktopGroup().writeEntry(s_copyOfKey, current);
        if (preference != AppPreference::Unset) {
            fresh.desktopGroup().writeEntry(s_preferenceKey, preference == AppPreference::OtherGpu);
        }
        fresh.desktopGroup().writeEntry(s_digestKey, digestOf(fresh));
        if (fresh.sync()) {
            ++rewritten;
        }
    }
    return rewritten;
}

}
