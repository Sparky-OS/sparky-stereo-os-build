// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include "saverskcm.h"

#include "readabletext.h"
#include "saverpreview.h"
#include "showstore.h"

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
const int IDLE = ShowStore::IDLE, CYCLE = ShowStore::CYCLE;

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
    // the defaults: the show on, its two times, every catalogue saver and no 2D one
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
    const ShowStore store = ShowStore::read();
    m_enabled = m_savedEnabled = store.enabled;
    m_idleSeconds = m_savedIdle = store.idleSeconds;
    m_cycleSeconds = m_savedCycle = store.cycleSeconds;
    m_savedDisabled = store.disabled;
    m_savedFlat = store.flat;
    m_model.setStore(m_savedDisabled, m_savedFlat);
    refreshOtherPages();
    Q_EMIT settingsChanged();
    changed();
}

void SaversKcm::save()
{
    ShowStore store;
    store.enabled = m_enabled;
    store.idleSeconds = m_idleSeconds;
    store.cycleSeconds = m_cycleSeconds;
    store.disabled = m_model.disabled();
    store.flat = m_model.flat();
    store.writeShow();
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
    const ShowStore store = ShowStore::read();
    m_autolock = store.autolock;
    m_lockMinutes = store.lockMinutes;
    m_lockKind = store.lockKind;
    m_desktopKinds = store.desktopKinds;

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

QColor SaversKcm::readableColor(const QColor &wanted, const QColor &text, const QColor &background) const
{
    return ReadableText::colour(wanted, text, background);
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
