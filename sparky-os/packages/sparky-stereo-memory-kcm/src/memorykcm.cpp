// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "memorykcm.h"
#include "memorysettings.h"

#include <KAuth/Action>
#include <KAuth/ActionReply>
#include <KAuth/ExecuteJob>
#include <KLocalizedString>
#include <KPluginFactory>

#include <QFile>
#include <QProcess>

using namespace Qt::StringLiterals;

K_PLUGIN_CLASS_WITH_JSON(MemoryKcm, "kcm_sparkystereo_memory.json")

static const QStringList s_zramValues = {u"auto"_s, u"on"_s, u"off"_s};

static QString autoReasonText(const QVariantMap &decision)
{
    const QString choice = decision.value(u"DECISION"_s).toString();
    const QString mode = decision.value(u"MODE"_s).toString();
    if (mode == u"on"_s && choice == mode) {
        return i18nc("@info zram reason", "Switched on by the zram configuration");
    }
    if (mode == u"off"_s && choice == mode) {
        return i18nc("@info zram reason", "Switched off by the zram configuration");
    }
    bool ramValid = false;
    const qulonglong ram = decision.value(u"RAM_KIB"_s).toString().toULongLong(&ramValid);
    bool limitValid = false;
    const qulonglong configuredLimit = qEnvironmentVariable("ZRAM_RAM_LIMIT_KIB").toULongLong(&limitValid);
    const qulonglong limit = limitValid ? configuredLimit : 9437184;
    const QString storage = decision.value(u"STORAGE"_s).toString();
    if (mode == u"auto"_s && ramValid && ram > 0) {
        if (choice == u"on"_s && ram <= limit) {
            return i18nc("@info zram reason", "%1 MiB of RAM: within the automatic zram RAM limit", ram / 1024);
        }
        if (choice == u"on"_s && ram > limit) {
            if (storage == u"emmc"_s) return i18nc("@info zram reason", "The swap area is on eMMC storage");
            if (storage == u"sd-card"_s) return i18nc("@info zram reason", "The swap area is on an SD card");
            if (storage == u"rotating"_s) return i18nc("@info zram reason", "The swap area is on a rotating disk");
            if (storage == u"removable"_s) return i18nc("@info zram reason", "The swap area is on removable storage");
            if (storage == u"usb"_s) return i18nc("@info zram reason", "The swap area is on USB storage");
        }
        if (choice == u"off"_s && ram > limit) {
            if (storage == u"fast"_s) return i18nc("@info zram reason", "%1 MiB of RAM and the swap area on fast storage", ram / 1024);
            if (storage == u"unknown"_s) return i18nc("@info zram reason", "%1 MiB of RAM; the swap storage type could not be identified", ram / 1024);
        }
    }
    return i18nc("@info zram reason", "Unrecognized zram decision; zram-auto says: %1", decision.value(u"REASON"_s).toString());
}

MemoryKcm::MemoryKcm(QObject *parent, const KPluginMetaData &data)
    : KQuickConfigModule(parent, data)
{
    setButtons(Apply | Default);
}

int MemoryKcm::zramMode() const
{
    return m_zramMode;
}

void MemoryKcm::setZramMode(int mode)
{
    if (mode == m_zramMode || mode < Automatic || mode > Off) {
        return;
    }
    m_zramMode = mode;
    Q_EMIT zramModeChanged();
    updateState();
}

bool MemoryKcm::autoZramOn() const
{
    return m_autoZramOn;
}

QString MemoryKcm::autoReason() const
{
    return m_autoReason;
}

bool MemoryKcm::zramActive() const
{
    return m_zramActive;
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
    const QString zram = MemorySettings::readValue(MemorySettings::zramConfigPath(), u"ZRAM"_s);
    m_savedZramMode = zram == u"on"_s ? On : zram == u"off"_s ? Off : Automatic;
    m_savedCushionEnabled = MemorySettings::readValue(MemorySettings::cushionConfigPath(), u"CUSHION_SWAP"_s) != u"off"_s;
    m_zramMode = m_savedZramMode;
    m_cushionEnabled = m_savedCushionEnabled;

    // What Automatic decides for this computer, and why, from the same
    // program zram-generator runs at boot; it ignores the ZRAM= override here.
    QProcess autoDecision;
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    environment.insert(u"SPARKY_ZRAM_CONFIG"_s, u"/nonexistent"_s);
    autoDecision.setProcessEnvironment(environment);
    autoDecision.start(MemorySettings::zramAutoPath(), {u"--explain"_s});
    autoDecision.waitForFinished(3000);
    const QVariantMap decision = MemorySettings::readKeyValues(autoDecision.readAllStandardOutput());
    m_autoZramOn = decision.value(u"DECISION"_s).toString() == u"on"_s;
    m_autoReason = autoReasonText(decision);
    const QString choice = decision.value(u"DECISION"_s).toString();
    m_autoDecisionText = choice == u"on"_s
        ? i18nc("@info %1 is the reason", "Automatic means on for this computer: %1.", m_autoReason)
        : choice == u"off"_s
        ? i18nc("@info %1 is the reason", "Automatic means off for this computer: %1.", m_autoReason)
        : m_autoReason;

    m_zramActive = false;
    QFile swaps(MemorySettings::swapsPath());
    if (swaps.open(QIODevice::ReadOnly)) {
        m_zramActive = swaps.readAll().contains("/dev/zram");
    }

    readCushionStatus();
    readProblems();

    Q_EMIT zramModeChanged();
    Q_EMIT cushionEnabledChanged();
    Q_EMIT statusChanged();
    updateState();
}

void MemoryKcm::save()
{
    KAuth::Action action(u"org.sparkylinux.sparkystereo.memory.save"_s);
    action.setHelperId(u"org.sparkylinux.sparkystereo.memory"_s);
    action.setArguments({
        {u"zram"_s, s_zramValues.at(m_zramMode)},
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
    setZramMode(Automatic);
    setCushionEnabled(true);
}

void MemoryKcm::updateState()
{
    setNeedsSave(m_zramMode != m_savedZramMode || m_cushionEnabled != m_savedCushionEnabled);
    setRepresentsDefaults(m_zramMode == Automatic && m_cushionEnabled);
}

#include "memorykcm.moc"
