// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include "saverskcm.h"

#include "saverpreview.h"

#include <KConfigGroup>
#include <KLocalizedString>
#include <KPluginFactory>
#include <KPluginMetaData>
#include <KSharedConfig>

#include <QDir>
#include <QProcess>
#include <QQmlEngine>
#include <QStandardPaths>

K_PLUGIN_CLASS_WITH_JSON(SaversKcm, "kcm_sparkystereo_screensavers.json")

namespace
{
// The show's own file and defaults (gl-stereo-show: /etc/xdg/stereoshowrc, stereoshow.kcfg)
const QString SHOW = QStringLiteral("stereoshowrc");
const int IDLE = 8100, CYCLE = 600;

QStringList names(const QString &value)
{
    QStringList out;
    for (const QString &name : value.split(QLatin1Char(','), Qt::SkipEmptyParts)) {
        out << name.trimmed();
    }
    out.removeAll(QString());
    out.sort();
    return out;
}

QString wallpaperFile(const QString &plugin)
{
    return QStandardPaths::locate(QStandardPaths::GenericDataLocation, QStringLiteral("plasma/wallpapers/%1/metadata.json").arg(plugin));
}
}

SaversKcm::SaversKcm(QObject *parent, const KPluginMetaData &data)
    : KQuickConfigModule(parent, data)
{
    qmlRegisterType<SaverPreview>("org.sparky.stereo.screensavers", 1, 0, "SaverPreview");
    qmlRegisterUncreatableType<SaverModel>("org.sparky.stereo.screensavers", 1, 0, "SaverModel", QStringLiteral("the page's list"));
    setButtons(Apply | Default);
    m_model.load(SaverModel::paths());
    connect(&m_model, &SaverModel::ticksChanged, this, &SaversKcm::changed);
}

void SaversKcm::changed()
{
    setNeedsSave(m_enabled != m_savedEnabled || m_idleSeconds != m_savedIdle || m_cycleSeconds != m_savedCycle || m_model.disabled() != m_savedDisabled
                 || m_model.flat() != m_savedFlat);
    QStringList allTicked; // the defaults: the show on, its two times, every catalogue saver and no 2D one
    setRepresentsDefaults(m_enabled && m_idleSeconds == IDLE && m_cycleSeconds == CYCLE && m_model.disabled().isEmpty() && m_model.flat().isEmpty());
}

void SaversKcm::setShowEnabled(bool enabled)
{
    if (enabled != m_enabled) {
        m_enabled = enabled;
        Q_EMIT settingsChanged();
        changed();
    }
}

void SaversKcm::setStartMinutes(int minutes)
{
    const int seconds = qBound(60, minutes * 60, 86400);
    if (seconds != m_idleSeconds) {
        m_idleSeconds = seconds;
        Q_EMIT settingsChanged();
        changed();
    }
}

void SaversKcm::setChangeMinutes(int minutes)
{
    const int seconds = qBound(60, minutes * 60, 86400);
    if (seconds != m_cycleSeconds) {
        m_cycleSeconds = seconds;
        Q_EMIT settingsChanged();
        changed();
    }
}

void SaversKcm::load()
{
    auto config = KSharedConfig::openConfig(SHOW, KConfig::FullConfig);
    config->reparseConfiguration();
    const KConfigGroup general(config, QStringLiteral("General"));
    m_enabled = m_savedEnabled = general.readEntry("Enabled", true);
    m_idleSeconds = m_savedIdle = qBound(60, general.readEntry("IdleSeconds", IDLE), 86400);
    m_cycleSeconds = m_savedCycle = qBound(60, general.readEntry("CycleSeconds", CYCLE), 86400);
    // one comma-separated value each, as the show's controller reads them (savers/preferences.py)
    m_savedDisabled = names(general.readEntry("DisabledSavers", QString()));
    m_savedFlat = names(general.readEntry("FlatSavers", QString()));
    m_model.setStore(m_savedDisabled, m_savedFlat);
    refreshOtherPages();
    Q_EMIT settingsChanged();
    changed();
}

void SaversKcm::save()
{
    auto config = KSharedConfig::openConfig(SHOW, KConfig::FullConfig);
    KConfigGroup general(config, QStringLiteral("General"));
    // the notify flag: a running show and the Screen Locking page follow at once (KConfigWatcher)
    general.writeEntry("Enabled", m_enabled, KConfig::Notify);
    general.writeEntry("IdleSeconds", m_idleSeconds, KConfig::Notify);
    general.writeEntry("CycleSeconds", m_cycleSeconds, KConfig::Notify);
    general.writeEntry("DisabledSavers", m_model.disabled().join(QLatin1Char(',')), KConfig::Notify);
    const QString flat = m_model.flat().join(QLatin1Char(','));
    if (flat.isEmpty() && !general.hasKey("FlatSavers")) {
        // nothing ticked and nothing stored: the key is not created
    } else {
        general.writeEntry("FlatSavers", flat, KConfig::Notify);
    }
    config->sync();
    load();
}

void SaversKcm::defaults()
{
    m_enabled = true;
    m_idleSeconds = IDLE;
    m_cycleSeconds = CYCLE;
    m_model.tickAllStereo();
    Q_EMIT settingsChanged();
    changed();
}

void SaversKcm::refreshOtherPages()
{
    // Screen Locking's own values, shown here and edited there
    KConfig lockFile(QStringLiteral("kscreenlockerrc"));
    const KConfigGroup daemon(&lockFile, QStringLiteral("Daemon"));
    m_autolock = daemon.readEntry("Autolock", true);
    m_lockMinutes = daemon.readEntry("Timeout", 5);
    const KConfigGroup greeter(&lockFile, QStringLiteral("Greeter"));
    m_lockKind = greeter.readEntry("WallpaperPlugin", QStringLiteral("org.kde.image"));

    // the desktop's wallpaper kind, one per desktop, as plasmashell keeps it
    m_desktopKinds.clear();
    KConfig desktop(QStringLiteral("plasma-org.kde.plasma.desktop-appletsrc"));
    const KConfigGroup containments(&desktop, QStringLiteral("Containments"));
    for (const QString &id : containments.groupList()) {
        const KConfigGroup containment(&containments, id);
        const QString kind = containment.readEntry("wallpaperplugin", QString());
        if (!kind.isEmpty() && !m_desktopKinds.contains(kind)) {
            m_desktopKinds << kind;
        }
    }
    if (m_desktopKinds.isEmpty()) {
        m_desktopKinds << QStringLiteral("org.kde.image"); // Plasma's own default before a desktop was ever configured
    }

    m_wallpaperKinds.clear();
    QStringList seen;
    for (const QString &dir : QStandardPaths::locateAll(QStandardPaths::GenericDataLocation, QStringLiteral("plasma/wallpapers"), QStandardPaths::LocateDirectory)) {
        for (const QString &plugin : QDir(dir).entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
            if (!seen.contains(plugin) && QFile::exists(dir + QLatin1Char('/') + plugin + QLatin1String("/metadata.json"))) {
                seen << plugin;
                m_wallpaperKinds << QVariantMap{{QStringLiteral("id"), plugin}, {QStringLiteral("name"), kindName(plugin)}};
            }
        }
    }
    Q_EMIT otherPagesChanged();
}

QString SaversKcm::kindName(const QString &plugin) const
{
    const QString file = wallpaperFile(plugin);
    if (file.isEmpty()) {
        return plugin;
    }
    const QString name = KPluginMetaData::fromJsonFile(file).name();
    return name.isEmpty() ? plugin : name;
}

bool SaversKcm::kindInstalled(const QString &plugin) const
{
    return !wallpaperFile(plugin).isEmpty();
}

bool SaversKcm::varietyInstalled() const
{
    return !QStandardPaths::findExecutable(QStringLiteral("variety")).isEmpty();
}

bool SaversKcm::openVariety()
{
    return QProcess::startDetached(QStringLiteral("variety"), {QStringLiteral("--preferences")});
}

#include "saverskcm.moc"
