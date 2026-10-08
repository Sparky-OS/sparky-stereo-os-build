// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#include "controller.h"
#include <QGuiApplication>
#include <QScreen>
#include <QSet>
#include <QTimer>

CecController::CecController(const QString &devices, const QString &drm, const QHash<QString, QString> &bindings, const QString &command, QObject *parent)
    : QObject(parent)
    , m_devices(devices)
    , m_drm(drm)
    , m_command(command)
    , m_bindings(bindings)
{
    m_watcher.addPath(devices);
    connect(&m_dpms, &KScreen::Dpms::modeChanged, this, [this](KScreen::Dpms::Mode mode, QScreen *screen) {
        m_modes.insert(screen->name(), mode == KScreen::Dpms::On);
        rescan();
    });
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &CecController::rescan);
    connect(qGuiApp, &QGuiApplication::screenAdded, this, &CecController::rescan);
    connect(qGuiApp, &QGuiApplication::screenRemoved, this, [this](QScreen *screen) {
        m_modes.remove(screen->name());
        rescan();
    });
    QTimer::singleShot(0, this, &CecController::rescan);
}

void CecController::setSessionActive(bool active)
{
    if (m_active == active) {
        return;
    }
    m_active = active;
    if (!active) {
        qDeleteAll(m_adapters);
        m_adapters.clear();
    } else {
        rescan();
    }
}

void CecController::rescan()
{
    if (!m_active) {
        return;
    }
    QStringList screens;
    for (const auto screen : qGuiApp->screens()) {
        screens.append(screen->name());
    }
    const auto found = discoverAdapters(m_devices, m_drm, screens, m_bindings);
    QSet<QString> present;
    for (const auto &device : found) {
        present.insert(device.device);
        auto adapter = m_adapters.value(device.device);
        if (adapter && adapter->output() != device.output) {
            delete m_adapters.take(device.device);
            adapter = nullptr;
        }
        if (!adapter) {
            adapter = new CecAdapter(device, m_command, this);
            m_adapters.insert(device.device, adapter);
            connect(adapter, &CecAdapter::failed, this, &CecController::failed);
            connect(adapter, &CecAdapter::transmitted, this, [this, name = device.output](bool on, bool acknowledged) {
                Q_EMIT transmitted(name, on, acknowledged);
            });
        }
        if (m_modes.contains(device.output)) {
            adapter->setScreenOn(m_modes.value(device.output));
        }
    }
    for (const auto &path : m_adapters.keys()) {
        if (!present.contains(path)) {
            delete m_adapters.take(path);
        }
    }
}
