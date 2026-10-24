// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QByteArray>
#include <QDir>
#include <QFile>
#include <QList>
#include <QString>
#include <QTemporaryDir>
#include <QTest>

using namespace Qt::StringLiterals;

// A sysfs tree like the kernel's, for the machines the page has to understand.
struct FixtureConnector {
    QString name; // "DP-1"
    bool connected = false;
    QString monitor; // put into a base EDID block when not empty
};

struct FixtureGpu {
    int card = 0;
    QString slot; // "0000:0b:00.0"
    QString parent; // the bridge above it, "0000:00:08.1", empty when on the root complex
    quint16 vendor = 0;
    quint16 device = 0;
    QString driver;
    bool bootVga = false;
    bool render = true;
    QList<FixtureConnector> connectors;
    bool accessible = true; // the account may open the render node
};

inline QByteArray fixtureEdid(const QString &monitor)
{
    QByteArray edid(128, '\0');
    const char header[] = {0x00, char(0xff), char(0xff), char(0xff), char(0xff), char(0xff), char(0xff), 0x00};
    edid.replace(0, 8, QByteArray(header, 8));
    // an unrelated descriptor first, then the monitor name descriptor (tag 0xFC)
    const char serial[] = {0x00, 0x00, 0x00, char(0xff), 0x00};
    edid.replace(54, 5, QByteArray(serial, 5));
    edid.replace(59, 13, QByteArray("ABC123\n      ", 13));
    const char name[] = {0x00, 0x00, 0x00, char(0xfc), 0x00};
    edid.replace(72, 5, QByteArray(name, 5));
    QByteArray text = monitor.toLatin1().left(13);
    if (text.size() < 13) {
        text += "\n";
    }
    text = text.leftJustified(13, ' ');
    edid.replace(77, 13, text);
    return edid;
}

class SysfsFixture
{
public:
    SysfsFixture()
    {
        Q_ASSERT(m_dir.isValid());
        write(QStringLiteral("usr/share/hwdata/pci.ids"), pciIds());
    }

    QString root() const
    {
        return m_dir.path();
    }

    void add(const FixtureGpu &gpu)
    {
        const QString parent = gpu.parent.isEmpty() ? QString() : gpu.parent + QLatin1Char('/');
        const QString device = QStringLiteral("sys/devices/pci0000:00/") + parent + gpu.slot;
        const QString card = QStringLiteral("card%1").arg(gpu.card);
        write(device + QStringLiteral("/vendor"), QByteArray("0x%1\n").replace("%1", QByteArray::number(gpu.vendor, 16).rightJustified(4, '0')));
        write(device + QStringLiteral("/device"), QByteArray("0x%1\n").replace("%1", QByteArray::number(gpu.device, 16).rightJustified(4, '0')));
        write(device + QStringLiteral("/class"), "0x030000\n");
        write(device + QStringLiteral("/boot_vga"), gpu.bootVga ? "1\n" : "0\n");
        QDir().mkpath(m_dir.filePath(device + QStringLiteral("/drm/") + card));
        if (gpu.render) {
            QDir().mkpath(m_dir.filePath(device + QStringLiteral("/drm/renderD%1").arg(128 + gpu.card)));
            // the node itself, so the account's access can be tested
            const QString node = QStringLiteral("dev/dri/renderD%1").arg(128 + gpu.card);
            write(node, "");
            QFile::setPermissions(m_dir.filePath(node), gpu.accessible ? QFileDevice::Permissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner) : QFileDevice::Permissions());
        }
        QDir().mkpath(m_dir.filePath(QStringLiteral("sys/bus/pci/drivers/") + gpu.driver));
        QFile::link(QStringLiteral("../../../../bus/pci/drivers/") + gpu.driver, m_dir.filePath(device + QStringLiteral("/driver")));
        // the PCI bus lists every device, with or without a driver, as the kernel does
        QDir().mkpath(m_dir.filePath(QStringLiteral("sys/bus/pci/devices")));
        QFile::link(m_dir.filePath(device), m_dir.filePath(QStringLiteral("sys/bus/pci/devices/") + gpu.slot));
        const QString cls = QStringLiteral("sys/class/drm/") + card;
        QDir().mkpath(m_dir.filePath(cls));
        QFile::link(m_dir.filePath(device), m_dir.filePath(cls + QStringLiteral("/device")));
        for (const FixtureConnector &c : gpu.connectors) {
            const QString dir = QStringLiteral("sys/class/drm/%1-%2").arg(card, c.name);
            write(dir + QStringLiteral("/status"), c.connected ? "connected\n" : "disconnected\n");
            if (!c.monitor.isEmpty()) {
                write(dir + QStringLiteral("/edid"), fixtureEdid(c.monitor));
            } else {
                write(dir + QStringLiteral("/edid"), "");
            }
        }
    }

    // The firmware's model strings, as the kernel shows them in /sys/class/dmi/id
    void setDmi(const QByteArray &vendor, const QByteArray &product)
    {
        write(QStringLiteral("sys/class/dmi/id/sys_vendor"), vendor + '\n');
        write(QStringLiteral("sys/class/dmi/id/product_name"), product + '\n');
    }

    void write(const QString &relative, const QByteArray &data)
    {
        const QString path = m_dir.filePath(relative);
        QDir().mkpath(QFileInfo(path).path());
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(data);
    }

    static QByteArray pciIds()
    {
        return "1002  Advanced Micro Devices, Inc. [AMD/ATI]\n"
               "\t1638  Cezanne [Radeon Vega Series / Radeon Vega Mobile Series]\n"
               "\t6660  Sun XT [Radeon HD 8670A/8670M/8690M / R5 M330 / M430 / Radeon 520 Mobile]\n"
               "\t7340  Navi 14 [Radeon RX 5500/5500M / Pro 5500M]\n"
               "\t9874  Wani [Radeon R5/R6/R7 Graphics]\n"
               "10de  NVIDIA Corporation\n"
               "\t2504  GA106 [GeForce RTX 3060 Lite Hash Rate]\n"
               "1a03  ASPEED Technology, Inc.\n"
               "\t2000  ASPEED Graphics Family\n"
               "8086  Intel Corporation\n"
               "\t46a6  Alder Lake-P GT2 [Iris Xe Graphics]\n"
               "\t56a0  DG2 [Arc A770]\n";
    }

    // One Intel iGPU on a laptop panel
    static FixtureGpu intel()
    {
        return {0, QStringLiteral("0000:00:02.0"), {}, 0x8086, 0x46a6, QStringLiteral("i915"), true, true,
                {{QStringLiteral("eDP-1"), true, QStringLiteral("LP156WFC")}, {QStringLiteral("HDMI-A-1"), false, {}}}};
    }
    // Daniel's field laptop: the iGPU drives every connector, the discrete R5 M430 has none
    static QList<FixtureGpu> a10()
    {
        return {{0, QStringLiteral("0000:00:01.0"), {}, 0x1002, 0x9874, QStringLiteral("amdgpu"), true, true,
                 {{QStringLiteral("eDP-1"), true, {}}, {QStringLiteral("HDMI-A-1"), true, QStringLiteral("SONY TV")}}},
                {1, QStringLiteral("0000:03:00.0"), QStringLiteral("0000:00:03.0"), 0x1002, 0x6660, QStringLiteral("amdgpu"), false, true, {}}};
    }
    // The workstation: Renoir-class APU and the RTX 3060, screens on both
    static QList<FixtureGpu> host()
    {
        return {{0, QStringLiteral("0000:0b:00.0"), QStringLiteral("0000:00:08.1"), 0x1002, 0x1638, QStringLiteral("amdgpu"), true, true,
                 {{QStringLiteral("DP-1"), true, QStringLiteral("DELL U2720Q")}, {QStringLiteral("HDMI-A-1"), true, QStringLiteral("SONY TV")}}},
                {1, QStringLiteral("0000:01:00.0"), QStringLiteral("0000:00:01.1"), 0x10de, 0x2504, QStringLiteral("nvidia"), false, true,
                 {{QStringLiteral("DP-2"), false, {}}, {QStringLiteral("DP-3"), false, {}}, {QStringLiteral("DP-4"), false, {}}, {QStringLiteral("HDMI-A-2"), true, QStringLiteral("LG TV")}}}};
    }
    // A server board: the BMC's chip is the boot VGA and cannot render
    static QList<FixtureGpu> bmc()
    {
        return {{0, QStringLiteral("0000:04:00.0"), QStringLiteral("0000:00:1c.0"), 0x1a03, 0x2000, QStringLiteral("ast"), true, false,
                 {{QStringLiteral("VGA-1"), true, {}}}},
                {1, QStringLiteral("0000:65:00.0"), QStringLiteral("0000:00:03.1"), 0x10de, 0x2504, QStringLiteral("nvidia"), false, true,
                 {{QStringLiteral("DP-1"), true, QStringLiteral("DELL U2720Q")}}}};
    }
    // A third card appears when installed
    static QList<FixtureGpu> three()
    {
        return {intel(),
                {1, QStringLiteral("0000:01:00.0"), QStringLiteral("0000:00:01.0"), 0x10de, 0x2504, QStringLiteral("nvidia"), false, true,
                 {{QStringLiteral("DP-2"), true, QStringLiteral("DELL U2720Q")}}},
                {2, QStringLiteral("0000:02:00.0"), QStringLiteral("0000:00:01.1"), 0x1002, 0x7340, QStringLiteral("amdgpu"), false, true,
                 {{QStringLiteral("DP-3"), false, {}}}}};
    }

private:
    QTemporaryDir m_dir;
};
