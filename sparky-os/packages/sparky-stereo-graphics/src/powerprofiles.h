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
    // The active profile, or why it could not be read: no system bus, the daemon not running, no answer, a profile name this
    // page does not know. SPARKY_STEREO_POWER_PROFILE overrides it (tests, the command line); a value that names no profile
    // is said too. Nothing stands in for a profile that could not be read (Daniel, 2026-11-01).
    static ProfileReading read();
    static bool daemonAvailable();
    // Only the actions that concern the graphics processor
    static QList<PowerAction> gpuActions();
    static bool setActionEnabled(const QString &name, bool enabled);
};

}
