// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#include "adapter.h"

#include <QFile>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <fcntl.h>
#include <linux/cec.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <utility>

namespace
{

struct State
{
    bool ready = false;
    bool configurable = false;
    int source = -1;
    int physical = -1;
};

State state(const AdapterConfig &config)
{
    const int fd = open(QFile::encodeName(config.device).constData(), O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        return {};
    }
    cec_caps caps = {};
    cec_log_addrs addresses = {};
    __u16 physical = CEC_PHYS_ADDR_INVALID;
    const bool readable = ioctl(fd, CEC_ADAP_G_CAPS, &caps) == 0 && (caps.capabilities & CEC_CAP_TRANSMIT)
        && ioctl(fd, CEC_ADAP_G_PHYS_ADDR, &physical) == 0 && ioctl(fd, CEC_ADAP_G_LOG_ADDRS, &addresses) == 0;
    close(fd);
    int source = -1;
    for (uint i = 0; i < addresses.num_log_addrs && i < CEC_MAX_LOG_ADDRS; ++i) {
        if (addresses.log_addr[i] == CEC_LOG_ADDR_PLAYBACK_1 || addresses.log_addr[i] == CEC_LOG_ADDR_PLAYBACK_2 || addresses.log_addr[i] == CEC_LOG_ADDR_PLAYBACK_3) {
            source = addresses.log_addr[i];
            break;
        }
    }
    return {readable && source >= 0 && physical != CEC_PHYS_ADDR_INVALID,
            readable && addresses.num_log_addrs == 0 && bool(caps.capabilities & CEC_CAP_LOG_ADDRS)
                && (physical != CEC_PHYS_ADDR_INVALID || (config.setPhysicalAddress && QFile::exists(config.edid))),
            source, physical};
}

}

CecAdapter::CecAdapter(const AdapterConfig &config, const QString &command, QObject *parent)
    : QObject(parent)
    , m_config(config)
    , m_command(command)
{
    m_process.setProcessChannelMode(QProcess::MergedChannels);
    auto environment = QProcessEnvironment::systemEnvironment();
    environment.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));
    m_process.setProcessEnvironment(environment);
    m_timeout.setSingleShot(true);
    connect(&m_timeout, &QTimer::timeout, &m_process, &QProcess::kill);
    connect(&m_process, &QProcess::finished, this, &CecAdapter::finished);
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            m_timeout.stop();
            m_busy = false;
            m_pending.clear();
            Q_EMIT failed(m_process.errorString());
        }
    });
}

QString CecAdapter::output() const
{
    return m_config.output;
}

void CecAdapter::setScreenOn(bool on)
{
    if (m_screenOn == on) {
        return;
    }
    if (!on || m_screenOn.has_value()) {
        m_pending.enqueue(on);
    }
    m_screenOn = on;
    m_attemptedConfiguration = false;
    next();
}

void CecAdapter::next()
{
    if (m_busy || !m_active) {
        return;
    }
    const auto current = state(m_config);
    if (!current.ready) {
        if (current.configurable && !m_attemptedConfiguration) {
            m_attemptedConfiguration = true;
            QStringList arguments{QStringLiteral("--device=") + m_config.device, QStringLiteral("--skip-info"), QStringLiteral("--playback"), QStringLiteral("--osd-name=Sparky Stereo"), QStringLiteral("--no-rc")};
            if (m_config.setPhysicalAddress) {
                arguments.append(QStringLiteral("--phys-addr-from-edid=") + m_config.edid);
            }
            start(arguments, Operation::Configure);
        } else {
            m_pending.clear();
            Q_EMIT failed(QStringLiteral("CEC adapter has no usable playback address: ") + m_config.device);
        }
        return;
    }
    if (m_pending.isEmpty()) {
        return;
    }
    m_currentOn = m_pending.dequeue();
    m_physical = current.physical;
    if (m_currentOn) {
        if (m_standbyPhysical != current.physical) {
            m_standbyPhysical = -1;
            Q_EMIT skipped(QStringLiteral("CEC wake skipped: this helper did not put the current TV in standby"));
            next();
            return;
        }
        send(Operation::ViewOn);
    } else {
        m_standbyPhysical = -1;
        send(Operation::CheckSource);
    }
}

void CecAdapter::setActive(bool active)
{
    m_active = active;
    if (!active) {
        m_pending.clear();
        m_operation = Operation::Idle;
        m_timeout.stop();
        if (m_busy) {
            m_process.kill();
        }
    } else {
        next();
    }
}

void CecAdapter::send(Operation operation)
{
    const auto current = state(m_config);
    if (!current.ready || current.physical != m_physical) {
        m_standbyPhysical = -1;
        m_pending.clear();
        Q_EMIT failed(QStringLiteral("CEC address changed during power request: ") + m_config.device);
        return;
    }
    QStringList arguments{QStringLiteral("--device=") + m_config.device, QStringLiteral("--skip-info"), QStringLiteral("--verbose"),
                          QStringLiteral("--from=") + QString::number(current.source)};
    switch (operation) {
    case Operation::CheckSource:
        arguments << QStringLiteral("--to=15") << QStringLiteral("--timeout=1000") << QStringLiteral("--request-active-source");
        break;
    case Operation::Standby:
        arguments << QStringLiteral("--to=0") << QStringLiteral("--standby");
        break;
    case Operation::ViewOn:
        arguments << QStringLiteral("--to=0") << QStringLiteral("--image-view-on");
        break;
    case Operation::AnnounceSource:
        arguments << QStringLiteral("--to=15") << QStringLiteral("--active-source=phys-addr=0x") + QString::number(current.physical, 16);
        break;
    default:
        return;
    }
    start(arguments, operation);
}

void CecAdapter::start(const QStringList &arguments, Operation operation)
{
    m_busy = true;
    m_operation = operation;
    m_process.start(m_command, arguments);
    m_timeout.start(10000);
}

void CecAdapter::finished(int exitCode, QProcess::ExitStatus status)
{
    m_timeout.stop();
    m_busy = false;
    const auto output = QString::fromLocal8Bit(m_process.readAll());
    const auto operation = std::exchange(m_operation, Operation::Idle);
    if (!m_active || operation == Operation::Idle) {
        next();
        return;
    }
    const bool exited = status == QProcess::NormalExit && exitCode == 0;
    const bool acknowledged = exited && QRegularExpression(QStringLiteral("(^|\\n)\\s*Tx, OK\\b")).match(output).hasMatch();
    if (operation == Operation::Configure) {
        if (!exited || !state(m_config).ready) {
            m_pending.clear();
            Q_EMIT failed(QStringLiteral("CEC playback configuration failed: ") + output);
            return;
        }
    } else if (operation == Operation::CheckSource) {
        if (!acknowledged) {
            Q_EMIT failed(QStringLiteral("CEC Request Active Source failed: ") + output);
        }
        const auto reply = QRegularExpression(QStringLiteral("Received from[^\\n]*\\n\\s*ACTIVE_SOURCE \\(0x82\\):\\s*\\n\\s*phys-addr: ([0-9a-fA-F])\\.([0-9a-fA-F])\\.([0-9a-fA-F])\\.([0-9a-fA-F])")).match(output);
        int physical = -1;
        if (acknowledged && output.contains(QStringLiteral("Rx, OK")) && reply.hasMatch()) {
            physical = 0;
            for (int i = 1; i <= 4; ++i) {
                physical = (physical << 4) | reply.captured(i).toInt(nullptr, 16);
            }
        }
        if (physical == m_physical && !m_screenOn.value_or(true)) {
            send(Operation::Standby);
            return;
        }
        Q_EMIT skipped(physical < 0                 ? QStringLiteral("CEC standby skipped: no valid Active Source reply")
                           : physical != m_physical ? QStringLiteral("CEC standby skipped: another input is the active source")
                                                    : QStringLiteral("CEC standby skipped: the screen is already on"));
    } else if (operation == Operation::Standby) {
        if (acknowledged) {
            m_standbyPhysical = m_physical;
        }
        Q_EMIT transmitted(false, acknowledged);
        if (!acknowledged) {
            Q_EMIT failed(QStringLiteral("CEC Standby was not acknowledged: ") + output);
        }
    } else if (operation == Operation::ViewOn) {
        if (acknowledged) {
            send(Operation::AnnounceSource);
            return;
        }
        m_standbyPhysical = -1;
        Q_EMIT transmitted(true, false);
        Q_EMIT failed(QStringLiteral("CEC Image View On was not acknowledged: ") + output);
    } else if (operation == Operation::AnnounceSource) {
        m_standbyPhysical = -1;
        Q_EMIT transmitted(true, acknowledged);
        if (!acknowledged) {
            Q_EMIT failed(QStringLiteral("CEC Active Source was not acknowledged: ") + output);
        }
    }
    next();
}
