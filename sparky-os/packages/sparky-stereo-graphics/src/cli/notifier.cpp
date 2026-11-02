// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "notifier.h"

#include "graphicssettings.h"

#include <KLocalizedString>

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusError>
#include <QDir>
#include <QFileInfo>
#include <QFile>
#include <QProcess>
#include <QSaveFile>
#include <QTextStream>

using namespace Qt::StringLiterals;
using namespace SparkyGraphics;

static const QString s_service = u"org.freedesktop.Notifications"_s;
static const QString s_path = u"/org/freedesktop/Notifications"_s;

Notifier::Notifier(const QString &root, QObject *parent)
    : QObject(parent)
    , m_root(root)
{
    const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (!runtime.isEmpty()) {
        m_seenFile = runtime + u"/sparky-stereo-graphics-notified"_s;
        QFile file(m_seenFile);
        if (file.open(QIODevice::ReadOnly)) {
            const QStringList lines = QString::fromUtf8(file.readAll()).split(u'\n', Qt::SkipEmptyParts);
            m_seen = QSet<QString>(lines.cbegin(), lines.cend());
        }
    }
}

int Notifier::run()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        QTextStream(stderr) << "sparky-stereo-gpu-env: the session bus cannot be reached, so the kept problems cannot be shown: " << bus.lastError().message()
                            << '\n';
        return 1;
    }
    bus.connect(s_service, s_path, s_service, u"ActionInvoked"_s, this, SLOT(actionInvoked(uint, QString)));
    bus.connect(s_service, s_path, s_service, u"NotificationClosed"_s, this, SLOT(notificationClosed(uint, uint)));
    for (const QString &dir : {Problems::userDir(), Problems::systemDir(m_root)}) {
        QDir().mkpath(dir); // watched while the notifications are open; the person's own folder is theirs to create
        if (QFileInfo::exists(dir)) {
            m_watcher.addPath(dir);
        }
    }
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &Notifier::rescan);
    rescan();
    if (m_shown.isEmpty()) {
        return m_failures ? 1 : 0;
    }
    QCoreApplication::exec();
    return m_failures ? 1 : 0;
}

void Notifier::rescan()
{
    const QList<Problem> problems = Problems::all(m_root);
    for (const Problem &problem : problems) {
        const QString ident = (problem.system ? u"system:"_s : QString()) + problem.key + u'@' + problem.time;
        if (m_seen.contains(ident)) {
            continue;
        }
        QStringList actions = {u"default"_s, i18nc("@action:button", "Open Graphics settings")};
        if (problem.isChoice()) {
            for (const Alternative &gpu : problem.alternatives) {
                if (gpu.id != problem.requested) {
                    actions << u"use:"_s + gpu.id << i18nc("@action:button %1 is a GPU name", "Use %1", gpu.name);
                }
            }
        }
        actions << u"open"_s << i18nc("@action:button", "Open Graphics settings");
        QDBusMessage call = QDBusMessage::createMethodCall(s_service, s_path, s_service, u"Notify"_s);
        call.setArguments({u"Sparky Stereo OS"_s,
                           0u,
                           u"video-card"_s,
                           Problems::title(problem),
                           Problems::message(problem),
                           actions,
                           QVariantMap{{u"urgency"_s, QVariant::fromValue<uchar>(2)}},
                           0});
        const QDBusMessage reply = QDBusConnection::sessionBus().call(call, QDBus::Block, 30000);
        if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty()) {
            // said where the session keeps its log, in English for support too
            QTextStream(stderr) << "sparky-stereo-gpu-env: the notification could not be shown (" << reply.errorMessage() << "): " << Problems::message(problem)
                                << '\n';
            ++m_failures;
            continue;
        }
        m_shown.insert(reply.arguments().first().toUInt(), problem);
        m_seen.insert(ident);
    }
    if (!m_seenFile.isEmpty()) {
        QSaveFile file(m_seenFile);
        if (file.open(QIODevice::WriteOnly)) {
            QStringList lines(m_seen.cbegin(), m_seen.cend());
            lines.sort();
            file.write(lines.join(u'\n').toUtf8() + '\n');
            file.commit();
        }
    }
}

void Notifier::use(const Problem &problem, const QString &gpu)
{
    GraphicsSettings settings;
    if (problem.key == u"main-gpu"_s) {
        settings.setMainGpu(gpu);
    } else {
        for (Category category : allCategories()) {
            if (categoryKey(category).toLower() == problem.key) {
                settings.setRenderChoice(category, gpu);
            }
        }
    }
    if (!settings.save()) {
        QTextStream(stderr) << "sparky-stereo-gpu-env: " << i18nc("@info", "The graphics settings could not be saved.") << '\n';
        ++m_failures;
        return;
    }
    // the person chose a GPU that is here: the problem of the old choice is over
    Problems::clear(problem.key, Problems::userDir());
}

void Notifier::actionInvoked(uint id, const QString &action)
{
    const auto it = m_shown.constFind(id);
    if (it == m_shown.cend()) {
        return;
    }
    if (action.startsWith(u"use:"_s)) {
        use(it.value(), action.mid(4));
    } else {
        QProcess::startDetached(u"systemsettings"_s, {u"kcm_sparkystereo_graphics"_s});
    }
    QDBusMessage close = QDBusMessage::createMethodCall(s_service, s_path, s_service, u"CloseNotification"_s);
    close.setArguments({id});
    QDBusConnection::sessionBus().call(close, QDBus::NoBlock);
    m_shown.remove(id);
    finishIfDone();
}

void Notifier::notificationClosed(uint id, uint reason)
{
    Q_UNUSED(reason)
    if (m_shown.remove(id)) {
        finishIfDone();
    }
}

void Notifier::finishIfDone()
{
    if (m_shown.isEmpty()) {
        QCoreApplication::quit();
    }
}
