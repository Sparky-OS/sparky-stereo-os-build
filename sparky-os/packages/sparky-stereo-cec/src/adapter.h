// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QHash>
#include <QObject>
#include <QProcess>
#include <QQueue>
#include <QTimer>
#include <optional>

struct AdapterConfig
{
    QString device;
    QString output;
    QString edid;
    bool setPhysicalAddress = false;
};

QList<AdapterConfig> discoverAdapters(const QString &deviceDirectory, const QString &drmDirectory, const QStringList &outputs, const QHash<QString, QString> &bindings);

class CecAdapter : public QObject
{
    Q_OBJECT

public:
    explicit CecAdapter(const AdapterConfig &config, const QString &command = QStringLiteral("/usr/bin/cec-ctl"), QObject *parent = nullptr);
    void setScreenOn(bool on);
    void setActive(bool active);
    QString output() const;

Q_SIGNALS:
    void transmitted(bool on, bool acknowledged);
    void failed(const QString &message);
    void skipped(const QString &message);

private:
    void next();
    enum class Operation { Idle, Configure, CheckSource, Standby, ViewOn, AnnounceSource };
    void start(const QStringList &arguments, Operation operation);
    void send(Operation operation);
    void finished(int exitCode, QProcess::ExitStatus status);

    AdapterConfig m_config;
    QString m_command;
    QProcess m_process;
    QTimer m_timeout;
    QQueue<bool> m_pending;
    std::optional<bool> m_screenOn;
    bool m_busy = false;
    Operation m_operation = Operation::Idle;
    bool m_active = true;
    int m_physical = -1;
    int m_standbyPhysical = -1;
    bool m_attemptedConfiguration = false;
    bool m_currentOn = false;
};
