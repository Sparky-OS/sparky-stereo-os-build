// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "appentries.h"
#include "gpuinventory.h"
#include "graphicssettings.h"
#include "machinerecord.h"
#include "powerprofiles.h"
#include "resolver.h"

#include <KQuickConfigModule>

#include <QMap>
#include <QVariantList>

class GraphicsKcm : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(QVariantList gpus READ gpus NOTIFY changed)
    Q_PROPERTY(int gpuCount READ gpuCount NOTIFY changed)
    Q_PROPERTY(bool multiGpu READ multiGpu NOTIFY changed)
    Q_PROPERTY(QString mainChoice READ mainChoice WRITE setMainChoice NOTIFY changed)
    Q_PROPERTY(QVariantList mainOptions READ mainOptions NOTIFY changed)
    Q_PROPERTY(QString mainNowText READ mainNowText NOTIFY changed)
    Q_PROPERTY(bool mainAppliesLater READ mainAppliesLater NOTIFY changed)
    Q_PROPERTY(bool mainSetByHand READ mainSetByHand NOTIFY changed)
    Q_PROPERTY(QVariantList categories READ categories NOTIFY changed)
    Q_PROPERTY(QString profile READ profile NOTIFY changed)
    Q_PROPERTY(QString profileText READ profileText NOTIFY changed)
    Q_PROPERTY(QString measuredText READ measuredText NOTIFY changed)
    Q_PROPERTY(bool copyBack READ copyBack WRITE setCopyBack NOTIFY changed)
    Q_PROPERTY(QString copyBackMachineText READ copyBackMachineText NOTIFY changed)
    Q_PROPERTY(bool copyBackSetInSession READ copyBackSetInSession NOTIFY changed)
    Q_PROPERTY(QString appFilter READ appFilter WRITE setAppFilter NOTIFY appsChanged)
    Q_PROPERTY(QVariantList apps READ apps NOTIFY appsChanged)
    Q_PROPERTY(int hiddenApps READ hiddenApps NOTIFY appsChanged)
    Q_PROPERTY(QVariantList appOptions READ appOptions CONSTANT)
    Q_PROPERTY(QVariantList powerActions READ powerActions NOTIFY changed)
    Q_PROPERTY(QString errorText READ errorText NOTIFY changed)

public:
    GraphicsKcm(QObject *parent, const KPluginMetaData &data);

    QVariantList gpus() const;
    int gpuCount() const;
    bool multiGpu() const;
    QString mainChoice() const;
    void setMainChoice(const QString &choice);
    QVariantList mainOptions() const;
    QString mainNowText() const;
    bool mainAppliesLater() const;
    bool mainSetByHand() const;
    QVariantList categories() const;
    QString profile() const;
    QString profileText() const;
    QString measuredText() const;
    bool copyBack() const;
    void setCopyBack(bool copyBack);
    QString copyBackMachineText() const;
    bool copyBackSetInSession() const;
    QString appFilter() const;
    void setAppFilter(const QString &filter);
    QVariantList apps() const;
    int hiddenApps() const;
    QVariantList appOptions() const;
    QVariantList powerActions() const;
    QString errorText() const;

    Q_INVOKABLE void setCategoryChoice(const QString &key, const QString &choice);
    Q_INVOKABLE void setAppPreference(const QString &id, int preference);
    Q_INVOKABLE void setPowerAction(const QString &name, bool enabled);
    Q_INVOKABLE QVariantList choiceOptions(const QString &current) const;

    void load() override;
    void save() override;
    void defaults() override;

Q_SIGNALS:
    void changed();
    void appsChanged();

private:
    SparkyGraphics::Resolver resolver() const;
    QString gpuLabel(int index) const;
    QString reasonText(const SparkyGraphics::Resolution &resolution) const;
    QString categoryLabel(SparkyGraphics::Category category) const;
    SparkyGraphics::AppPreference pendingPreference(const SparkyGraphics::AppEntry &entry) const;
    void updateState();

    QString m_root;
    QList<SparkyGraphics::Gpu> m_gpus;
    SparkyGraphics::GraphicsSettings m_settings;
    SparkyGraphics::MachineRecord m_record;
    SparkyGraphics::PowerProfile m_profile = SparkyGraphics::PowerProfile::Balanced;
    QList<SparkyGraphics::AppEntry> m_apps;
    QMap<QString, int> m_appChanges;
    QList<SparkyGraphics::PowerAction> m_actions;
    QMap<QString, bool> m_actionChanges;
    QString m_appFilter;
    QString m_errorText;
    bool m_handSet = false;
    int m_runningMain = -1;
};
