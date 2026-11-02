// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "resolver.h"

using namespace Qt::StringLiterals;

namespace SparkyGraphics
{

std::optional<PowerProfile> powerProfileFromString(const QString &name)
{
    if (name == u"power-saver"_s) {
        return PowerProfile::PowerSaver;
    }
    if (name == u"balanced"_s) {
        return PowerProfile::Balanced;
    }
    if (name == u"performance"_s) {
        return PowerProfile::Performance;
    }
    return std::nullopt;
}

QString powerProfileToString(PowerProfile profile)
{
    switch (profile) {
    case PowerProfile::PowerSaver:
        return u"power-saver"_s;
    case PowerProfile::Performance:
        return u"performance"_s;
    case PowerProfile::Balanced:
        break;
    }
    return u"balanced"_s;
}

Resolver::Resolver(const QList<Gpu> &gpus, const QString &savedMainGpu, const ProfileReading &profile, const QString &measuredBest)
    : m_gpus(gpus)
    , m_savedMain(savedMainGpu)
    , m_profile(profile)
    , m_measuredBest(measuredBest)
{
}

int Resolver::measuredIndex() const
{
    if (m_measuredBest.isEmpty()) {
        return -1;
    }
    for (int i = 0; i < m_gpus.size(); ++i) {
        const Gpu &gpu = m_gpus.at(i);
        const QString pciId = QStringLiteral("%1:%2").arg(gpu.vendorId, 4, 16, QLatin1Char('0')).arg(gpu.deviceId, 4, 16, QLatin1Char('0'));
        if ((gpu.id == m_measuredBest || pciId == m_measuredBest) && gpu.usable()) {
            return i;
        }
    }
    return -1;
}

bool Resolver::measuredNamesAbsentGpu() const
{
    return !m_measuredBest.isEmpty() && measuredIndex() < 0;
}

int Resolver::presentingIndex() const
{
    const int measured = measuredIndex();
    if (measured >= 0) {
        return measured;
    }
    // Not measured here: the discrete GPU, which libplacebo also prefers, and which drew 3D film with far
    // fewer dropped frames than the integrated GPU that drives the screens on the A10 (ORDER 234)
    const int discrete = firstOfKind(GpuKind::Discrete);
    return discrete >= 0 ? discrete : mainIndex();
}

const QList<Gpu> &Resolver::gpus() const
{
    return m_gpus;
}

int Resolver::indexOfId(const QString &id) const
{
    for (int i = 0; i < m_gpus.size(); ++i) {
        if (m_gpus.at(i).id == id) {
            return i;
        }
    }
    return -1;
}

int Resolver::automaticMainIndex() const
{
    int best = -1;
    for (int i = 0; i < m_gpus.size(); ++i) {
        const Gpu &gpu = m_gpus.at(i);
        if (!gpu.canRender) {
            continue;
        }
        if (best < 0) {
            best = i;
            continue;
        }
        // KWin's own order: the GPU with the laptop panel, then the one with most screens; the boot VGA breaks a tie
        const Gpu &current = m_gpus.at(best);
        if (gpu.hasInternalScreen() != current.hasInternalScreen()) {
            if (gpu.hasInternalScreen()) {
                best = i;
            }
        } else if (gpu.connectedCount() != current.connectedCount()) {
            if (gpu.connectedCount() > current.connectedCount()) {
                best = i;
            }
        } else if (gpu.bootVga && !current.bootVga) {
            best = i;
        }
    }
    if (best < 0 && !m_gpus.isEmpty()) {
        return 0;
    }
    return best;
}

int Resolver::mainIndex() const
{
    const int saved = indexOfId(m_savedMain);
    if (saved >= 0 && m_gpus.at(saved).canRender) {
        return saved;
    }
    return automaticMainIndex();
}

Resolution Resolver::mainProblem() const
{
    Resolution resolution;
    resolution.reason = u"choice"_s;
    if (m_savedMain.isEmpty()) {
        return resolution;
    }
    const int saved = indexOfId(m_savedMain);
    if (saved < 0) {
        return cannotUse(u"gpu-missing"_s, m_savedMain);
    }
    // KWin opens the card through the session (logind), so the render node's permissions do not matter here; drawing does
    if (!m_gpus.at(saved).canRender) {
        return cannotUse(u"gpu-cannot-render"_s, m_savedMain, saved);
    }
    resolution.gpuIndex = saved;
    return resolution;
}

QList<int> Resolver::usableIndices() const
{
    QList<int> list;
    for (int i = 0; i < m_gpus.size(); ++i) {
        if (m_gpus.at(i).usable()) {
            list << i;
        }
    }
    return list;
}

int Resolver::defaultIndex() const
{
    // switcheroo-control marks the boot VGA as the Default GPU, and the only GPU when there is one
    for (int i = 0; i < m_gpus.size(); ++i) {
        if (m_gpus.at(i).bootVga) {
            return i;
        }
    }
    return mainIndex();
}

int Resolver::firstOfKind(GpuKind kind) const
{
    for (int i = 0; i < m_gpus.size(); ++i) {
        if (m_gpus.at(i).usable() && m_gpus.at(i).kind == kind) {
            return i;
        }
    }
    return -1;
}

QString Resolver::automaticTarget(Category category, PowerProfile profile, bool stereo)
{
    // Daniel, 2026-10-24, split by kind: players, games and any program while it presents 3D draw on the GPU
    // measured best on the machine whatever the power profile, battery included; browsers follow the power
    // profile; other programs stay on the GPU that draws the desktop. The person's choice wins over it
    if (category == Category::Players || category == Category::Games || stereo) {
        return u"measured"_s;
    }
    if (category == Category::Browsers) {
        return profileTarget(profile);
    }
    return u"main"_s;
}

QString Resolver::profileTarget(PowerProfile profile)
{
    switch (profile) {
    case PowerProfile::PowerSaver:
        return u"integrated"_s;
    case PowerProfile::Performance:
        return u"discrete"_s;
    case PowerProfile::Balanced:
        break;
    }
    // the GPU that draws the desktop: no hand-over between GPUs
    return u"main"_s;
}

Resolution Resolver::make(int index, const QString &reason) const
{
    Resolution resolution;
    resolution.gpuIndex = index;
    resolution.reason = reason;
    resolution.isMain = index == mainIndex();
    if (index >= 0 && !resolution.isMain) {
        resolution.environment = environmentFor(m_gpus.at(index));
        // glvnd tries NVIDIA's EGL and GLX first, and they draw on the GPU the desktop uses; a program sent from an
        // NVIDIA desktop to a Mesa GPU names Mesa's (libglvnd: __EGL_VENDOR_LIBRARY_FILENAMES loads only the vendor files
        // it lists, __GLX_VENDOR_LIBRARY_NAME picks the GLX vendor)
        const auto nvidiaDriver = [](const Gpu &gpu) {
            return gpu.vendorId == 0x10de && gpu.driver != u"nouveau"_s;
        };
        const int main = mainIndex();
        if (main >= 0 && nvidiaDriver(m_gpus.at(main)) && !nvidiaDriver(m_gpus.at(index))) {
            resolution.environment << u"__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json"_s << u"__GLX_VENDOR_LIBRARY_NAME=mesa"_s;
        }
    }
    return resolution;
}

Resolution Resolver::cannotUse(const QString &problem, const QString &requested, int requestedIndex) const
{
    Resolution resolution;
    resolution.missing = true;
    resolution.problem = problem;
    resolution.requested = requested;
    resolution.requestedIndex = requestedIndex;
    resolution.reason = u"choice"_s;
    resolution.isMain = false;
    return resolution;
}

Resolution Resolver::resolveGpu(const QString &choice) const
{
    if (choice == u"integrated"_s || choice == u"discrete"_s) {
        const GpuKind kind = choice == u"integrated"_s ? GpuKind::Integrated : GpuKind::Discrete;
        const int index = firstOfKind(kind);
        if (index >= 0) {
            return make(index, u"choice"_s);
        }
        // a GPU of that kind that is here but cannot be used says why; none at all is said too
        for (int i = 0; i < m_gpus.size(); ++i) {
            const Gpu &gpu = m_gpus.at(i);
            if (gpu.canRender && gpu.kind == kind) {
                return cannotUse(u"gpu-not-allowed"_s, choice, i);
            }
        }
        return cannotUse(u"kind-missing"_s, choice);
    }
    const int index = indexOfId(choice);
    if (index < 0) {
        return cannotUse(u"gpu-missing"_s, choice);
    }
    if (!m_gpus.at(index).canRender) {
        return cannotUse(u"gpu-cannot-render"_s, choice, index);
    }
    if (!m_gpus.at(index).accessible) {
        return cannotUse(u"gpu-not-allowed"_s, choice, index);
    }
    return make(index, u"choice"_s);
}

Resolution Resolver::resolveChoice(const QString &choice, Category category, bool stereo) const
{
    // The person's own GPU, by its id or its kind, is kept or said to be unusable, also when one GPU or none is left: another
    // GPU is only ever an explicit choice of theirs (Daniel, 2026-11-01)
    if (choice != u"auto"_s && choice != u"profile"_s) {
        return resolveGpu(choice);
    }
    const int main = mainIndex();
    if (main < 0) {
        return {}; // no GPU: nothing to choose
    }
    int renderers = 0;
    for (const Gpu &gpu : m_gpus) {
        renderers += gpu.usable() ? 1 : 0;
    }
    if (renderers <= 1) {
        return make(main, u"only-gpu"_s);
    }

    // Automatic and Follow the power profile are rules: each says where it puts a kind of program, and the page shows it
    const bool measured = choice == u"auto"_s && (category == Category::Players || category == Category::Games || stereo);
    if (measured) {
        // the machine's record naming a GPU that is not here is said, not taken for "not measured"
        return make(presentingIndex(), measuredIndex() >= 0 ? u"measured"_s : (measuredNamesAbsentGpu() ? u"measured-missing"_s : u"unmeasured"_s));
    }
    if (choice == u"auto"_s && category == Category::Other) {
        return make(main, u"desktop"_s);
    }
    // Browsers on Automatic, and every kind set to follow the power profile, need the profile: without it there is no answer
    if (!m_profile.profile) {
        return cannotUse(u"profile-unreadable"_s, choice);
    }
    const PowerProfile profile = *m_profile.profile;
    const QString wanted = profileTarget(profile);
    const QString reason = u"profile:"_s + powerProfileToString(profile);
    int index = main;
    QString absent;
    if (wanted == u"integrated"_s || wanted == u"discrete"_s) {
        index = firstOfKind(wanted == u"integrated"_s ? GpuKind::Integrated : GpuKind::Discrete);
        if (index < 0) {
            // the rule's own answer when this computer has no usable GPU of that kind: the GPU that draws the desktop
            index = main;
            absent = wanted;
        }
    }
    Resolution resolution = make(index, reason);
    resolution.kindAbsent = absent;
    return resolution;
}

Resolution Resolver::resolveCategory(Category category, const GraphicsSettings &settings, bool stereo) const
{
    return resolveChoice(settings.renderChoice(category), category, stereo);
}

Resolution Resolver::resolveApp(const AppEntry &entry, const GraphicsSettings &settings, bool stereo) const
{
    const int main = mainIndex();
    switch (entry.preference) {
    case AppPreference::MainGpu:
        return make(main, u"app"_s);
    case AppPreference::OtherGpu: {
        if (main < 0) {
            return {};
        }
        // KDE's meaning of the key, as KIO's launcher applies it (gpudetection.cpp): the Desktop Entry Specification's
        // PrefersNonDefaultGPU "prefers to be run on a more powerful discrete GPU if available", so the first discrete
        // GPU; nothing to do when the default GPU (switcheroo-control's Default, the boot VGA) is discrete; with no
        // discrete GPU, the first GPU other than the default
        const int defaultGpu = defaultIndex();
        if (m_gpus.at(defaultGpu).kind == GpuKind::Discrete) {
            return make(main, u"app"_s);
        }
        int index = firstOfKind(GpuKind::Discrete);
        for (int i = 0; i < m_gpus.size() && index < 0; ++i) {
            if (i != defaultGpu && m_gpus.at(i).usable()) {
                index = i;
            }
        }
        return index < 0 ? make(main, u"only-gpu"_s) : make(index, u"app"_s);
    }
    case AppPreference::Unset:
        break;
    }
    return resolveCategory(entry.category, settings, stereo);
}

QString Resolver::kwinDrmDevices() const
{
    const int main = indexOfId(m_savedMain);
    if (main < 0 || !m_gpus.at(main).canRender) {
        return {};
    }
    QStringList devices = {m_gpus.at(main).cardNode};
    for (int i = 0; i < m_gpus.size(); ++i) {
        if (i != main && m_gpus.at(i).canRender) {
            devices << m_gpus.at(i).cardNode;
        }
    }
    for (int i = 0; i < m_gpus.size(); ++i) {
        if (!m_gpus.at(i).canRender) {
            devices << m_gpus.at(i).cardNode;
        }
    }
    return devices.join(u':');
}

QStringList Resolver::environmentFor(const Gpu &gpu)
{
    // The sets switcheroo-control prints for these drivers (switcherooctl list, checked on the workstation)
    if (gpu.vendorId == 0x10de && gpu.driver != u"nouveau"_s) {
        return {u"__GLX_VENDOR_LIBRARY_NAME=nvidia"_s, u"__NV_PRIME_RENDER_OFFLOAD=1"_s, u"__VK_LAYER_NV_optimus=NVIDIA_only"_s, u"VK_LOADER_DRIVERS_SELECT=*nvidia*"_s};
    }
    QStringList environment = {u"DRI_PRIME="_s + gpu.mesaId()};
    if (gpu.driver == u"amdgpu"_s || gpu.driver == u"radeon"_s) {
        environment << u"VK_LOADER_DRIVERS_SELECT=*radeon*"_s;
    } else if (gpu.driver == u"i915"_s || gpu.driver == u"xe"_s) {
        environment << u"VK_LOADER_DRIVERS_SELECT=*intel*"_s;
    } else if (gpu.driver == u"nouveau"_s) {
        environment << u"VK_LOADER_DRIVERS_SELECT=*nouveau*"_s;
    }
    return environment;
}

}
