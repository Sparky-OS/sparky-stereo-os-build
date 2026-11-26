// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "savermodel.h"

#include <KQuickConfigModule>

#include <QColor>

/* System Settings' Screensavers page. It edits the stereo show's own keys
 * (stereoshowrc, the file Screen Locking edits too) and keeps no copy of
 * any; what belongs to other pages is shown and linked, not edited here. */
class SaversKcm : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(SaverModel *savers READ savers CONSTANT)
    Q_PROPERTY(bool showEnabled READ showEnabled WRITE setShowEnabled NOTIFY settingsChanged)
    Q_PROPERTY(int startMinutes READ startMinutes WRITE setStartMinutes NOTIFY settingsChanged)
    Q_PROPERTY(int changeMinutes READ changeMinutes WRITE setChangeMinutes NOTIFY settingsChanged)
    Q_PROPERTY(bool lockAutomatically READ lockAutomatically NOTIFY otherPagesChanged)
    Q_PROPERTY(int lockMinutes READ lockMinutes NOTIFY otherPagesChanged)
    Q_PROPERTY(QStringList desktopKinds READ desktopKinds NOTIFY otherPagesChanged)
    Q_PROPERTY(QString lockKind READ lockKind NOTIFY otherPagesChanged)
    Q_PROPERTY(QVariantList wallpaperKinds READ wallpaperKinds NOTIFY otherPagesChanged)
    Q_PROPERTY(bool varietyInstalled READ varietyInstalled CONSTANT)
    Q_PROPERTY(QString initialSaver READ initialSaver CONSTANT)

public:
    SaversKcm(QObject *parent, const KPluginMetaData &data);

    SaverModel *savers() { return &m_model; }
    bool showEnabled() const { return m_enabled; }
    void setShowEnabled(bool enabled);
    int startMinutes() const { return m_idleSeconds / 60; }
    void setStartMinutes(int minutes);
    int changeMinutes() const { return m_cycleSeconds / 60; }
    void setChangeMinutes(int minutes);
    bool lockAutomatically() const { return m_autolock; }
    int lockMinutes() const { return m_lockMinutes; }
    QStringList desktopKinds() const { return m_desktopKinds; }
    QString lockKind() const { return m_lockKind; }
    QVariantList wallpaperKinds() const { return m_wallpaperKinds; }
    bool varietyInstalled() const;
    /* The saver selected when the page opens: the first of the list, or the one a caller names (SPARKY_SAVER_SELECT). */
    QString initialSaver() const { return qEnvironmentVariable("SPARKY_SAVER_SELECT"); }

    Q_INVOKABLE QString kindName(const QString &plugin) const;
    Q_INVOKABLE bool kindInstalled(const QString &plugin) const;
    Q_INVOKABLE bool openVariety();
    Q_INVOKABLE void refreshOtherPages();
    /* The colour for a quieter text: the wanted one when it can be read on that background, else the nearest that can (ReadableText). */
    Q_INVOKABLE QColor readableColor(const QColor &wanted, const QColor &text, const QColor &background) const;

public Q_SLOTS:
    void load() override;
    void save() override;
    void defaults() override;

Q_SIGNALS:
    void settingsChanged();
    void otherPagesChanged();

private:
    void changed();
    SaverModel m_model;
    QStringList m_desktopKinds;
    QString m_lockKind;
    QVariantList m_wallpaperKinds;
    QStringList m_savedDisabled, m_savedFlat;
    int m_idleSeconds = 8100, m_cycleSeconds = 600, m_lockMinutes = 5;
    int m_savedIdle = 8100, m_savedCycle = 600;
    bool m_enabled = true, m_savedEnabled = true, m_autolock = true;
};
