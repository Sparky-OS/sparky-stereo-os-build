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
    QString reason; // "app", "choice", "profile:performance", "measured", "unmeasured", "only-gpu", ...
    QStringList environment; // KEY=value lines; empty for the main GPU
};

class Resolver
{
public:
    // measuredBest: the machine record's GPU for players and 3D ("pci-0000:03:00.0" or "1002:6660"), empty when not measured
    Resolver(const QList<Gpu> &gpus, const QString &savedMainGpu, PowerProfile profile, const QString &measuredBest = QString());

    // The GPU that draws the desktop after the next login
    int mainIndex() const;
    // What Automatic picks as the main GPU: render-capable, internal panel first, most screens, boot VGA
    int automaticMainIndex() const;
    int indexOfId(const QString &id) const;

    // The GPU the machine record names, when it is here and usable, else -1
    int measuredIndex() const;
    // Where players and 3D go on Automatic: the measured GPU, else the first discrete GPU, else the main GPU
    int presentingIndex() const;

    // Pins every choice to a GPU. "auto" is Automatic for that kind of program (stereo: it presents 3D),
    // "profile" follows the power profile, "integrated"/"discrete" pick a kind, an id picks a GPU
    Resolution resolveChoice(const QString &choice, Category category = Category::Other, bool stereo = false) const;
    Resolution resolveCategory(Category category, const GraphicsSettings &settings, bool stereo = false) const;
    Resolution resolveApp(const AppEntry &entry, const GraphicsSettings &settings, bool stereo = false) const;

    // What Automatic means for a kind of program now: "measured" (players, and any program while it
    // presents 3D, whatever the profile), else "integrated", "main" or "discrete" by the power profile
    static QString automaticTarget(Category category, PowerProfile profile, bool stereo = false);

    // Value of KWIN_DRM_DEVICES that puts the main GPU first, or empty when the saved choice is Automatic or missing
    QString kwinDrmDevices() const;

    // The variables that send a program to the GPU (switcheroo-control's own set when it is known)
    static QStringList environmentFor(const Gpu &gpu);

    const QList<Gpu> &gpus() const;

private:
    Resolution make(int index, const QString &reason) const;
    int firstOfKind(GpuKind kind) const;
    int defaultIndex() const;

    QList<Gpu> m_gpus;
    QString m_savedMain;
    PowerProfile m_profile;
    QString m_measuredBest;
};

}
