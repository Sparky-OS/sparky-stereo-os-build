// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "appentries.h"
#include "gpuinventory.h"
#include "graphicssettings.h"

#include <QStringList>

namespace SparkyGraphics
{

enum class PowerProfile {
    PowerSaver,
    Balanced,
    Performance,
};

PowerProfile powerProfileFromString(const QString &name, PowerProfile fallback = PowerProfile::Balanced);
QString powerProfileToString(PowerProfile profile);

struct Resolution {
    int gpuIndex = -1; // into the inventory, -1 when the machine has no GPU
    bool isMain = true;
    bool missing = false; // the saved choice names a GPU that is not here
    QString reason; // "app", "choice", "profile:performance", "only-gpu", ...
    QStringList environment; // KEY=value lines; empty for the main GPU
};

class Resolver
{
public:
    Resolver(const QList<Gpu> &gpus, const QString &savedMainGpu, PowerProfile profile);

    // The GPU that draws the desktop after the next login
    int mainIndex() const;
    // What Automatic picks as the main GPU: render-capable, internal panel first, most screens, boot VGA
    int automaticMainIndex() const;
    int indexOfId(const QString &id) const;

    // Pins every choice to a GPU: "auto" follows the profile, "integrated"/"discrete" pick a kind, an id picks a GPU
    Resolution resolveChoice(const QString &choice) const;
    Resolution resolveCategory(Category category, const GraphicsSettings &settings) const;
    Resolution resolveApp(const AppEntry &entry, const GraphicsSettings &settings) const;

    // What Automatic means now: "integrated", "main" (the balanced default) or "discrete"
    static QString automaticTarget(PowerProfile profile);

    // Value of KWIN_DRM_DEVICES that puts the main GPU first, or empty when the saved choice is Automatic or missing
    QString kwinDrmDevices() const;

    // The variables that send a program to the GPU (switcheroo-control's own set when it is known)
    static QStringList environmentFor(const Gpu &gpu);

    const QList<Gpu> &gpus() const;

private:
    Resolution make(int index, const QString &reason) const;
    int firstOfKind(GpuKind kind) const;

    QList<Gpu> m_gpus;
    QString m_savedMain;
    PowerProfile m_profile;
};

}
