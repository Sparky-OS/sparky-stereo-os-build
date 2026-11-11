/*
    SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "umsservice.h"

#include <QProcess>

namespace
{
const QString unit = QStringLiteral("ums.service");
}

bool UmsService::run(const QStringList &arguments, QString *output) const
{
    QProcess process;
    const QString program = qEnvironmentVariable("UMS_KCM_SYSTEMCTL", QStringLiteral("systemctl"));
    process.start(program, QStringList{QStringLiteral("--user")} + arguments);
    if (!process.waitForFinished(30000)) {
        process.kill();
        m_error = QStringLiteral("%1 did not finish").arg(program);
        return false;
    }
    if (output) {
        *output = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
    }
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        m_error = QString::fromUtf8(process.readAllStandardError()).trimmed();
        return false;
    }
    return true;
}

bool UmsService::isEnabled() const
{
    QString output;
    run({QStringLiteral("is-enabled"), unit}, &output);
    return output == QLatin1String("enabled");
}

bool UmsService::isActive() const
{
    QString output;
    run({QStringLiteral("is-active"), unit}, &output);
    return output == QLatin1String("active");
}

bool UmsService::setEnabled(bool enabled)
{
    return run({enabled ? QStringLiteral("enable") : QStringLiteral("disable"), QStringLiteral("--now"), unit});
}

bool UmsService::restartIfActive()
{
    return run({QStringLiteral("try-restart"), unit});
}

QString UmsService::errorString() const
{
    return m_error;
}
