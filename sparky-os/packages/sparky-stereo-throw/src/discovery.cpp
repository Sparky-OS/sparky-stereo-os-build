// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include "discovery.h"
#include "logging.h"

namespace Throw
{

Discovery::Discovery(QObject *parent)
    : QObject(parent)
{
}

bool Discovery::start()
{
    if (KDNSSD::ServiceBrowser::isAvailable() != KDNSSD::ServiceBrowser::Working) {
        m_error = QStringLiteral("DNS-SD is not available (the Avahi service is not running)");
        return false;
    }
    m_browser = new KDNSSD::ServiceBrowser(QStringLiteral("_googlecast._tcp"), true, QString(), QString());
    m_browser->setParent(this);
    connect(m_browser, &KDNSSD::ServiceBrowser::serviceAdded, this, &Discovery::onAdded);
    connect(m_browser, &KDNSSD::ServiceBrowser::serviceRemoved, this, &Discovery::onRemoved);
    m_browser->startBrowse();
    return true;
}

std::optional<Device> Discovery::device(const QString &id) const
{
    const auto it = m_devices.constFind(id);
    if (it == m_devices.constEnd()) {
        return std::nullopt;
    }
    return *it;
}

void Discovery::onAdded(KDNSSD::RemoteService::Ptr service)
{
    const auto txt = service->textData();
    Device device;
    device.id = QString::fromUtf8(txt.value(QStringLiteral("id")));
    device.name = QString::fromUtf8(txt.value(QStringLiteral("fn")));
    device.model = QString::fromUtf8(txt.value(QStringLiteral("md")));
    device.host = service->hostName();
    device.port = service->port();
    device.group = device.port != 8009;
    device.service = service->serviceName();
    device.address = KDNSSD::ServiceBrowser::resolveHostName(device.host);
    if (device.id.isEmpty()) {
        // a record without an identity cannot be thrown to as the same screen again: kept under its service name
        device.id = device.service;
    }
    if (device.name.isEmpty()) {
        device.name = device.service;
    }
    qCInfo(THROW) << "found" << device.name << device.model << device.host << device.address << device.port << (device.group ? "group" : "");
    const bool known = m_devices.contains(device.id);
    m_devices.insert(device.id, device);
    if (!known) {
        Q_EMIT deviceAdded(device);
    }
}

void Discovery::onRemoved(KDNSSD::RemoteService::Ptr service)
{
    for (auto it = m_devices.begin(); it != m_devices.end(); ++it) {
        if (it->service == service->serviceName()) {
            const QString id = it->id;
            qCInfo(THROW) << "gone" << it->name;
            m_devices.erase(it);
            Q_EMIT deviceRemoved(id);
            return;
        }
    }
}

} // namespace Throw
