// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include "showstore.h"

#include <KConfig>
#include <KConfigGroup>
#include <KSharedConfig>

namespace
{
const QString SHOW = QStringLiteral("stereoshowrc");

// one comma-separated value, as the show's controller reads it (gl-stereo, savers/preferences.py)
QStringList names(const QString &value)
{
    QStringList out;
    for (const QString &name : value.split(QLatin1Char(','), Qt::SkipEmptyParts)) {
        if (!name.trimmed().isEmpty()) {
            out << name.trimmed();
        }
    }
    out.sort();
    return out;
}
}

ShowStore ShowStore::read()
{
    ShowStore store;
    auto config = KSharedConfig::openConfig(SHOW, KConfig::FullConfig);
    config->reparseConfiguration();
    const KConfigGroup general(config, QStringLiteral("General"));
    store.enabled = general.readEntry("Enabled", true);
    store.idleSeconds = qBound(60, general.readEntry("IdleSeconds", IDLE), 86400);
    store.cycleSeconds = qBound(60, general.readEntry("CycleSeconds", CYCLE), 86400);
    store.disabled = names(general.readEntry("DisabledSavers", QString()));
    store.flat = names(general.readEntry("FlatSavers", QString()));

    // Screen Locking's own values, shown by the page and edited there
    KConfig lockFile(QStringLiteral("kscreenlockerrc"));
    const KConfigGroup daemon(&lockFile, QStringLiteral("Daemon"));
    store.autolock = daemon.readEntry("Autolock", true);
    store.lockMinutes = daemon.readEntry("Timeout", 5);
    store.lockKind = KConfigGroup(&lockFile, QStringLiteral("Greeter")).readEntry("WallpaperPlugin", QStringLiteral("org.kde.image"));

    // the desktop's wallpaper kind, one per desktop, as plasmashell keeps it
    KConfig desktop(QStringLiteral("plasma-org.kde.plasma.desktop-appletsrc"));
    const KConfigGroup containments(&desktop, QStringLiteral("Containments"));
    for (const QString &id : containments.groupList()) {
        const QString kind = KConfigGroup(&containments, id).readEntry("wallpaperplugin", QString());
        if (!kind.isEmpty() && !store.desktopKinds.contains(kind)) {
            store.desktopKinds << kind;
        }
    }
    if (store.desktopKinds.isEmpty()) {
        store.desktopKinds << QStringLiteral("org.kde.image"); // Plasma's own default before a desktop was ever configured
    }
    return store;
}

void ShowStore::writeShow() const
{
    auto config = KSharedConfig::openConfig(SHOW, KConfig::FullConfig);
    KConfigGroup general(config, QStringLiteral("General"));
    // the notify flag: a running show and the Screen Locking page follow at once (KConfigWatcher)
    general.writeEntry("Enabled", enabled, KConfig::Notify);
    general.writeEntry("IdleSeconds", idleSeconds, KConfig::Notify);
    general.writeEntry("CycleSeconds", cycleSeconds, KConfig::Notify);
    general.writeEntry("DisabledSavers", disabled.join(QLatin1Char(',')), KConfig::Notify);
    if (!flat.isEmpty() || general.hasKey("FlatSavers")) { // nothing ticked and nothing stored: the key is not created
        general.writeEntry("FlatSavers", flat.join(QLatin1Char(',')), KConfig::Notify);
    }
    config->sync();
}
