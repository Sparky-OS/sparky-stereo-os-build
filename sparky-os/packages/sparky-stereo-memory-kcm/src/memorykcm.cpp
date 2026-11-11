// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "memorykcm.h"
#include "memorysettings.h"

#include <KAuth/Action>
#include <KAuth/ActionReply>
#include <KAuth/ExecuteJob>
#include <KLocalizedString>
#include <KPluginFactory>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QProcessEnvironment>

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

    refreshZram();
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


void MemoryKcm::refreshZram()
{
    if (m_zramReading || m_zramBusy) {
        return;
    }
    m_zramReading = true;
    auto *process = new QProcess(this);
    auto environment = QProcessEnvironment::systemEnvironment();
    environment.insert(u"LANGUAGE"_s, KLocalizedString::languages().join(u':'));
    process->setProcessEnvironment(environment);
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            m_zramReading = false;
            m_zramKnown = false;
            m_zram.insert(u"known"_s, false);
            m_zram.insert(u"error"_s, process->errorString());
            Q_EMIT zramChanged();
            process->deleteLater();
        }
    });
    connect(process, &QProcess::finished, this, [this, process](int code, QProcess::ExitStatus exitStatus) {
        QJsonParseError parseError;
        const auto document = QJsonDocument::fromJson(process->readAllStandardOutput(), &parseError);
        m_zramKnown = exitStatus == QProcess::NormalExit && code == 0 && parseError.error == QJsonParseError::NoError
            && document.isObject() && document.object().value(u"installed"_s).isBool();
        if (m_zramKnown) {
            m_zram = document.object().toVariantMap();
        } else {
            const QString error = QString::fromUtf8(process->readAllStandardError()).trimmed()
                + u" "_s + parseError.errorString();
            m_zram.insert(u"error"_s, error);
        }
        m_zram.insert(u"known"_s, m_zramKnown);
        m_zramReading = false;
        Q_EMIT zramChanged();
        process->deleteLater();
    });
    process->start(u"/usr/lib/sparky-aptus-stereo-appcenter/actions/zram"_s, {u"status"_s});
}

void MemoryKcm::changeZram()
{
    if (!m_zramKnown || m_zramBusy || m_zramReading) {
        return;
    }
    m_zramBusy = true;
    auto *process = new QProcess(this);
    process->setProcessChannelMode(QProcess::MergedChannels);
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            m_zramBusy = false;
            m_errorText = process->errorString();
            Q_EMIT zramChanged();
            Q_EMIT errorTextChanged();
            process->deleteLater();
        }
    });
    connect(process, &QProcess::finished, this, [this, process](int code, QProcess::ExitStatus status) {
        m_zramBusy = false;
        m_errorText = (status == QProcess::NormalExit && code == 0) ? QString()
            : QString::fromUtf8(process->readAll()).trimmed();
        Q_EMIT errorTextChanged();
        Q_EMIT zramChanged();
        refreshZram();
        process->deleteLater();
    });
    Q_EMIT zramChanged();
    process->start(u"/usr/bin/pkexec"_s, {u"/usr/lib/sparky-aptus-stereo-appcenter/actions/zram"_s,
        m_zram.value(u"installed"_s).toBool() ? u"remove"_s : u"install"_s});
}

#include "memorykcm.moc"
