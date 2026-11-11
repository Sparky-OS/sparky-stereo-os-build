// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#include "problems.h"
#include <QByteArray>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextStream>
#include <sparky-stereo-problems.h>

namespace
{

const char package[] = "sparky-stereo-cec";

void said(const char *what)
{
    QTextStream(stderr) << package << ": " << what << ": " << QString::fromUtf8(ssp_error()) << '\n';
}

}

CecProblems::CecProblems(QObject *parent)
    : QObject(parent)
{
}

void CecProblems::watch(CecController &controller, SessionGate &session)
{
    connect(&controller, &CecController::problem, this, &CecProblems::keep);
    connect(&controller, &CecController::transmitted, this, [this](const QString &output, bool, bool acknowledged) {
        if (acknowledged) {
            this->acknowledged(output);
        }
    });
    connect(&session, &SessionGate::lookupFailed, this, &CecProblems::sessionFailed);
    connect(&session, &SessionGate::lookupSucceeded, this, &CecProblems::sessionWorks);
}

void CecProblems::keep(const QString &output, const QString &kind, const QString &detail, const QString &evidence)
{
    // the kind says which message; the message names the screen and the detail
    const char *message = kind == QLatin1String("start") ? "LOCAL2" : kind == QLatin1String("address") ? "LOCAL3" : "LOCAL4";
    const QByteArray key = (kind + QLatin1Char(':') + output).toUtf8();
    const QByteArray out = output.toUtf8();
    const QByteArray det = detail.toUtf8();
    const char *args[] = {out.constData(), det.constData()};
    QJsonObject details{{QStringLiteral("actions"),
                         QJsonArray{QJsonObject{{QStringLiteral("id"), QStringLiteral("display")},
                                                {QStringLiteral("label"), QJsonArray{QStringLiteral("LOCAL6")}},
                                                {QStringLiteral("command"), QJsonArray{QStringLiteral("systemsettings"), QStringLiteral("kcm_kscreen")}}}}}};
    if (!evidence.isEmpty()) {
        details.insert(QStringLiteral("output"), evidence.left(4000));
    }
    const QByteArray json = QJsonDocument(details).toJson(QJsonDocument::Compact);
    if (ssp_keep(SSP_PERSON, package, key.constData(), message, args, 2, json.constData()) != 0) {
        said("the problem could not be kept");
    }
}

void CecProblems::acknowledged(const QString &output)
{
    // a message the TV acknowledged: this screen's failures are over
    for (const char *kind : {"start", "address", "unacknowledged"}) {
        const QByteArray key = (QLatin1String(kind) + QLatin1Char(':') + output).toUtf8();
        if (ssp_clear(SSP_PERSON, package, key.constData()) != 0) {
            said("the problem could not be cleared");
        }
    }
}

void CecProblems::sessionFailed(const QString &reason)
{
    const QByteArray det = reason.toUtf8();
    const char *args[] = {det.constData()};
    if (ssp_keep(SSP_PERSON, package, "session", "LOCAL5", args, 1, nullptr) != 0) {
        said("the problem could not be kept");
    }
}

void CecProblems::sessionWorks()
{
    if (ssp_clear(SSP_PERSON, package, "session") != 0) {
        said("the problem could not be cleared");
    }
}
