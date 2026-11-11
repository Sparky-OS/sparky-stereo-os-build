// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <KQuickConfigModule>

#include <QFileSystemWatcher>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

// The Problems page of System Settings (ORDER 468): every problem sparky-stereo-problems keeps, the current ones and
// the ones the person dismissed, with Repair, Dismiss and Bring back. Dismiss and Bring back are the engine's hide
// and show, so the notifier and this page always agree. The page follows the stores: a problem that appears or ends
// is listed or goes at once.
class ProblemsKcm : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(QVariantList current READ current NOTIFY changed)
    Q_PROPERTY(QVariantList dismissed READ dismissed NOTIFY changed)
    Q_PROPERTY(QString errorText READ errorText NOTIFY messageChanged)
    Q_PROPERTY(QString noticeText READ noticeText NOTIFY messageChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    ProblemsKcm(QObject *parent, const KPluginMetaData &data);

    QVariantList current() const { return m_current; }
    QVariantList dismissed() const { return m_dismissed; }
    QString errorText() const { return m_error; }
    QString noticeText() const { return m_notice; }
    bool busy() const { return m_busy; }

    // HANDLE is the entry's "handle": scope/package/key
    Q_INVOKABLE void dismiss(const QString &handle);
    Q_INVOKABLE void bringBack(const QString &handle);
    Q_INVOKABLE void repair(const QString &handle);
    Q_INVOKABLE void runAction(const QString &handle, int index);
    Q_INVOKABLE void refresh();

    void load() override;

Q_SIGNALS:
    void changed();
    void messageChanged();
    void busyChanged();

private Q_SLOTS:
    void unitChanged(const QString &interface, const QVariantMap &changed, const QStringList &invalidated);

private:
    QVariantMap find(const QString &handle) const;
    void setMessages(const QString &error, const QString &notice);
    void watchStores();

    QVariantList m_current;
    QVariantList m_dismissed;
    QString m_error;
    QString m_notice;
    bool m_busy = false;
    QFileSystemWatcher m_watcher;
    QTimer m_settle;
};
