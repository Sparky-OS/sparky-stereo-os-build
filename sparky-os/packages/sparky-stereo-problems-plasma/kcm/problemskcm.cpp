// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "problemskcm.h"

#include <sparky-stereo-problems.h>

#include <KLocalizedString>
#include <KPluginFactory>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QProcess>
#include <QStandardPaths>

using namespace Qt::StringLiterals;

K_PLUGIN_CLASS_WITH_JSON(ProblemsKcm, "kcm_sparkystereo_problems.json")

static const QString s_engine = u"/usr/bin/sparky-stereo-problems"_s;

static QString handleOf(const QString &scope, const QString &package, const QString &key)
{
    return scope + u'/' + package + u'/' + key;
}

static int scopeCode(const QString &scope)
{
    return scope == u"machine"_s ? SSP_MACHINE : scope == u"boot"_s ? SSP_BOOT : SSP_PERSON;
}

// The person's languages as the engine takes them, the page's own first, so the engine's texts and the page agree
static QByteArray languages()
{
    return KLocalizedString::languages().join(u':').toUtf8();
}

static QString whenText(const QString &iso)
{
    const QDateTime t = QDateTime::fromString(iso, Qt::ISODate);
    return t.isValid() ? QLocale().toString(t.toLocalTime(), QLocale::ShortFormat) : iso;
}

ProblemsKcm::ProblemsKcm(QObject *parent, const KPluginMetaData &data)
    : KQuickConfigModule(parent, data)
{
    setButtons(NoAdditionalButton);
    m_settle.setSingleShot(true);
    m_settle.setInterval(300);
    connect(&m_settle, &QTimer::timeout, this, &ProblemsKcm::refresh);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] {
        m_settle.start();
    });
    // systemd's unit state: a failed service that systemd no longer has as failed is over
    QDBusConnection system = QDBusConnection::systemBus();
    if (system.isConnected()) {
        system.connect(u"org.freedesktop.systemd1"_s, QString(), u"org.freedesktop.DBus.Properties"_s, u"PropertiesChanged"_s, this,
                       SLOT(unitChanged(QString, QVariantMap, QStringList)));
        system.asyncCall(QDBusMessage::createMethodCall(u"org.freedesktop.systemd1"_s, u"/org/freedesktop/systemd1"_s,
                                                        u"org.freedesktop.systemd1.Manager"_s, u"Subscribe"_s));
    }
}

void ProblemsKcm::load()
{
    refresh();
}

void ProblemsKcm::watchStores()
{
    const QString root = qEnvironmentVariable("SPARKY_STEREO_ROOT");
    const QString state = QString(QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation) + u"/sparky-stereo-problems"_s);
    const QStringList dirs = {QString(root + u"/var/lib/sparky-stereo-problems"_s), QString(root + u"/run/sparky-stereo-problems"_s), state,
                              QString(state + u"/.hidden"_s)};
    for (const QString &dir : dirs) {
        if (QFileInfo::exists(dir) && !m_watcher.directories().contains(dir)) {
            m_watcher.addPath(dir);
        }
    }
}

void ProblemsKcm::refresh()
{
    watchStores();
    const QByteArray lang = languages();
    char *json = ssp_list_over_json(nullptr, lang.isEmpty() ? nullptr : lang.constData());
    if (!json) {
        setMessages(i18nc("@info", "The problems cannot be read: %1", QString::fromUtf8(ssp_error())), QString());
        return;
    }
    const QJsonArray all = QJsonDocument::fromJson(QByteArray(json)).array();
    ssp_free(json);
    QVariantList current;
    QVariantList dismissed;
    for (const QJsonValue &v : all) {
        const QJsonObject p = v.toObject();
        QVariantMap e;
        if (p.contains(u"unreadable"_s)) {
            // a record that cannot be read is said, never left out; it cannot be dismissed
            e[u"handle"_s] = QString(u"unreadable/"_s + p[u"file"_s].toString());
            e[u"title"_s] = i18nc("@title", "A record cannot be read");
            e[u"text"_s] = QString(p[u"file"_s].toString() + u": "_s + p[u"unreadable"_s].toString());
            e[u"severity"_s] = u"failed"_s;
            e[u"since"_s] = QString();
            e[u"canDismiss"_s] = false;
            e[u"canRepair"_s] = false;
            e[u"labels"_s] = QStringList();
            e[u"over"_s] = false;
            current << e;
            continue;
        }
        const QString scope = p[u"scope"_s].toString();
        const QString severity = p[u"severity"_s].toString();
        e[u"handle"_s] = handleOf(scope, p[u"package"_s].toString(), p[u"key"_s].toString());
        e[u"scope"_s] = scope;
        e[u"title"_s] = p[u"title"_s].toString();
        e[u"text"_s] = p[u"text"_s].toString();
        e[u"severity"_s] = severity;
        e[u"severityText"_s] = severity == u"failed"_s ? i18nc("@label severity", "Failed")
            : severity == u"degraded"_s                  ? i18nc("@label severity", "Works only in part")
                                                         : i18nc("@label severity", "Notice");
        e[u"since"_s] = i18nc("@info %1 a date and time", "Since %1", whenText(p[u"first"_s].toString()));
        e[u"canDismiss"_s] = true;
        e[u"canRepair"_s] = !p[u"repair"_s].toArray().isEmpty() && !p[u"over"_s].toBool();
        QStringList labels;
        for (const QJsonValue &l : p[u"labels"_s].toArray()) {
            labels << l.toString();
        }
        e[u"labels"_s] = p[u"over"_s].toBool() ? QStringList() : labels;
        e[u"over"_s] = p[u"over"_s].toBool();
        e[u"dismissed"_s] = p[u"hidden"_s].toBool();
        const QJsonObject last = p[u"last_repair"_s].toObject();
        e[u"lastRepair"_s] = last.isEmpty() ? QString() : i18nc("@info", "The last repair failed with exit status %1.", last[u"status"_s].toInteger());
        if (p[u"hidden"_s].toBool()) {
            dismissed << e;
        } else {
            current << e;
        }
    }
    m_current = current;
    m_dismissed = dismissed;
    Q_EMIT changed();
}

void ProblemsKcm::unitChanged(const QString &interface, const QVariantMap &changed, const QStringList &invalidated)
{
    if (interface == u"org.freedesktop.systemd1.Unit"_s && (changed.contains(u"ActiveState"_s) || invalidated.contains(u"ActiveState"_s))) {
        m_settle.start();
    }
}

void ProblemsKcm::setMessages(const QString &error, const QString &notice)
{
    m_error = error;
    m_notice = notice;
    Q_EMIT messageChanged();
}

QVariantMap ProblemsKcm::find(const QString &handle) const
{
    for (const QVariantList *list : {&m_current, &m_dismissed}) {
        for (const QVariant &v : *list) {
            if (v.toMap()[u"handle"_s].toString() == handle) {
                return v.toMap();
            }
        }
    }
    return {};
}

void ProblemsKcm::dismiss(const QString &handle)
{
    const QVariantMap e = find(handle);
    if (e.isEmpty() || !e[u"canDismiss"_s].toBool()) {
        return;
    }
    const QStringList parts = handle.split(u'/');
    const QByteArray package = parts.value(1).toUtf8();
    const QByteArray key = handle.section(u'/', 2).toUtf8();
    if (ssp_hide(scopeCode(parts.value(0)), package.constData(), key.constData()) != 0) {
        setMessages(i18nc("@info", "The problem could not be dismissed: %1", QString::fromUtf8(ssp_error())), QString());
        return;
    }
    setMessages(QString(), QString());
    refresh();
}

void ProblemsKcm::bringBack(const QString &handle)
{
    const QStringList parts = handle.split(u'/');
    const QByteArray package = parts.value(1).toUtf8();
    const QByteArray key = handle.section(u'/', 2).toUtf8();
    if (ssp_show(scopeCode(parts.value(0)), package.constData(), key.constData()) != 0) {
        setMessages(i18nc("@info", "The problem could not be brought back: %1", QString::fromUtf8(ssp_error())), QString());
        return;
    }
    setMessages(QString(), QString());
    refresh();
}

void ProblemsKcm::repair(const QString &handle)
{
    const QVariantMap e = find(handle);
    if (e.isEmpty() || !e[u"canRepair"_s].toBool() || m_busy) {
        return;
    }
    const QStringList parts = handle.split(u'/');
    const QString scope = parts.value(0);
    QStringList args = {u"repair"_s, u"--"_s + scope, parts.value(1), handle.section(u'/', 2)};
    QString program = s_engine;
    if (scope != u"person"_s) {
        // the machine's problems are root's: org.sparkylinux.sparkystereo.problems.repair, which runs only repair
        args.prepend(s_engine);
        program = u"pkexec"_s;
    }
    m_busy = true;
    Q_EMIT busyChanged();
    auto *process = new QProcess(this);
    process->setProcessChannelMode(QProcess::MergedChannels);
    const QString title = e[u"title"_s].toString();
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            setMessages(i18nc("@info", "%1 could not be started: %2", process->program(), process->errorString()), QString());
            m_busy = false;
            Q_EMIT busyChanged();
            process->deleteLater();
        }
    });
    connect(process, &QProcess::finished, this, [this, process, title, program](int code, QProcess::ExitStatus status) {
        const QString output = QString::fromUtf8(process->readAll()).trimmed();
        process->deleteLater();
        m_busy = false;
        Q_EMIT busyChanged();
        if (status == QProcess::NormalExit && code == 0) {
            setMessages(QString(), i18nc("@info %1 a problem's title", "It works again: %1", title));
        } else if (program == u"pkexec"_s && (code == 126 || code == 127)) {
            setMessages(i18nc("@info", "The administrator's permission was not given (pkexec exit status %1).", code), QString());
        } else {
            // a repair that failed is kept by the engine as a new generation: the problem is listed again with it
            setMessages(i18nc("@info %1 the engine's words", "The repair did not work: %1", output), QString());
        }
        refresh();
    });
    process->start(program, args);
}

void ProblemsKcm::runAction(const QString &handle, int index)
{
    const QStringList parts = handle.split(u'/');
    const QByteArray package = parts.value(1).toUtf8();
    const QByteArray key = handle.section(u'/', 2).toUtf8();
    // the record's own action (a command the package asked to offer), as the notifier runs it
    char *json = ssp_list_over_json(package.constData(), nullptr);
    if (!json) {
        setMessages(QString::fromUtf8(ssp_error()), QString());
        return;
    }
    const QJsonArray all = QJsonDocument::fromJson(QByteArray(json)).array();
    ssp_free(json);
    for (const QJsonValue &v : all) {
        const QJsonObject p = v.toObject();
        if (p[u"scope"_s].toString() != parts.value(0) || p[u"key"_s].toString() != QString::fromUtf8(key)) {
            continue;
        }
        const QJsonArray command = p[u"actions"_s].toArray().at(index).toObject()[u"command"_s].toArray();
        QStringList args;
        for (int i = 1; i < command.size(); ++i) {
            args << command.at(i).toString();
        }
        const QString program = command.at(0).toString();
        if (program.isEmpty() || !QProcess::startDetached(program, args)) {
            setMessages(i18nc("@info", "%1 could not be started.", program), QString());
        }
        return;
    }
}

#include "problemskcm.moc"
