// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "signerstate.h"

#include <KQuickConfigModule>

#include <QTimer>

// The settings page of PJeOffice Pro on the edition: autostart, the installed version and its update state, and the ways to open the
// signer and the certificate tools. Certificates, tokens and PINs are the program's own window's business, system trust Sparky CA's.
class PjeOfficeKcm : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(bool autostart READ autostart WRITE setAutostart NOTIFY autostartChanged)
    Q_PROPERTY(QString installedVersion READ installedVersion NOTIFY stateChanged)
    Q_PROPERTY(QString reviewedVersion READ reviewedVersion NOTIFY stateChanged)
    Q_PROPERTY(QString previousVersion READ previousVersion NOTIFY stateChanged)
    Q_PROPERTY(QString updateText READ updateText NOTIFY stateChanged)
    Q_PROPERTY(QString upstreamText READ upstreamText NOTIFY stateChanged)
    Q_PROPERTY(bool signerAnswers READ signerAnswers NOTIFY stateChanged)
    Q_PROPERTY(bool restartPending READ restartPending NOTIFY stateChanged)
    Q_PROPERTY(bool certificateToolInstalled READ certificateToolInstalled CONSTANT)

public:
    PjeOfficeKcm(QObject *parent, const KPluginMetaData &data);

    bool autostart() const { return m_autostart; }
    void setAutostart(bool on);
    QString installedVersion() const { return SignerState::installedVersion(); }
    QString reviewedVersion() const { return SignerState::reviewedVersion(); }
    QString previousVersion() const { return SignerState::previousVersion(); }
    QString updateText() const;
    QString upstreamText() const;
    bool signerAnswers() const { return m_state.answers(); }
    bool restartPending() const { return SignerState::restartPending(); }
    bool certificateToolInstalled() const;

    Q_INVOKABLE void openSigner();
    Q_INVOKABLE void openCertificateTool();
    Q_INVOKABLE void checkUpstream();

    void load() override;
    void save() override;
    void defaults() override;

Q_SIGNALS:
    void autostartChanged();
    void stateChanged();

private:
    SignerState m_state;
    QTimer m_poll;
    bool m_autostart = true;
    bool m_checking = false;
};
