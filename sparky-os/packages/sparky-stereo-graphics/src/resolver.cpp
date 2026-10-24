// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "resolver.h"

using namespace Qt::StringLiterals;

namespace SparkyGraphics
{

PowerProfile powerProfileFromString(const QString &name, PowerProfile fallback)
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
    return fallback;
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

Resolver::Resolver(const QList<Gpu> &gpus, const QString &savedMainGpu, PowerProfile profile, const QString &measuredBest)
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
    // Daniel, 2026-10-24: players, and any program while it presents 3D, draw on the GPU measured best on the
    // machine whatever the power profile, battery included; the person's choice wins over it
    if (category == Category::Players || stereo) {
        return u"measured"_s;
    }
    switch (profile) {
    case PowerProfile::PowerSaver:
        return u"integrated"_s;
    case PowerProfile::Performance:
        return u"discrete"_s;
    case PowerProfile::Balanced:
        break;
    }
    // the GPU that draws the desktop: no hand-over between GPUs for games, browsers and other programs
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
    }
    return resolution;
}

Resolution Resolver::resolveChoice(const QString &choice, Category category, bool stereo) const
{
    const int main = mainIndex();
    if (main < 0) {
        return {};
    }
    int renderers = 0;
    for (const Gpu &gpu : m_gpus) {
        renderers += gpu.usable() ? 1 : 0;
    }
    if (renderers <= 1) {
        return make(main, u"only-gpu"_s);
    }

    int index = -1;
    QString reason = u"choice"_s;
    bool missing = false;
    if (choice == u"auto"_s || choice == u"profile"_s) {
        const QString target = choice == u"profile"_s ? automaticTarget(Category::Other, m_profile) : automaticTarget(category, m_profile, stereo);
        reason = u"profile:"_s + powerProfileToString(m_profile);
        if (target == u"measured"_s) {
            index = presentingIndex();
            reason = measuredIndex() >= 0 ? u"measured"_s : u"unmeasured"_s;
        } else if (target == u"integrated"_s) {
            index = firstOfKind(GpuKind::Integrated);
        } else if (target == u"discrete"_s) {
            index = firstOfKind(GpuKind::Discrete);
        } else {
            index = main;
        }
    } else if (choice == u"integrated"_s) {
        index = firstOfKind(GpuKind::Integrated);
    } else if (choice == u"discrete"_s) {
        index = firstOfKind(GpuKind::Discrete);
    } else {
        index = indexOfId(choice);
        if (index < 0 || !m_gpus.at(index).usable()) {
            index = -1;
            missing = true;
        }
    }
    if (index < 0) {
        index = main; // nothing of that kind here
    }
    Resolution resolution = make(index, reason);
    resolution.missing = missing;
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
        // KDE's key is relative to the default GPU: the first GPU of the opposite kind, else any other
        const GpuKind opposite = m_gpus.at(main).kind == GpuKind::Integrated ? GpuKind::Discrete : GpuKind::Integrated;
        int index = -1;
        for (int i = 0; i < m_gpus.size() && index < 0; ++i) {
            if (i != main && m_gpus.at(i).usable() && m_gpus.at(i).kind == opposite) {
                index = i;
            }
        }
        for (int i = 0; i < m_gpus.size() && index < 0; ++i) {
            if (i != main && m_gpus.at(i).usable()) {
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
