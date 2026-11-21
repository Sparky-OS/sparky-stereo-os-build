// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QList>
#include <QString>

namespace SparkyGraphics
{

enum class GpuKind {
    Integrated,
    Discrete,
};

struct Connector {
    QString name; // "DP-1", "HDMI-A-2"
    bool connected = false;
    QString monitor; // the model name in the EDID, empty when none
};

struct Gpu {
    QString id; // "pci-0000:0b:00.0", the same after a reboot
    QString pciSlot; // "0000:0b:00.0"
    quint16 vendorId = 0;
    quint16 deviceId = 0;
    QString vendor; // "AMD"
    QString chip; // "Cezanne"
    QString name; // "AMD Radeon Vega Series / Radeon Vega Mobile Series"
    QString driver; // "amdgpu"
    QString cardNode; // "/dev/dri/card0"
    QString renderNode; // "/dev/dri/renderD128", empty when the chip cannot render
    bool bootVga = false;
    bool canRender = false;
    bool accessible = true; // the person's account may open the render node
    GpuKind kind = GpuKind::Discrete;
    QList<Connector> connectors;
    // The card's own memory in bytes, 0 when it is not known (ORDER 70: the Partners page proposes a model by it). amdgpu
    // gives it in sysfs (mem_info_vram_total; for an integrated card the part of the computer's memory set aside for it);
    // NVIDIA's driver only through NVML, which readMemory() asks
    quint64 memory = 0;

    bool hasScreens() const;
    int connectedCount() const;
    // Can draw and the account may use it: what programs can be sent to
    bool usable() const;
    bool hasInternalScreen() const;
    // Mesa's spelling of the PCI address for DRI_PRIME, "pci-0000_0b_00_0"
    QString mesaId() const;
};

class GpuInventory
{
public:
    // Reads root/sys/class/drm and root/usr/share/hwdata/pci.ids, cards in card number order.
    static QList<Gpu> read(const QString &root = QStringLiteral("/"));
    // Fills the memory sysfs does not give: NVIDIA's cards through NVML (libnvidia-ml.so.1, the driver's own library),
    // on the running system only (root "/"). Kept apart from read(), which every program start goes through
    static void readMemory(QList<Gpu> &gpus, const QString &root = QStringLiteral("/"));

    static bool isIntegratedFamily(quint16 vendorId, const QString &chip, const QString &name);
    static QString edidMonitorName(const QByteArray &edid);
};

}
