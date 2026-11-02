// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "appentries.h"
#include "gpuinventory.h"
#include "graphicssettings.h"

#include <QStringList>

#include <optional>

namespace SparkyGraphics
{

enum class PowerProfile {
    PowerSaver,
    Balanced,
    Performance,
};

// The name power-profiles-daemon gives a profile, or nothing for a name that is not one
std::optional<PowerProfile> powerProfileFromString(const QString &name);
QString powerProfileToString(PowerProfile profile);

// The power profile as it could be read: the profile, or why it could not be read
struct ProfileReading {
    std::optional<PowerProfile> profile;
    // "not-running", "no-bus", "no-answer", "unknown" (the daemon named another profile) or "override" (SPARKY_STEREO_POWER_PROFILE
    // names no profile); detail is the D-Bus error or the name
    QString error;
    QString detail;

    ProfileReading() = default;
    ProfileReading(PowerProfile known)
        : profile(known)
    {
    }
};

struct Resolution {
    int gpuIndex = -1; // into the inventory, -1 when the machine has no GPU or the choice cannot be used
    bool isMain = true;
    bool missing = false; // the choice cannot be used: problem says why
    QString reason; // "app", "choice", "profile:performance", "desktop", "measured", "unmeasured", "measured-missing", "only-gpu", ...
    QStringList environment; // KEY=value lines; empty for the main GPU
    // Why the choice cannot be used; nothing else is put in its place (Daniel, 2026-11-01: "either it works or not and the user
    // must know"): "gpu-missing" (no GPU at that PCI address has a graphics device), "gpu-cannot-render" (here, no render node),
    // "gpu-not-allowed" (the account may not open its render node), "kind-missing" (no integrated or discrete GPU),
    // "profile-unreadable" (the choice follows the power profile, which could not be read)
    QString problem;
    QString requested; // the choice that cannot be used: a GPU id, "integrated", "discrete", "profile" or "auto"
    int requestedIndex = -1; // the GPU that was asked for, when it is here but cannot be used
    // Automatic or the power profile asked for a kind this computer has no usable GPU of ("integrated", "discrete"), so the
    // GPU that draws the desktop: the rule of that choice, said on the page
    QString kindAbsent;
};

class Resolver
{
public:
    // measuredBest: the machine record's GPU for players and 3D ("pci-0000:03:00.0" or "1002:6660"), empty when not measured
    Resolver(const QList<Gpu> &gpus, const QString &savedMainGpu, const ProfileReading &profile, const QString &measuredBest = QString());

    // The GPU that draws the desktop after the next login: the saved one when it can draw, else what Automatic picks
    int mainIndex() const;
    // Why the saved main GPU cannot draw the desktop (problem empty when it can, or when the choice is Automatic)
    Resolution mainProblem() const;
    // The GPUs a program can be sent to, offered as explicit choices when a choice cannot be used
    QList<int> usableIndices() const;
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

    // What Automatic means for a kind of program now: "measured" for players, games and any program while it
    // presents 3D, whatever the profile; for browsers "integrated", "main" or "discrete" by the power profile;
    // "main" (the GPU that draws the desktop) for other programs
    static QString automaticTarget(Category category, PowerProfile profile, bool stereo = false);
    // What the power profile asks for: "integrated", "main" or "discrete"
    static QString profileTarget(PowerProfile profile);

    // Value of KWIN_DRM_DEVICES that puts the main GPU first, or empty when the saved choice is Automatic or missing
    QString kwinDrmDevices() const;

    // The variables that send a program to the GPU (switcheroo-control's own set when it is known)
    static QStringList environmentFor(const Gpu &gpu);

    const QList<Gpu> &gpus() const;

private:
    Resolution make(int index, const QString &reason) const;
    Resolution cannotUse(const QString &problem, const QString &requested, int requestedIndex = -1) const;
    // The person's choice of one GPU, by its id or by its kind, checked whatever the number of GPUs
    Resolution resolveGpu(const QString &choice) const;
    int firstOfKind(GpuKind kind) const;
    int defaultIndex() const;
    bool measuredNamesAbsentGpu() const;

    QList<Gpu> m_gpus;
    QString m_savedMain;
    ProfileReading m_profile;
    QString m_measuredBest;
};

}
