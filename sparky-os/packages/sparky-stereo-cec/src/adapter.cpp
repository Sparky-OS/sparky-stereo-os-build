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

namespace
{
struct State {
    bool readable = false;
    bool ready = false;
    bool configurable = false;
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
    bool playback = false;
    for (uint i = 0; i < addresses.num_log_addrs && i < CEC_MAX_LOG_ADDRS; ++i) {
        playback |= addresses.log_addr[i] == CEC_LOG_ADDR_PLAYBACK_1 || addresses.log_addr[i] == CEC_LOG_ADDR_PLAYBACK_2 || addresses.log_addr[i] == CEC_LOG_ADDR_PLAYBACK_3;
    }
    return {readable, readable && playback && physical != CEC_PHYS_ADDR_INVALID,
            readable && addresses.num_log_addrs == 0 && bool(caps.capabilities & CEC_CAP_LOG_ADDRS)
                && (physical != CEC_PHYS_ADDR_INVALID || (config.setPhysicalAddress && QFile::exists(config.edid)))};
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
    if (m_busy) {
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
            start(arguments, true);
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
    start({QStringLiteral("--device=") + m_config.device, QStringLiteral("--skip-info"), QStringLiteral("--verbose"), QStringLiteral("--to=0"),
           m_currentOn ? QStringLiteral("--image-view-on") : QStringLiteral("--standby")}, false);
}

void CecAdapter::start(const QStringList &arguments, bool configuring)
{
    m_busy = true;
    m_configuring = configuring;
    m_process.start(m_command, arguments);
    m_timeout.start(10000);
}

void CecAdapter::finished(int exitCode, QProcess::ExitStatus status)
{
    m_timeout.stop();
    m_busy = false;
    const auto output = QString::fromLocal8Bit(m_process.readAll());
    const bool exited = status == QProcess::NormalExit && exitCode == 0;
    if (m_configuring) {
        if (!exited || !state(m_config).ready) {
            m_pending.clear();
            Q_EMIT failed(QStringLiteral("CEC playback configuration failed: ") + output);
            return;
        }
    } else {
        const bool acknowledged = exited && QRegularExpression(QStringLiteral("(^|\\n)\\s*Tx, OK\\b")).match(output).hasMatch();
        Q_EMIT transmitted(m_currentOn, acknowledged);
        if (!acknowledged) {
            Q_EMIT failed(QStringLiteral("CEC message was not acknowledged: ") + output);
        }
    }
    next();
}
