// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "memorykcm.h"
#include "memorysettings.h"

#include <KAuth/Action>
#include <KAuth/ActionReply>
#include <KAuth/ExecuteJob>
#include <KLocalizedString>
#include <KPluginFactory>

using namespace Qt::StringLiterals;

K_PLUGIN_CLASS_WITH_JSON(MemoryKcm, "kcm_sparkystereo_memory.json")

MemoryKcm::MemoryKcm(QObject *parent, const KPluginMetaData &data)
    : KQuickConfigModule(parent, data)
{
    setButtons(Apply | Default);
}

bool MemoryKcm::cushionEnabled() const
{
    return m_cushionEnabled;
}

void MemoryKcm::setCushionEnabled(bool enabled)
{
    if (enabled == m_cushionEnabled) {
        return;
    }
    m_cushionEnabled = enabled;
    Q_EMIT cushionEnabledChanged();
    updateState();
}

QString MemoryKcm::cushionState() const
{
    return m_cushionState;
}

QString MemoryKcm::cushionMode() const
{
    return m_cushionMode;
}

QString MemoryKcm::cushionArea() const
{
    return m_cushionArea;
}

QString MemoryKcm::errorText() const
{
    return m_errorText;
}

void MemoryKcm::load()
{
    m_savedCushionEnabled = MemorySettings::readValue(MemorySettings::cushionConfigPath(), u"CUSHION_SWAP"_s) != u"off"_s;
    m_cushionEnabled = m_savedCushionEnabled;

    readCushionStatus();
    readProblems();

    Q_EMIT cushionEnabledChanged();
    Q_EMIT statusChanged();
    updateState();
}

void MemoryKcm::save()
{
    KAuth::Action action(u"org.sparkylinux.sparkystereo.memory.savecushion"_s);
    action.setHelperId(u"org.sparkylinux.sparkystereo.memory"_s);
    action.setArguments({
        {u"cushion"_s, m_cushionEnabled ? u"on"_s : u"off"_s},
    });
    KAuth::ExecuteJob *job = action.execute();
    connect(job, &KJob::result, this, [this, job] {
        const bool success = job->error() == KJob::NoError;
        if (success) {
            m_errorText.clear();
        } else if (job->error() == KAuth::ActionReply::AuthorizationDeniedError || job->error() == KAuth::ActionReply::UserCancelledError) {
            m_errorText = i18nc("@info", "Not saved: not authorized to change these settings.");
        } else {
            m_errorText = i18nc("@info %1 is the error", "Not saved: %1", job->errorString().isEmpty() ? QString::number(job->error()) : job->errorString());
        }
        Q_EMIT errorTextChanged();
        if (success) {
            load();
        } else {
            updateState();
        }
        Q_EMIT saveFinished(success);
    });
    job->start();
}

void MemoryKcm::defaults()
{
    setCushionEnabled(true);
}

void MemoryKcm::updateState()
{
    setNeedsSave(m_cushionEnabled != m_savedCushionEnabled);
    setRepresentsDefaults(m_cushionEnabled);
}

#include "memorykcm.moc"
