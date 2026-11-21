// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <KQuickConfigModule>

#include <QVariantList>
#include <QVariantMap>

// The Partners page (ORDER 70): for each kind of work, who answers, with which model and on which card. Every fact and every
// change goes through the page's command, sparky-stereo-partners, so the page, programs and tests read the same answers.
// Choices (a default's interface and model, the card, a program's own choice) wait for Apply; actions (install the engine,
// turn it on or off, download a model, add or remove a provider) run when the person asks, and their words are shown.
class PartnersKcm : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(QVariantMap status READ status NOTIFY statusChanged)
    Q_PROPERTY(QVariantList models READ models NOTIFY modelsChanged)
    Q_PROPERTY(QVariantMap pending READ pending NOTIFY pendingChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString message READ message NOTIFY messageChanged)
    Q_PROPERTY(QString progress READ progress NOTIFY progressChanged)
    // a download the connection's state held (metered, or not readable): the page offers "Download anyway" for it
    Q_PROPERTY(QString heldModel READ heldModel NOTIFY messageChanged)

public:
    PartnersKcm(QObject *parent, const KPluginMetaData &data);

    QVariantMap status() const { return m_status; }
    QVariantList models() const { return m_models; }
    QVariantMap pending() const { return m_pending; }
    bool busy() const { return m_busy; }
    QString message() const { return m_message; }
    QString progress() const { return m_progress; }
    QString heldModel() const { return m_heldModel; }

    // a choice, applied with Apply: key names the setting ("default/text/interface", "default/text/model", "card",
    // "program/ID/KIND"), args are the command's arguments that write it
    Q_INVOKABLE void choose(const QString &key, const QStringList &args, const QVariant &shown);
    // an action, now: the command with these arguments (and text on its standard input, for a provider's key)
    Q_INVOKABLE void act(const QStringList &args, const QString &input = QString());
    Q_INVOKABLE void refreshModels();
    Q_INVOKABLE QString humanSize(double bytes) const;

    void load() override;
    void save() override;
    void defaults() override;

Q_SIGNALS:
    void statusChanged();
    void modelsChanged();
    void pendingChanged();
    void busyChanged();
    void messageChanged();
    void progressChanged();
    // the page asks the person before an install: the plan's packages and sizes
    void planReady(const QVariantList &packages, double total);

private:
    QByteArray runNow(const QStringList &args, int *status = nullptr, QString *error = nullptr) const;
    void refreshStatus();
    void setBusy(bool busy);
    void setMessage(const QString &text);

    QVariantMap m_status;
    QVariantList m_models;
    QVariantMap m_pending; // key -> shown value
    QMap<QString, QStringList> m_pendingArgs;
    bool m_busy = false;
    QString m_message;
    QString m_progress;
    QString m_heldModel;
};
