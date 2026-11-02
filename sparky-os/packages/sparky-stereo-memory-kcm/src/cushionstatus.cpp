// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "memorykcm.h"
#include "memorysettings.h"

#include <KLocalizedString>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>
#include <cerrno>

using namespace Qt::StringLiterals;

static const QString s_engine = u"/usr/bin/sparky-stereo-problems"_s;
static const QString s_package = u"sparky-stereo-cushion-swap"_s;

void MemoryKcm::readCushionStatus()
{
    m_cushionState.clear();
    m_cushionMode.clear();
    m_cushionArea.clear();
    m_cushionProtection.clear();
    m_cushionReason.clear();
    m_cushionProblemKeys.clear();
    m_cushionStatusError.clear();
    m_cushionStatus = Unreadable;

    QFile file(MemorySettings::cushionStatusPath());
    if (!file.open(QIODevice::ReadOnly)) {
        if (errno == ENOENT) {
            m_cushionState = u"stopped"_s;
            m_cushionStatus = NotRunning;
        } else {
            m_cushionStatusError = i18nc("@info", "Could not read %1: %2", file.fileName(), file.errorString());
        }
        return;
    }
    const QByteArray bytes = file.readAll();
    if (file.error() != QFileDevice::NoError) {
        m_cushionStatusError = i18nc("@info", "Could not read %1: %2", file.fileName(), file.errorString());
        return;
    }
    const QVariantMap status = MemorySettings::readKeyValues(bytes);
    m_cushionState = status.value(u"STATE"_s).toString();
    m_cushionMode = status.value(u"MODE"_s).toString();
    m_cushionArea = status.value(u"AREA"_s).toString();
    m_cushionProtection = status.value(u"PROTECTION"_s).toString();
    m_cushionReason = status.value(u"REASON"_s).toString();
    m_cushionProblemKeys = status.value(u"PROBLEMS"_s).toString().split(QRegularExpression(u"\\s+"_s), Qt::SkipEmptyParts);

    const QString pid = status.value(u"PID"_s).toString();
    if (m_cushionState == u"stopped"_s || m_cushionState == u"disabled"_s) {
        m_cushionStatus = NotRunning;
    } else if (!pid.isEmpty() && QRegularExpression(u"^[0-9]+$"_s).match(pid).hasMatch()
               && !QFileInfo::exists(qEnvironmentVariable("SPARKY_STEREO_MEMORY_ROOT") + u"/proc/"_s + pid)) {
        m_cushionStatus = NotRunning;
    } else if (m_cushionProtection == u"yes"_s) {
        m_cushionStatus = m_cushionProblemKeys.isEmpty() ? Protected : ProtectedWithProblem;
    } else if (m_cushionProtection == u"degraded"_s) {
        m_cushionStatus = ProtectedWithProblem;
    } else if (m_cushionProtection == u"no"_s) {
        m_cushionStatus = NotProtected;
    }
    if (m_cushionStatus == Unreadable) {
        m_cushionStatusError = i18nc("@info", "Could not read the protection state from %1: missing or invalid PROTECTION.", file.fileName());
    }
}

void MemoryKcm::readProblems()
{
    m_cushionProblems.clear();
    m_cushionProblemsError.clear();
    QProcess process;
    process.start(s_engine, {u"list"_s, u"--json"_s, u"--lang"_s, KLocalizedString::languages().join(u':'), s_package});
    if (!process.waitForFinished(3000)) {
        const QString error = process.errorString();
        process.kill();
        process.waitForFinished();
        m_cushionProblemsError = i18nc("@info", "Could not read the kept problems: %1", error);
        return;
    }
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        m_cushionProblemsError = i18nc("@info", "Could not read the kept problems: %1",
                                      QString::fromUtf8(process.readAllStandardError()).trimmed() + u" (%1)"_s.arg(process.exitCode()));
        return;
    }
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(process.readAllStandardOutput(), &error);
    if (!document.isArray()) {
        m_cushionProblemsError = i18nc("@info", "Could not read the kept problems: %1", error.errorString());
        return;
    }
    QStringList found;
    for (const QJsonValue &value : document.array()) {
        const QJsonObject problem = value.toObject();
        if (problem.contains(u"unreadable"_s)) {
            m_cushionProblemsError = i18nc("@info", "Could not read the kept problems: %1",
                                          problem.value(u"file"_s).toString() + u": "_s + problem.value(u"unreadable"_s).toString());
            continue;
        }
        if (problem.value(u"package"_s).toString() != s_package) {
            continue;
        }
        if (problem.value(u"text"_s).toString().isEmpty()) {
            m_cushionProblemsError = i18nc("@info", "The problems engine returned a problem without its text.");
            continue;
        }
        found << problem.value(u"key"_s).toString();
        // Include hidden records too: hiding a notification does not repair the problem.
        m_cushionProblems << problem.toVariantMap();
    }
    for (const QString &key : std::as_const(m_cushionProblemKeys)) {
        if (!found.contains(key)) {
            m_cushionProblemsError = i18nc("@info", "The status names a problem whose text is unavailable from the problems engine. Refresh to try again.");
            break;
        }
    }
}

void MemoryKcm::refreshStatus()
{
    readCushionStatus();
    readProblems();
    Q_EMIT statusChanged();
}

void MemoryKcm::repairProblem(int index)
{
    if (m_repairing || index < 0 || index >= m_cushionProblems.size()) {
        return;
    }
    const QVariantMap problem = m_cushionProblems.at(index).toMap();
    const QString scope = problem.value(u"scope"_s).toString();
    if (problem.value(u"repair"_s).toList().isEmpty()
        || !QStringList{u"boot"_s, u"machine"_s, u"person"_s}.contains(scope)) {
        return;
    }
    QStringList arguments{u"repair"_s, u"--"_s + scope, s_package, problem.value(u"key"_s).toString()};
    QString program = s_engine;
    if (scope != u"person"_s) {
        arguments.prepend(s_engine);
        program = u"/usr/bin/pkexec"_s;
    }
    auto *process = new QProcess(this);
    process->setProcessChannelMode(QProcess::MergedChannels);
    m_errorText.clear();
    m_repairing = true;
    Q_EMIT errorTextChanged();
    Q_EMIT repairingChanged();
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            m_errorText = i18nc("@info", "The repair did not run: %1", process->errorString());
            m_repairing = false;
            Q_EMIT errorTextChanged();
            Q_EMIT repairingChanged();
            process->deleteLater();
        }
    });
    connect(process, &QProcess::finished, this, [this, process](int code, QProcess::ExitStatus status) {
        if (status != QProcess::NormalExit || code != 0) {
            m_errorText = i18nc("@info", "The repair failed (exit %1): %2", code, QString::fromUtf8(process->readAll()).trimmed());
        }
        m_repairing = false;
        Q_EMIT errorTextChanged();
        Q_EMIT repairingChanged();
        refreshStatus();
        process->deleteLater();
    });
    process->start(program, arguments);
}
