// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "adapter.h"
#include <KScreenDpms/Dpms>
#include <QFileSystemWatcher>

class CecController : public QObject
{
    Q_OBJECT

public:
    CecController(const QString &devices, const QString &drm, const QHash<QString, QString> &bindings,
                  const QString &command = QStringLiteral("/usr/bin/cec-ctl"), QObject *parent = nullptr);
    void setSessionActive(bool active);

Q_SIGNALS:
    void transmitted(const QString &output, bool on, bool acknowledged);
    void failed(const QString &message);
    void skipped(const QString &message);

private:
    void rescan();
    QString m_devices;
    QString m_drm;
    QString m_command;
    QHash<QString, QString> m_bindings;
    KScreen::Dpms m_dpms;
    QFileSystemWatcher m_watcher;
    QHash<QString, CecAdapter *> m_adapters;
    QHash<QString, bool> m_modes;
    bool m_active = false;
};
