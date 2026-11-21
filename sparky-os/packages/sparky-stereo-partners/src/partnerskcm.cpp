// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "partnerskcm.h"

#include <KLocalizedString>
#include <KPluginFactory>

#include <QJsonDocument>
#include <QLocale>
#include <QProcess>
#include <QStandardPaths>

using namespace Qt::StringLiterals;

K_PLUGIN_CLASS_WITH_JSON(PartnersKcm, "kcm_sparkystereo_partners.json")

static QString command()
{
    // SPARKY_STEREO_PARTNERS_COMMAND: another build of the command, for tests
    const QString given = qEnvironmentVariable("SPARKY_STEREO_PARTNERS_COMMAND");
    return given.isEmpty() ? QStandardPaths::findExecutable(u"sparky-stereo-partners"_s) : given;
}

PartnersKcm::PartnersKcm(QObject *parent, const KPluginMetaData &data)
    : KQuickConfigModule(parent, data)
{
    setButtons(Apply | Default);
}

QByteArray PartnersKcm::runNow(const QStringList &args, int *status, QString *error) const
{
    QProcess process;
    process.start(command(), args);
    if (!process.waitForStarted(5000)) {
        if (status) {
            *status = 127;
        }
        if (error) {
            *error = i18nc("@info", "The page's command, sparky-stereo-partners, could not be started.");
        }
        return {};
    }
    process.closeWriteChannel();
    process.waitForFinished(60000);
    if (status) {
        *status = process.exitStatus() == QProcess::NormalExit ? process.exitCode() : 128;
    }
    if (error) {
        *error = QString::fromUtf8(process.readAllStandardError()).trimmed();
    }
    return process.readAllStandardOutput();
}

void PartnersKcm::refreshStatus()
{
    QString error;
    int status = 0;
    const QByteArray out = runNow({u"status"_s, u"--json"_s}, &status, &error);
    m_status = QJsonDocument::fromJson(out).toVariant().toMap();
    if (status != 0 && !error.isEmpty()) {
        setMessage(error);
    }
    Q_EMIT statusChanged();
}

void PartnersKcm::refreshModels()
{
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process]() {
        m_models = QJsonDocument::fromJson(process->readAllStandardOutput()).toVariant().toList();
        Q_EMIT modelsChanged();
        process->deleteLater();
    });
    process->start(command(), {u"models"_s, u"--json"_s});
}

void PartnersKcm::refreshAccount()
{
    m_account.clear();
    Q_EMIT accountChanged();
    if (!m_status.value(u"engine"_s).toMap().value(u"on"_s).toBool()) {
        m_account.insert(u"state"_s, u"off"_s);
        Q_EMIT accountChanged();
        return;
    }
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process]() {
        m_account = QJsonDocument::fromJson(process->readAllStandardOutput()).toVariant().toMap();
        if (m_account.isEmpty()) {
            m_account.insert(u"state"_s, u"unavailable"_s);
            m_account.insert(u"why"_s, QString::fromUtf8(process->readAllStandardError()).trimmed());
        }
        Q_EMIT accountChanged();
        process->deleteLater();
    });
    process->start(command(), {u"account"_s, u"--json"_s});
}

void PartnersKcm::refresh()
{
    refreshStatus();
    refreshModels();
    refreshAccount();
}

void PartnersKcm::load()
{
    m_pending.clear();
    m_pendingArgs.clear();
    Q_EMIT pendingChanged();
    refreshStatus();
    refreshModels();
    refreshAccount();
    setNeedsSave(false);
}

void PartnersKcm::save()
{
    QStringList errors;
    for (auto it = m_pendingArgs.cbegin(); it != m_pendingArgs.cend(); ++it) {
        int status = 0;
        QString error;
        runNow(it.value(), &status, &error);
        if (status != 0) {
            errors << (error.isEmpty() ? i18nc("@info", "The choice could not be saved.") : error);
        }
    }
    m_pending.clear();
    m_pendingArgs.clear();
    Q_EMIT pendingChanged();
    setMessage(errors.join(u'\n'));
    refreshStatus();
    setNeedsSave(false);
}

void PartnersKcm::defaults()
{
    // the system defaults: the person's own choices go (each kind follows /etc/xdg), the card goes back to Automatic
    const QVariantList kinds = m_status.value(u"defaults"_s).toList();
    for (const QVariant &kind : kinds) {
        const QString name = kind.toMap().value(u"kind"_s).toString();
        choose(u"default/%1/model"_s.arg(name), {u"set-default"_s, name, u"--no-model"_s}, QString());
    }
    choose(u"card"_s, {u"card"_s, u"auto"_s}, u"auto"_s);
}

void PartnersKcm::choose(const QString &key, const QStringList &args, const QVariant &shown)
{
    m_pending.insert(key, shown);
    m_pendingArgs.insert(key, args);
    Q_EMIT pendingChanged();
    setNeedsSave(true);
}

void PartnersKcm::act(const QStringList &args, const QString &input)
{
    if (m_busy) {
        return;
    }
    setBusy(true);
    setMessage(QString());
    m_progress.clear();
    Q_EMIT progressChanged();
    auto *process = new QProcess(this);
    const QString what = args.value(0);
    connect(process, &QProcess::readyReadStandardOutput, this, [this, process, what]() {
        while (process->canReadLine()) {
            const QByteArray line = process->readLine().trimmed();
            if (what == u"download"_s) {
                const QVariantMap event = QJsonDocument::fromJson(line).toVariant().toMap();
                m_progress = event.isEmpty() ? QString::fromUtf8(line)
                    : event.contains(u"total"_s) ? u"%1 %2 / %3"_s.arg(event.value(u"status"_s).toString(),
                                                                       humanSize(event.value(u"completed"_s).toDouble()),
                                                                       humanSize(event.value(u"total"_s).toDouble()))
                                                 : event.value(u"status"_s).toString();
                Q_EMIT progressChanged();
            }
        }
    });
    m_heldModel.clear();
    connect(process, &QProcess::finished, this, [this, process, what, args](int code, QProcess::ExitStatus exitStatus) {
        const QString error = QString::fromUtf8(process->readAllStandardError()).trimmed();
        const QByteArray out = process->readAllStandardOutput();
        if (what == u"install-plan"_s && code == 0) {
            QVariantList packages;
            double total = 0;
            for (const QByteArray &line : out.split('\n')) {
                const QList<QByteArray> fields = line.split('\t');
                if (fields.size() == 2 && fields[0] == "total") {
                    total = fields[1].toDouble();
                } else if (fields.size() == 2 && fields[0] != "packages") {
                    packages << QVariantMap{{u"name"_s, QString::fromUtf8(fields[0])}, {u"size"_s, fields[1].toDouble()}};
                }
            }
            Q_EMIT planReady(packages, total);
        }
        if (what == u"download"_s && code == 5) {
            m_heldModel = args.value(1);
        }
        if (what == u"signin"_s && exitStatus == QProcess::NormalExit && code == 7) {
            // not signed in yet: the browser was opened at ollama.com's page; the command's words say what to do next
            setMessage(QString::fromUtf8(out).trimmed(), true);
        } else if (exitStatus != QProcess::NormalExit || code != 0) {
            // the command's own words: what failed, why and what to do (and kept by the problems engine)
            setMessage(error.isEmpty() ? i18nc("@info %1 is an exit status", "The step failed (exit status %1).", code) : error);
        }
        process->deleteLater();
        setBusy(false);
        refreshStatus();
        if (what == u"download"_s || what == u"engine"_s) {
            refreshModels();
        }
        if (what == u"engine"_s || what == u"signin"_s || what == u"signout"_s) {
            refreshAccount();
        }
    });
    process->start(command(), args);
    if (!input.isNull()) {
        process->write(input.toUtf8());
    }
    process->closeWriteChannel();
}

QString PartnersKcm::humanSize(double bytes) const
{
    return QLocale().formattedDataSize(qint64(bytes), 2, QLocale::DataSizeSIFormat);
}

void PartnersKcm::setBusy(bool busy)
{
    if (m_busy != busy) {
        m_busy = busy;
        Q_EMIT busyChanged();
    }
}

void PartnersKcm::setMessage(const QString &text, bool info)
{
    if (m_message != text || m_messageIsInfo != info) {
        m_message = text;
        m_messageIsInfo = info;
        Q_EMIT messageChanged();
    }
}

#include "partnerskcm.moc"
