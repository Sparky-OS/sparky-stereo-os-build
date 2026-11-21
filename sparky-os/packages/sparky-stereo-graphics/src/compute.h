// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "gpuinventory.h"

#include <QString>
#include <QStringList>

namespace SparkyGraphics
{

// ORDER 70: the card the edition's partners (local AI engines: Ollama, llama.cpp, whisper.cpp) compute on, as the
// variables their runners read, so only the chosen card is visible to every runner and nothing else is put in its place.
// Measured with Ollama 0.40.16 on an RTX 3060 and a Renoir APU with every runner installed (CUDA, ROCm, Vulkan):
// NVIDIA chosen gives CUDA on the RTX 3060 only, the APU chosen gives Vulkan on the APU only, the processor chosen gives
// the processor only.
struct ComputeAnswer {
    // The card can be reached by a compute driver: problem is empty. Otherwise "card-no-compute", with detail the card's
    // kernel driver
    QString problem;
    QString detail;
    // KEY=VALUE lines; for the processor, the values that hide every card
    QStringList environment;
};

namespace Compute
{
// The variables for one card of the inventory:
// - CUDA (NVIDIA's driver): CUDA_DEVICE_ORDER=PCI_BUS_ID and CUDA_VISIBLE_DEVICES set to the card's UUID from the driver's
//   own file (root/proc/driver/nvidia/gpus/SLOT/information), or its place among NVIDIA's cards in PCI order; -1 for any
//   other card ("If one of the indices is invalid, only the devices whose index precedes the invalid index are visible",
//   CUDA C++ Programming Guide 13.0, CUDA Environment Variables);
// - ROCm (amdgpu with a KFD node, root/sys/class/kfd/kfd/topology/nodes): ROCR_VISIBLE_DEVICES set to the card's place
//   among the KFD's graphics nodes, matched by its render node's minor, and HIP_VISIBLE_DEVICES=0; HIP_VISIBLE_DEVICES=-1
//   for any other card, since HIP otherwise reads CUDA_VISIBLE_DEVICES;
// - Vulkan: the loader's driver filter for the card's driver (VK_LOADER_DRIVERS_SELECT, as the Graphics page sends a
//   program) and Mesa's device selection with only that card exposed (DRI_PRIME=pci-DOMAIN_BUS_DEV_FN!, Mesa's
//   environment variables page: "For Vulkan it's possible to append !, in which case only the selected GPU will be
//   exposed to the application").
// A card no compute driver reaches (no Vulkan driver installed for its kernel driver, no CUDA, no KFD node) has
// problem "card-no-compute".
ComputeAnswer forGpu(const QList<Gpu> &gpus, int index, const QString &root = QStringLiteral("/"));
// The processor only: CUDA_VISIBLE_DEVICES=-1, HIP_VISIBLE_DEVICES=-1, GGML_VK_VISIBLE_DEVICES= (ggml's Vulkan back end
// lists none)
ComputeAnswer processor();
// The Vulkan driver files the loader would find for a kernel driver (root/usr/share/vulkan/icd.d, root/etc/vulkan/icd.d)
QStringList vulkanDrivers(const QString &driver, const QString &root = QStringLiteral("/"));
}

}
