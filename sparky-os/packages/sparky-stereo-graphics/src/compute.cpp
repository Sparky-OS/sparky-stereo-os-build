// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "compute.h"

#include <QDir>
#include <QFile>
#include <QRegularExpression>

#include <algorithm>

using namespace Qt::StringLiterals;

namespace SparkyGraphics
{

static bool nvidiaDriver(const Gpu &gpu)
{
    return gpu.vendorId == 0x10de && gpu.driver == u"nvidia"_s;
}

// The UUID NVIDIA's driver gives the card ("GPU UUID: GPU-..." in its own file), the form CUDA_VISIBLE_DEVICES takes
static QString nvidiaUuid(const Gpu &gpu, const QString &root)
{
    QFile file(root + u"/proc/driver/nvidia/gpus/"_s + gpu.pciSlot + u"/information"_s);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    static const QRegularExpression pattern(QStringLiteral(R"(^GPU UUID:\s*(GPU-[0-9a-fA-F-]+)\s*$)"), QRegularExpression::MultilineOption);
    const QRegularExpressionMatch match = pattern.match(QString::fromUtf8(file.readAll()));
    return match.hasMatch() ? match.captured(1) : QString();
}

// The card's place among the KFD's graphics nodes (ROCm's order), matched by the minor of its render node; -1 when the
// KFD lists no node for it
static int kfdIndex(const Gpu &gpu, const QString &root)
{
    if (gpu.driver != u"amdgpu"_s || !gpu.renderNode.startsWith(u"/dev/dri/renderD"_s)) {
        return -1;
    }
    const QString minor = gpu.renderNode.mid(16);
    const QString nodes = root + u"/sys/class/kfd/kfd/topology/nodes"_s;
    QStringList names = QDir(nodes).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    names.removeIf([](const QString &name) {
        bool number = false;
        name.toInt(&number);
        return !number;
    });
    std::sort(names.begin(), names.end(), [](const QString &a, const QString &b) {
        return a.toInt() < b.toInt();
    });
    int index = 0;
    for (const QString &name : std::as_const(names)) {
        QFile id(nodes + u'/' + name + u"/gpu_id"_s);
        if (!id.open(QIODevice::ReadOnly) || id.readAll().trimmed().toULongLong() == 0) {
            continue; // the processor's node
        }
        QFile properties(nodes + u'/' + name + u"/properties"_s);
        if (properties.open(QIODevice::ReadOnly)) {
            for (const QByteArray &line : properties.readAll().split('\n')) {
                if (line.startsWith("drm_render_minor ") && QString::fromLatin1(line.mid(17)).trimmed() == minor) {
                    return index;
                }
            }
        }
        ++index;
    }
    return -1;
}

static QString loaderFilter(const Gpu &gpu)
{
    if (nvidiaDriver(gpu)) {
        return u"*nvidia*"_s;
    }
    if (gpu.driver == u"amdgpu"_s || gpu.driver == u"radeon"_s) {
        return u"*radeon*"_s;
    }
    if (gpu.driver == u"i915"_s || gpu.driver == u"xe"_s) {
        return u"*intel*"_s;
    }
    if (gpu.driver == u"nouveau"_s) {
        return u"*nouveau*"_s;
    }
    return {};
}

QStringList Compute::vulkanDrivers(const QString &driver, const QString &root)
{
    // the driver files of Mesa's radv (amdgpu only: the older radeon kernel driver has no Vulkan), anv and hasvk, nvk,
    // and NVIDIA's own
    QStringList patterns;
    if (driver == u"amdgpu"_s) {
        patterns = {u"radeon_icd*.json"_s};
    } else if (driver == u"i915"_s) {
        patterns = {u"intel_icd*.json"_s, u"intel_hasvk_icd*.json"_s};
    } else if (driver == u"xe"_s) {
        patterns = {u"intel_icd*.json"_s};
    } else if (driver == u"nouveau"_s) {
        patterns = {u"nouveau_icd*.json"_s};
    } else if (driver == u"nvidia"_s) {
        patterns = {u"nvidia_icd*.json"_s};
    }
    QStringList found;
    if (patterns.isEmpty()) {
        return found;
    }
    for (const QString &dir : {u"/usr/share/vulkan/icd.d"_s, u"/etc/vulkan/icd.d"_s}) {
        for (const QString &name : QDir(root + dir).entryList(patterns, QDir::Files, QDir::Name)) {
            found << dir + u'/' + name;
        }
    }
    return found;
}

static bool cudaDriver(const QString &root)
{
    for (const QString &dir : {u"/usr/lib/x86_64-linux-gnu"_s, u"/usr/lib/x86_64-linux-gnu/nvidia/current"_s, u"/usr/lib64"_s}) {
        if (QFile::exists(root + dir + u"/libcuda.so.1"_s)) {
            return true;
        }
    }
    return false;
}

ComputeAnswer Compute::forGpu(const QList<Gpu> &gpus, int index, const QString &root)
{
    ComputeAnswer answer;
    if (index < 0 || index >= gpus.size()) {
        return processor();
    }
    const Gpu &gpu = gpus.at(index);
    const bool cuda = nvidiaDriver(gpu) && cudaDriver(root);
    const int kfd = kfdIndex(gpu, root);
    const bool vulkan = !vulkanDrivers(gpu.driver, root).isEmpty();
    if (!cuda && kfd < 0 && !vulkan) {
        answer.problem = u"card-no-compute"_s;
        answer.detail = gpu.driver;
        return answer;
    }
    QString cudaDevice = u"-1"_s;
    if (nvidiaDriver(gpu)) {
        cudaDevice = nvidiaUuid(gpu, root);
        if (cudaDevice.isEmpty()) {
            QStringList addresses;
            for (const Gpu &other : gpus) {
                if (nvidiaDriver(other)) {
                    addresses << other.pciSlot;
                }
            }
            addresses.sort();
            cudaDevice = QString::number(addresses.indexOf(gpu.pciSlot));
        }
    }
    answer.environment << u"CUDA_DEVICE_ORDER=PCI_BUS_ID"_s << u"CUDA_VISIBLE_DEVICES="_s + cudaDevice;
    if (kfd >= 0) {
        answer.environment << u"ROCR_VISIBLE_DEVICES="_s + QString::number(kfd) << u"HIP_VISIBLE_DEVICES=0"_s;
    } else {
        answer.environment << u"HIP_VISIBLE_DEVICES=-1"_s;
    }
    const QString filter = loaderFilter(gpu);
    if (!filter.isEmpty()) {
        answer.environment << u"VK_LOADER_DRIVERS_SELECT="_s + filter;
    }
    answer.environment << u"DRI_PRIME="_s + gpu.mesaId() + u'!';
    return answer;
}

ComputeAnswer Compute::processor()
{
    ComputeAnswer answer;
    answer.environment = {u"CUDA_VISIBLE_DEVICES=-1"_s, u"HIP_VISIBLE_DEVICES=-1"_s, u"GGML_VK_VISIBLE_DEVICES="_s};
    return answer;
}

}
