// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "appentries.h"
#include "gpuinventory.h"
#include "graphicssettings.h"
#include "machinerecord.h"
#include "paint.h"
#include "powerprofiles.h"
#include "problems.h"
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
    Q_PROPERTY(bool vramProtection READ vramProtection WRITE setVramProtection NOTIFY changed)
    Q_PROPERTY(bool copyBack READ copyBack WRITE setCopyBack NOTIFY changed)
    Q_PROPERTY(QString copyBackMachineText READ copyBackMachineText NOTIFY changed)
    Q_PROPERTY(bool copyBackSetInSession READ copyBackSetInSession NOTIFY changed)
    Q_PROPERTY(bool otherGpu READ otherGpu WRITE setOtherGpu NOTIFY changed)
    Q_PROPERTY(bool otherGpuSetInSession READ otherGpuSetInSession NOTIFY changed)
    Q_PROPERTY(QString appFilter READ appFilter WRITE setAppFilter NOTIFY appsChanged)
    Q_PROPERTY(QVariantList apps READ apps NOTIFY appsChanged)
    Q_PROPERTY(int hiddenApps READ hiddenApps NOTIFY appsChanged)
    Q_PROPERTY(QVariantList appOptions READ appOptions CONSTANT)
    Q_PROPERTY(QVariantList powerActions READ powerActions NOTIFY changed)
    // Paint windows (ORDER 518): how programs made with Qt Widgets paint, by kind of program and by program
    Q_PROPERTY(QVariantList paintKinds READ paintKinds NOTIFY changed)
    Q_PROPERTY(QVariantList paintOptions READ paintOptions CONSTANT)
    Q_PROPERTY(QVariantList paintProgramOptions READ paintProgramOptions CONSTANT)
    Q_PROPERTY(bool paintSetInSession READ paintSetInSession NOTIFY changed)
    Q_PROPERTY(bool canPaintOnGpu READ canPaintOnGpu NOTIFY changed)
    Q_PROPERTY(QString errorText READ errorText NOTIFY changed)
    // Each saved choice that cannot be used, and each failed step of the package: text, and the GPUs offered instead
    Q_PROPERTY(QVariantList problems READ problems NOTIFY changed)

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
    bool vramProtection() const;
    void setVramProtection(bool enabled);
    bool copyBack() const;
    void setCopyBack(bool copyBack);
    QString copyBackMachineText() const;
    bool copyBackSetInSession() const;
    bool otherGpu() const;
    void setOtherGpu(bool otherGpu);
    bool otherGpuSetInSession() const;
    QString appFilter() const;
    void setAppFilter(const QString &filter);
    QVariantList apps() const;
    int hiddenApps() const;
    QVariantList appOptions() const;
    QVariantList powerActions() const;
    QVariantList paintKinds() const;
    QVariantList paintOptions() const;
    QVariantList paintProgramOptions() const;
    bool paintSetInSession() const;
    bool canPaintOnGpu() const;
    Q_INVOKABLE void setPaintKind(const QString &key, const QString &choice);
    Q_INVOKABLE void setPaintProgram(const QString &id, const QString &choice);
    QString errorText() const;
    QVariantList problems() const;

    // The person's explicit answer to a problem: draw the desktop (key "main-gpu") or a kind of program on that GPU
    Q_INVOKABLE void runProblemAction(const QString &package, const QString &key, const QString &id);
    Q_INVOKABLE void useGpu(const QString &key, const QString &id);
    Q_INVOKABLE void setCategoryChoice(const QString &key, const QString &choice);
    Q_INVOKABLE void setAppPreference(const QString &id, int preference);
    Q_INVOKABLE void setPowerAction(const QString &name, bool enabled);
    Q_INVOKABLE QVariantList choiceOptions(const QString &current) const;

    void load() override;
    void save() override;
    void defaults() override;

Q_SIGNALS:
    void saveFinished(bool success);
    void changed();
    void appsChanged();

private:
    SparkyGraphics::Resolver resolver() const;
    QString gpuLabel(int index) const;
    QString reasonText(const SparkyGraphics::Resolution &resolution) const;
    QString reasonTextOf(const QString &reason) const;
    int indexOf(const QString &id) const;
    QString categoryLabel(SparkyGraphics::Category category) const;
    SparkyGraphics::AppPreference pendingPreference(const SparkyGraphics::AppEntry &entry) const;
    void updateState();
    // The saved choices' problems as they are now, against the person's own file (not the pending changes)
    QList<SparkyGraphics::Problem> liveProblems(const SparkyGraphics::GraphicsSettings &settings) const;
    // Keeps the saved choices' problems that are there and clears the ones that are over
    void syncKept();

    QString m_root;
    QList<SparkyGraphics::Gpu> m_gpus;
    SparkyGraphics::GraphicsSettings m_settings;
    SparkyGraphics::MachineRecord m_record;
    SparkyGraphics::ProfileReading m_profile;
    QList<SparkyGraphics::AppEntry> m_apps;
    QMap<QString, int> m_appChanges;
    QList<SparkyGraphics::PowerAction> m_actions;
    QMap<QString, bool> m_actionChanges;
    SparkyGraphics::PaintSettings m_paint;
    SparkyGraphics::PaintRecord m_paintRecord;
    QString wayLabel(SparkyGraphics::PaintWay way) const;
    QString paintNowText(const SparkyGraphics::PaintResolution &resolution) const;
    QString paintWhyText(const SparkyGraphics::PaintResolution &resolution) const;
    SparkyGraphics::PaintFacts paintFacts() const;
    QString m_appFilter;
    QString m_errorText;
    bool m_vramProtection = false;
    bool m_savedVramProtection = false;
    bool m_savingVram = false;
    bool m_handSet = false;
    int m_runningMain = -1;
};
