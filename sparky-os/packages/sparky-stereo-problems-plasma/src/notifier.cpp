// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "notifier.h"

#include <sparky-stereo-problems.h>

#include <KLocalizedString>
#include <KNotification>

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QProcess>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTextStream>

using namespace Qt::StringLiterals;

static const QString s_engine = u"/usr/bin/sparky-stereo-problems"_s;

static QString handleOf(const QJsonObject &p)
{
    return p[u"scope"_s].toString() + u'/' + p[u"package"_s].toString() + u'/' + p[u"key"_s].toString();
}

static QString identOf(const QJsonObject &p)
{
    return handleOf(p) + u'/' + p[u"id"_s].toString() + u'/' + QString::number(p[u"generation"_s].toInteger());
}

static int scopeCode(const QString &scope)
{
    return scope == u"machine"_s ? SSP_MACHINE : scope == u"boot"_s ? SSP_BOOT : SSP_PERSON;
}

static QString commandLine(const QJsonArray &argv)
{
    QStringList words;
    for (const QJsonValue &v : argv) {
        words << v.toString();
    }
    return words.join(u' ');
}

// One of the engine's own messages, in the person's language
static QString engineText(const char *message, const QStringList &args)
{
    QList<QByteArray> bytes;
    QList<const char *> pointers;
    for (const QString &a : args) {
        bytes << a.toUtf8();
    }
    for (const QByteArray &b : std::as_const(bytes)) {
        pointers << b.constData();
    }
    char *json = ssp_render("sparky-stereo-problems", message, pointers.constData(), int(pointers.size()), nullptr);
    if (!json) {
        return QString::fromLatin1(message) + u' ' + args.join(u' ');
    }
    const QJsonObject o = QJsonDocument::fromJson(QByteArray(json)).object();
    ssp_free(json);
    return o[u"text"_s].toString();
}

Notifier::Notifier(QObject *parent)
    : QObject(parent)
{
    m_settle.setSingleShot(true);
    m_settle.setInterval(300);
    connect(&m_settle, &QTimer::timeout, this, &Notifier::rescan);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] {
        m_settle.start();
    });
}

void Notifier::start()
{
    const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (runtime.isEmpty()) {
        // without it every start is a login: said where the session keeps its log
        QTextStream(stderr) << "sparky-stereo-problems-notifier: XDG_RUNTIME_DIR is not set, so each start shows every open problem again\n";
    } else {
        QDir().mkpath(runtime + u"/sparky-stereo-problems"_s);
        m_notifiedFile = runtime + u"/sparky-stereo-problems/notified"_s;
        QFile file(m_notifiedFile);
        if (file.open(QIODevice::ReadOnly)) {
            m_login = false;
            const QStringList lines = QString::fromUtf8(file.readAll()).split(u'\n', Qt::SkipEmptyParts);
            m_notified = QSet<QString>(lines.cbegin(), lines.cend());
        }
    }
    const QString state = QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation) + u"/sparky-stereo-problems"_s;
    if (QDir().mkpath(state)) {
        QFile::setPermissions(state, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
    }
    for (const QString &dir : {u"/var/lib/sparky-stereo-problems"_s, u"/run/sparky-stereo-problems"_s, state}) {
        if (!QFileInfo::exists(dir) || !m_watcher.addPath(dir)) {
            QTextStream(stderr) << "sparky-stereo-problems-notifier: " << dir << " cannot be watched; its problems are shown when another store changes\n";
        }
    }
    rescan();
}

void Notifier::saveNotified()
{
    if (m_notifiedFile.isEmpty()) {
        return;
    }
    QSaveFile file(m_notifiedFile);
    QStringList lines(m_notified.cbegin(), m_notified.cend());
    lines.sort();
    if (!file.open(QIODevice::WriteOnly) || file.write(lines.join(u'\n').toUtf8() + '\n') < 0 || !file.commit()) {
        QTextStream(stderr) << "sparky-stereo-problems-notifier: " << m_notifiedFile << " cannot be written: " << file.errorString() << '\n';
    }
}

void Notifier::closeShown(const QString &handle)
{
    const QPointer<KNotification> n = m_shown.take(handle);
    if (n) {
        n->close();
    }
}

void Notifier::rescan()
{
    char *json = ssp_list_json(nullptr, nullptr);
    if (!json) {
        tell(u"error"_s, i18nc("@title", "The problems cannot be read"), QString::fromUtf8(ssp_error()));
        return;
    }
    const QJsonArray all = QJsonDocument::fromJson(QByteArray(json)).array();
    ssp_free(json);
    QList<QJsonObject> open;
    QSet<QString> handles;
    for (const QJsonValue &v : all) {
        QJsonObject p = v.toObject();
        if (p.contains(u"unreadable"_s)) {
            // a record that cannot be read is said, never left out
            p[u"package"_s] = u"sparky-stereo-problems"_s;
            p[u"key"_s] = p[u"file"_s];
            p[u"id"_s] = p[u"unreadable"_s];
            p[u"severity"_s] = u"failed"_s;
            p[u"title"_s] = engineText("LOCAL29", {});
            p[u"text"_s] = engineText("LOCAL25", {p[u"file"_s].toString() + u": "_s + p[u"unreadable"_s].toString()});
        }
        if (p[u"hidden"_s].toBool()) {
            continue;
        }
        open << p;
        handles.insert(handleOf(p));
    }
    // a problem that is over, or hidden, closes its notification
    const QStringList shown = m_shown.keys();
    for (const QString &h : shown) {
        if (!handles.contains(h)) {
            closeShown(h);
        }
    }
    QList<QJsonObject> fresh;
    for (const QJsonObject &p : std::as_const(open)) {
        if (!m_notified.contains(identOf(p))) {
            fresh << p;
        }
    }
    if (m_login && fresh.size() > 1) {
        notifySummary(fresh);
    } else {
        for (const QJsonObject &p : std::as_const(fresh)) {
            notifyOne(p);
        }
    }
    for (const QJsonObject &p : std::as_const(fresh)) {
        m_notified.insert(identOf(p));
    }
    m_login = false;
    if (!fresh.isEmpty() || !m_notifiedFile.isEmpty()) {
        saveNotified();
    }
}

void Notifier::notifyOne(const QJsonObject &p)
{
    const QString handle = handleOf(p);
    closeShown(handle);
    const QString severity = p[u"severity"_s].toString();
    const bool failed = severity == u"failed"_s;
    auto *n = new KNotification(failed ? u"failed"_s : severity == u"degraded"_s ? u"degraded"_s : u"notice"_s,
                                failed ? KNotification::Persistent : KNotification::CloseOnTimeout);
    n->setComponentName(u"sparky-stereo-problems"_s);
    n->setUrgency(failed ? KNotification::CriticalUrgency : KNotification::NormalUrgency);
    n->setTitle(p[u"title"_s].toString());
    QString text = p[u"text"_s].toString().toHtmlEscaped();
    const QJsonObject last = p[u"last_repair"_s].toObject();
    if (!last.isEmpty()) {
        text += u"<br/>"_s + i18nc("@info", "The last repair failed with exit status %1.", last[u"status"_s].toInteger()).toHtmlEscaped();
    }
    n->setText(text);
    connect(n->addDefaultAction(i18nc("@action:button", "Show details")), &KNotificationAction::activated, this, [this, p] {
        showDetails(p);
    });
    connect(n->addAction(i18nc("@action:button", "Show details")), &KNotificationAction::activated, this, [this, p] {
        showDetails(p);
    });
    if (!p[u"repair"_s].toArray().isEmpty()) {
        connect(n->addAction(i18nc("@action:button", "Repair")), &KNotificationAction::activated, this, [this, p] {
            repair(p);
        });
    }
    const QJsonArray labels = p[u"labels"_s].toArray();
    for (int i = 0; i < labels.size(); ++i) {
        connect(n->addAction(labels.at(i).toString()), &KNotificationAction::activated, this, [this, p, i] {
            runAction(p, i);
        });
    }
    if (!p.contains(u"unreadable"_s)) {
        connect(n->addAction(i18nc("@action:button", "Hide")), &KNotificationAction::activated, this, [this, p] {
            hide(p);
        });
    }
    connect(n, &KNotification::closed, this, [this, handle, n] {
        if (m_shown.value(handle) == n) {
            m_shown.remove(handle);
        }
    });
    m_shown.insert(handle, n);
    n->sendEvent();
}

void Notifier::notifySummary(const QList<QJsonObject> &problems)
{
    bool failed = false;
    QStringList titles;
    for (const QJsonObject &p : problems) {
        failed = failed || p[u"severity"_s].toString() == u"failed"_s;
        titles << u"• "_s + p[u"title"_s].toString().toHtmlEscaped();
    }
    auto *n = new KNotification(u"summary"_s, failed ? KNotification::Persistent : KNotification::CloseOnTimeout);
    n->setComponentName(u"sparky-stereo-problems"_s);
    n->setUrgency(failed ? KNotification::CriticalUrgency : KNotification::NormalUrgency);
    n->setTitle(i18ncp("@title", "One problem needs attention", "%1 problems need attention", problems.size()));
    n->setText(titles.join(u"<br/>"_s));
    // Show details opens one notification per problem, each with its own buttons
    auto expand = [this, problems] {
        if (m_summary) {
            m_summary->close();
        }
        for (const QJsonObject &p : problems) {
            notifyOne(p);
        }
    };
    connect(n->addDefaultAction(i18nc("@action:button", "Show details")), &KNotificationAction::activated, this, expand);
    connect(n->addAction(i18nc("@action:button", "Show details")), &KNotificationAction::activated, this, expand);
    m_summary = n;
    n->sendEvent();
}

void Notifier::showDetails(const QJsonObject &p)
{
    QStringList lines;
    lines << p[u"title"_s].toString() << QString() << p[u"text"_s].toString() << QString();
    lines << i18nc("@info", "Kept since: %1", p[u"first"_s].toString());
    lines << i18nc("@info", "Last kept: %1", p[u"time"_s].toString());
    lines << i18nc("@info", "Kept in: %1", p[u"file"_s].toString());
    if (!p[u"unit"_s].toString().isEmpty()) {
        lines << i18nc("@info", "Service: %1", p[u"unit"_s].toString());
    }
    const QJsonArray command = p[u"command"_s].toArray();
    if (!command.isEmpty()) {
        lines << i18nc("@info", "Command: %1", commandLine(command));
    }
    if (p[u"status"_s].isDouble()) {
        lines << i18nc("@info", "Exit status: %1", p[u"status"_s].toInteger());
    }
    for (const QJsonValue &r : p[u"repair"_s].toArray()) {
        lines << i18nc("@info", "Repair: %1", commandLine(r.toArray()));
    }
    const QJsonObject last = p[u"last_repair"_s].toObject();
    if (!last.isEmpty()) {
        lines << i18nc("@info %1 a command, %2 its exit status, %3 when", "Last repair: %1, exit status %2, at %3", commandLine(last[u"command"_s].toArray()),
                       last[u"status"_s].toInteger(), last[u"time"_s].toString());
        if (!last[u"output"_s].toString().isEmpty()) {
            lines << QString() << i18nc("@info", "Output of the last repair:") << last[u"output"_s].toString();
        }
    }
    if (!p[u"output"_s].toString().isEmpty()) {
        lines << QString() << i18nc("@info", "Output:") << p[u"output"_s].toString();
    }
    const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR", QDir::tempPath());
    QSaveFile file(runtime + u"/sparky-stereo-problems/details-"_s + QString::number(qHash(handleOf(p)), 16) + u".txt"_s);
    if (!file.open(QIODevice::WriteOnly) || file.write(lines.join(u'\n').toUtf8() + '\n') < 0 || !file.commit()) {
        tell(u"error"_s, i18nc("@title", "The details cannot be shown"), file.errorString());
        return;
    }
    if (!QProcess::startDetached(u"kdialog"_s, {u"--title"_s, p[u"title"_s].toString(), u"--textbox"_s, file.fileName(), u"760"_s, u"460"_s})) {
        tell(u"error"_s, i18nc("@title", "The details cannot be shown"), i18nc("@info", "kdialog could not be started."));
    }
}

void Notifier::repair(const QJsonObject &p)
{
    const QString scope = p[u"scope"_s].toString();
    QStringList args = {u"repair"_s, u"--"_s + scope, p[u"package"_s].toString(), p[u"key"_s].toString()};
    QString program = s_engine;
    if (scope != u"person"_s) {
        // the machine's problems are root's: org.sparkylinux.problems.repair, which runs only repair
        args.prepend(s_engine);
        program = u"pkexec"_s;
    }
    auto *process = new QProcess(this);
    process->setProcessChannelMode(QProcess::MergedChannels);
    const QString title = p[u"title"_s].toString();
    connect(process, &QProcess::errorOccurred, this, [this, process, title](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            tell(u"error"_s, i18nc("@title", "The repair did not run"), i18nc("@info", "%1 could not be started: %2", process->program(), process->errorString()));
            process->deleteLater();
        }
    });
    connect(process, &QProcess::finished, this, [this, process, title, program](int code, QProcess::ExitStatus status) {
        process->deleteLater();
        if (status == QProcess::NormalExit && code == 0) {
            tell(u"repaired"_s, i18nc("@title", "It works again"), title.toHtmlEscaped());
        } else if (program == u"pkexec"_s && (code == 126 || code == 127)) {
            tell(u"error"_s, i18nc("@title", "The repair did not run"),
                 i18nc("@info", "The administrator's permission was not given (pkexec exit status %1).", code));
        } else if (code == 2) {
            tell(u"error"_s, i18nc("@title", "The repair did not run"), QString::fromUtf8(process->readAll()).trimmed().toHtmlEscaped());
        }
        // a repair that failed is kept by the engine as a new generation: the problem is shown again with it
        rescan();
    });
    process->start(program, args);
}

void Notifier::hide(const QJsonObject &p)
{
    const QByteArray package = p[u"package"_s].toString().toUtf8();
    const QByteArray key = p[u"key"_s].toString().toUtf8();
    if (ssp_hide(scopeCode(p[u"scope"_s].toString()), package.constData(), key.constData()) != 0) {
        tell(u"error"_s, i18nc("@title", "The problem could not be hidden"), QString::fromUtf8(ssp_error()).toHtmlEscaped());
        return;
    }
    closeShown(handleOf(p));
}

void Notifier::runAction(const QJsonObject &p, int index)
{
    const QJsonArray actions = p[u"actions"_s].toArray();
    const QJsonArray command = actions.at(index).toObject()[u"command"_s].toArray();
    QStringList args;
    for (int i = 1; i < command.size(); ++i) {
        args << command.at(i).toString();
    }
    const QString program = command.at(0).toString();
    if (program.isEmpty() || !QProcess::startDetached(program, args)) {
        tell(u"error"_s, i18nc("@title", "The action did not run"), i18nc("@info", "%1 could not be started.", commandLine(command)).toHtmlEscaped());
    }
}

void Notifier::tell(const QString &event, const QString &title, const QString &text)
{
    auto *n = new KNotification(event, KNotification::CloseOnTimeout);
    n->setComponentName(u"sparky-stereo-problems"_s);
    n->setTitle(title);
    n->setText(text);
    n->sendEvent();
}
