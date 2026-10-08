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
    QString output() const;

Q_SIGNALS:
    void transmitted(bool on, bool acknowledged);
    void failed(const QString &message);

private:
    void next();
    void start(const QStringList &arguments, bool configuring);
    void finished(int exitCode, QProcess::ExitStatus status);

    AdapterConfig m_config;
    QString m_command;
    QProcess m_process;
    QTimer m_timeout;
    QQueue<bool> m_pending;
    std::optional<bool> m_screenOn;
    bool m_busy = false;
    bool m_configuring = false;
    bool m_attemptedConfiguration = false;
    bool m_currentOn = false;
};
