// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "signerstate.h"

#include <QFile>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QStandardPaths>
#include <QTimer>

SignerState::SignerState(QObject *parent)
    : QObject(parent)
{
}

void SignerState::probe()
{
    if (m_busy) {
        return;
    }
    m_busy = true;
    QNetworkRequest request(QUrl(QStringLiteral("http://127.0.0.1:8800/pjeOffice/?u=18")));
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    request.setRawHeader("Force-Preflight", "true");
    request.setRawHeader("Origin", "http://127.0.0.1:8800");
    request.setTransferTimeout(2000);
    QNetworkReply *reply = m_network.put(request, QByteArray());
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        bool ok = false;
        if (reply->error() == QNetworkReply::NoError
            && reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() == 200) {
            ok = QJsonDocument::fromJson(reply->readAll()).object().value(QStringLiteral("success")).toBool();
        }
        reply->deleteLater();
        m_busy = false;
        m_probed = true;
        m_answers = ok;
        Q_EMIT probeFinished(ok);
    });
}

static QJsonObject readJson(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    return QJsonDocument::fromJson(file.readAll()).object();
}

QJsonObject SignerState::installerState()
{
    return readJson(QStringLiteral("/var/lib/sparky-pjeoffice/state.json"));
}

QString SignerState::installedVersion()
{
    return installerState().value(QStringLiteral("installed")).toString();
}

QString SignerState::previousVersion()
{
    return installerState().value(QStringLiteral("previous")).toString();
}

bool SignerState::restartPending()
{
    return installerState().value(QStringLiteral("restart_pending")).toBool();
}

QJsonObject SignerState::upstream()
{
    return readJson(QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation) + QStringLiteral("/sparky-pjeoffice/upstream.json"));
}

QString SignerState::reviewedVersion()
{
    return readJson(QStringLiteral("/usr/share/sparky-pjeoffice/catalogue.json")).value(QStringLiteral("current")).toString();
}
