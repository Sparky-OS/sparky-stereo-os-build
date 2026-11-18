// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "pjeofficekcm.h"

#include <KConfigGroup>
#include <KLocalizedString>
#include <KPluginFactory>
#include <KSharedConfig>

#include <QDateTime>
#include <QProcess>
#include <QStandardPaths>

K_PLUGIN_CLASS_WITH_JSON(PjeOfficeKcm, "kcm_sparkystereo_pjeoffice.json")

static KConfigGroup settings()
{
    return KConfigGroup(KSharedConfig::openConfig(QStringLiteral("sparkystereopjeofficerc")), QStringLiteral("General"));
}

PjeOfficeKcm::PjeOfficeKcm(QObject *parent, const KPluginMetaData &data)
    : KQuickConfigModule(parent, data)
{
    setButtons(Apply | Default);
    connect(&m_state, &SignerState::probeFinished, this, &PjeOfficeKcm::stateChanged);
    m_poll.setInterval(3000);
    connect(&m_poll, &QTimer::timeout, &m_state, &SignerState::probe);
    m_poll.start();
    m_state.probe();
    load();
}

void PjeOfficeKcm::setAutostart(bool on)
{
    if (m_autostart != on) {
        m_autostart = on;
        Q_EMIT autostartChanged();
        setNeedsSave(true);
        setRepresentsDefaults(on);
    }
}

void PjeOfficeKcm::load()
{
    m_autostart = settings().readEntry("Autostart", true);
    Q_EMIT autostartChanged();
    Q_EMIT stateChanged();
    setNeedsSave(false);
    setRepresentsDefaults(m_autostart);
}

void PjeOfficeKcm::save()
{
    KConfigGroup group = settings();
    group.writeEntry("Autostart", m_autostart);
    group.sync();
    setNeedsSave(false);
}

void PjeOfficeKcm::defaults()
{
    setAutostart(true);
}

QString PjeOfficeKcm::updateText() const
{
    const QString installed = SignerState::installedVersion();
    const QString reviewed = SignerState::reviewedVersion();
    if (installed.isEmpty()) {
        return i18n("PJeOffice Pro is not installed. Install it from the app center.");
    }
    if (reviewed.isEmpty() || reviewed == installed) {
        return i18n("Up to date: version %1 is the reviewed one. Updates arrive with the package, after each new version is reviewed.", installed);
    }
    return i18n("Version %1 is in use. The reviewed version %2 did not install: see the Problems page.", installed, reviewed);
}

QString PjeOfficeKcm::upstreamText() const
{
    const QJsonObject seen = SignerState::upstream();
    if (seen.isEmpty()) {
        return i18n("CNJ's update address has not been looked at yet.");
    }
    const QString when = QDateTime::fromString(seen.value(QStringLiteral("checked")).toString(), Qt::ISODate).toLocalTime().toString(Qt::TextDate);
    if (!seen.value(QStringLiteral("reachable")).toBool()) {
        return i18n("CNJ's update address could not be read on %1: %2", when, seen.value(QStringLiteral("reason")).toString());
    }
    const QString published = seen.value(QStringLiteral("published")).toString();
    return i18n("On %1 CNJ's update address named version %2.", when, published);
}

bool PjeOfficeKcm::certificateToolInstalled() const
{
    return !QStandardPaths::findExecutable(QStringLiteral("kleopatra")).isEmpty();
}

void PjeOfficeKcm::openSigner()
{
    QProcess::startDetached(SignerState::launcher(), {});
    QTimer::singleShot(2000, &m_state, &SignerState::probe);
}

void PjeOfficeKcm::openCertificateTool()
{
    QProcess::startDetached(QStringLiteral("kleopatra"), {});
}

void PjeOfficeKcm::checkUpstream()
{
    if (m_checking) {
        return;
    }
    m_checking = true;
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process]() {
        m_checking = false;
        process->deleteLater();
        Q_EMIT stateChanged();
    });
    process->start(SignerState::command(), {QStringLiteral("check")});
}

#include "pjeofficekcm.moc"
