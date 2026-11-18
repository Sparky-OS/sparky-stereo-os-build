// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QObject>
#include <QString>

// What the tray and the settings page know about PJeOffice Pro: whether the signer answers on localhost (the program's own
// browser-facing ping), and what the installer wrote down (state.json), and what the last look at CNJ's update address saw.
class SignerState : public QObject
{
    Q_OBJECT
public:
    explicit SignerState(QObject *parent = nullptr);

    // The ping the program's own web integration uses: PUT /pjeOffice/?u=18 with the preflight headers; answers when it replies
    // 200 with {"success": true}. A refusal, a timeout or another reply is "does not answer".
    void probe();
    bool answers() const { return m_answers; }
    bool probed() const { return m_probed; }

    // /var/lib/sparky-pjeoffice/state.json, read again on every call (the installer replaces it atomically)
    static QJsonObject installerState();
    static QString installedVersion();
    static QString previousVersion();
    static bool restartPending();
    // $XDG_STATE_HOME/sparky-pjeoffice/upstream.json written by `sparky-pjeoffice check`
    static QJsonObject upstream();
    // The version the package's catalogue reviewed
    static QString reviewedVersion();

    static QString launcher() { return QStringLiteral("/usr/bin/pjeoffice-pro"); }
    static QString command() { return QStringLiteral("/usr/bin/sparky-pjeoffice"); }

Q_SIGNALS:
    void probeFinished(bool answers);

private:
    QNetworkAccessManager m_network;
    bool m_answers = false;
    bool m_probed = false;
    bool m_busy = false;
};
