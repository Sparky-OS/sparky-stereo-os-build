// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QFileSystemWatcher>
#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QPointer>
#include <QSet>
#include <QTimer>
#include <QVariantMap>

class KNotification;

// The session's side of sparky-stereo-problems (ORDER 350): every kept problem of the machine, of this boot and of
// the person, as a KDE notification (sparky-stereo-problems.notifyrc). At login one notification per open problem, or
// one summary when several are open; then one for each new or changed problem. A failed problem is Critical and stays
// until it is closed; a degraded one or a notice is Normal. Each offers Show details (the evidence), Repair (pkexec
// for the machine's and this boot's problems: org.sparkylinux.sparkystereo.problems.repair), the record's own actions and Dismiss,
// which is the person's own (the engine's hide): the problem stays listed on the Problems page of System Settings, where it is
// brought back. A notification closes when its problem is over or dismissed, on this notification or on the page.
class Notifier : public QObject
{
    Q_OBJECT

public:
    explicit Notifier(QObject *parent = nullptr);
    void start();

private Q_SLOTS:
    // systemd's unit state (Manager.Subscribe): a failed service that systemd no longer has as failed is over
    void unitChanged(const QString &interface, const QVariantMap &changed, const QStringList &invalidated);

private:
    void rescan();
    void notifyOne(const QJsonObject &problem);
    void notifySummary(const QList<QJsonObject> &problems);
    void showDetails(const QJsonObject &problem);
    void repair(const QJsonObject &problem);
    void dismiss(const QJsonObject &problem);
    void dismissAll(const QList<QJsonObject> &problems);
    void tellDismissed(int count);
    void runAction(const QJsonObject &problem, int index);
    void tell(const QString &event, const QString &title, const QString &text);
    void closeShown(const QString &handle);
    void saveNotified();

    QHash<QString, QPointer<KNotification>> m_shown; // scope/package/key -> its notification
    QPointer<KNotification> m_summary;
    QSet<QString> m_notified; // scope/package/key/id/generation, this login
    QSet<QString> m_dismissed; // the same, of the problems dismissed at the last scan: one brought back is told again
    QString m_notifiedFile;
    bool m_login = true;
    bool m_watchUnits = false;
    QFileSystemWatcher m_watcher;
    QTimer m_settle;
};
