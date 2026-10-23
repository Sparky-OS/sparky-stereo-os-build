// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "resolver.h"

#include <QList>
#include <QString>

namespace SparkyGraphics
{

struct PowerAction {
    QString name; // "amdgpu_dpm"
    QString description;
    bool enabled = false;
};

// power-profiles-daemon over the system bus (net.hadess.PowerProfiles).
class PowerProfiles
{
public:
    // The active profile; SPARKY_STEREO_POWER_PROFILE overrides it (tests, the command line); Balanced when the daemon is absent.
    static PowerProfile active();
    static bool daemonAvailable();
    // Only the actions that concern the graphics processor
    static QList<PowerAction> gpuActions();
    static bool setActionEnabled(const QString &name, bool enabled);
};

}
