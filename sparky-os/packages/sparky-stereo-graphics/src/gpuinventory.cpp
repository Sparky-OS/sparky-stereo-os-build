// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "gpuinventory.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>

#include <unistd.h>

using namespace Qt::StringLiterals;

namespace SparkyGraphics
{

bool Gpu::hasScreens() const
{
    return connectedCount() > 0;
}

int Gpu::connectedCount() const
{
    int count = 0;
    for (const Connector &connector : connectors) {
        count += connector.connected ? 1 : 0;
    }
    return count;
}

bool Gpu::hasInternalScreen() const
{
    for (const Connector &connector : connectors) {
        if (connector.connected
            && (connector.name.startsWith(u"eDP"_s, Qt::CaseInsensitive) || connector.name.startsWith(u"LVDS"_s, Qt::CaseInsensitive)
                || connector.name.startsWith(u"DSI"_s, Qt::CaseInsensitive))) {
            return true;
        }
    }
    return false;
}

bool Gpu::usable() const
{
    return canRender && accessible;
}

QString Gpu::mesaId() const
{
    QString id = u"pci-"_s + pciSlot;
    id.replace(u':', u'_').replace(u'.', u'_');
    return id;
}

static QString readFirstLine(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    return QString::fromUtf8(file.readLine()).trimmed();
}

static quint16 readHex(const QString &path)
{
    return readFirstLine(path).toUShort(nullptr, 16);
}

struct PciNames {
    QString vendor;
    QString device;
};

// root/usr/share/hwdata/pci.ids: "vvvv  Vendor" then "\tdddd  Device" lines
static PciNames lookupPci(const QString &root, quint16 vendorId, quint16 deviceId)
{
    PciNames names;
    QFile file(root + u"/usr/share/hwdata/pci.ids"_s);
    if (!file.open(QIODevice::ReadOnly)) {
        file.setFileName(root + u"/usr/share/misc/pci.ids"_s);
        if (!file.open(QIODevice::ReadOnly)) {
            return names;
        }
    }
    const QByteArray vendorPrefix = QByteArray::number(vendorId, 16).rightJustified(4, '0') + "  ";
    const QByteArray devicePrefix = "\t" + QByteArray::number(deviceId, 16).rightJustified(4, '0') + "  ";
    bool inVendor = false;
    while (!file.atEnd()) {
        const QByteArray line = file.readLine();
        if (line.startsWith('#') || line.trimmed().isEmpty()) {
            continue;
        }
        if (!line.startsWith('\t')) {
            if (inVendor) {
                break;
            }
            if (line.startsWith(vendorPrefix)) {
                inVendor = true;
                names.vendor = QString::fromUtf8(line.mid(vendorPrefix.size())).trimmed();
            }
        } else if (inVendor && line.startsWith(devicePrefix)) {
            names.device = QString::fromUtf8(line.mid(devicePrefix.size())).trimmed();
            break;
        }
    }
    return names;
}

static QString shortVendor(quint16 vendorId, const QString &pciName)
{
    switch (vendorId) {
    case 0x1002:
        return u"AMD"_s;
    case 0x10de:
        return u"NVIDIA"_s;
    case 0x8086:
        return u"Intel"_s;
    }
    QString name = pciName;
    static const QRegularExpression tail(QStringLiteral(R"([,\s]+(Corporation|Corp\.?|Inc\.?|Technology|Ltd\.?|Co\.?|Limited|Electronics|Semiconductor)\s*$)"), QRegularExpression::CaseInsensitiveOption);
    for (int i = 0; i < 4; ++i) {
        name.remove(tail);
    }
    return name.isEmpty() ? QStringLiteral("%1").arg(vendorId, 4, 16, QLatin1Char('0')) : name;
}

QString GpuInventory::edidMonitorName(const QByteArray &edid)
{
    if (edid.size() < 128) {
        return {};
    }
    for (int offset : {54, 72, 90, 108}) {
        if (edid[offset] == 0 && edid[offset + 1] == 0 && edid[offset + 2] == 0 && static_cast<uchar>(edid[offset + 3]) == 0xfc) {
            QByteArray text = edid.mid(offset + 5, 13);
            const int end = text.indexOf('\n');
            if (end >= 0) {
                text.truncate(end);
            }
            return QString::fromLatin1(text).trimmed();
        }
    }
    return {};
}

bool GpuInventory::isIntegratedFamily(quint16 vendorId, const QString &chip, const QString &name)
{
    if (vendorId == 0x8086) {
        static const QStringList discrete = {u"arc"_s, u"dg1"_s, u"dg2"_s, u"alchemist"_s, u"battlemage"_s, u"data center"_s, u"ponte"_s};
        const QString lowerName = name.toLower();
        const QString lowerChip = chip.toLower();
        for (const QString &word : discrete) {
            if (lowerName.contains(word) || lowerChip.startsWith(word)) {
                return false;
            }
        }
        return true;
    }
    if (vendorId == 0x1002) {
        // AMD names its APU graphics by family; discrete chips carry other code names
        static const QStringList apu = {
            u"renoir"_s,   u"cezanne"_s,   u"lucienne"_s,  u"barcelo"_s,   u"raven"_s,     u"picasso"_s,    u"rembrandt"_s, u"yellow carp"_s, u"phoenix"_s,
            u"hawk point"_s, u"mendocino"_s, u"raphael"_s,   u"granite"_s,   u"strix"_s,     u"krackan"_s,    u"kraken"_s,    u"van gogh"_s,    u"vangogh"_s,
            u"dragon range"_s, u"wani"_s,    u"carrizo"_s,   u"stoney"_s,    u"kaveri"_s,    u"godavari"_s,   u"kabini"_s,    u"mullins"_s,     u"beema"_s,
            u"bristol"_s,  u"llano"_s,     u"trinity"_s,   u"richland"_s,  u"sumo"_s,      u"wrestler"_s,   u"ontario"_s,   u"zacate"_s,      u"palm"_s,
        };
        const QString lowerChip = chip.toLower();
        for (const QString &family : apu) {
            if (lowerChip.contains(family)) {
                return true;
            }
        }
    }
    return false;
}

QList<Gpu> GpuInventory::read(const QString &root)
{
    QList<Gpu> gpus;
    const QString drm = root + u"/sys/class/drm"_s;
    QStringList cards = QDir(drm).entryList({u"card[0-9]*"_s}, QDir::Dirs | QDir::NoDotAndDotDot);
    cards.removeIf([](const QString &name) {
        return name.contains(u'-');
    });
    std::sort(cards.begin(), cards.end(), [](const QString &a, const QString &b) {
        return a.mid(4).toInt() < b.mid(4).toInt();
    });

    for (const QString &card : std::as_const(cards)) {
        const QString device = QFileInfo(drm + u'/' + card + u"/device"_s).canonicalFilePath();
        if (device.isEmpty() || !QFile::exists(device + u"/vendor"_s)) {
            continue; // not a PCI graphics processor
        }
        Gpu gpu;
        gpu.pciSlot = QFileInfo(device).fileName();
        gpu.id = u"pci-"_s + gpu.pciSlot;
        gpu.vendorId = readHex(device + u"/vendor"_s);
        gpu.deviceId = readHex(device + u"/device"_s);
        gpu.bootVga = readFirstLine(device + u"/boot_vga"_s) == u"1"_s;
        gpu.driver = QFileInfo(device + u"/driver"_s).symLinkTarget().section(u'/', -1);
        gpu.cardNode = u"/dev/dri/"_s + card;
        const QStringList renderNodes = QDir(device + u"/drm"_s).entryList({u"renderD*"_s}, QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
        if (!renderNodes.isEmpty()) {
            gpu.renderNode = u"/dev/dri/"_s + renderNodes.first();
            gpu.canRender = true;
            gpu.accessible = ::access(QFile::encodeName(root + gpu.renderNode).constData(), R_OK | W_OK) == 0;
        }

        const PciNames names = lookupPci(root, gpu.vendorId, gpu.deviceId);
        gpu.vendor = shortVendor(gpu.vendorId, names.vendor);
        QString marketing;
        if (names.device.isEmpty()) {
            gpu.chip = QStringLiteral("%1:%2").arg(gpu.vendorId, 4, 16, QLatin1Char('0')).arg(gpu.deviceId, 4, 16, QLatin1Char('0'));
        } else {
            const int open = names.device.indexOf(u" ["_s);
            const int close = names.device.lastIndexOf(u']');
            if (open > 0 && close > open) {
                gpu.chip = names.device.left(open);
                marketing = names.device.mid(open + 2, close - open - 2);
            } else {
                gpu.chip = names.device;
            }
        }
        if (!marketing.isEmpty()) {
            gpu.name = gpu.vendor + u' ' + marketing;
        } else if (gpu.chip.startsWith(gpu.vendor, Qt::CaseInsensitive)) {
            gpu.name = gpu.chip;
        } else {
            gpu.name = gpu.vendor + u' ' + gpu.chip;
        }

        const QStringList connectors = QDir(drm).entryList({card + u"-*"_s}, QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name | QDir::IgnoreCase);
        for (const QString &entry : connectors) {
            Connector connector;
            connector.name = entry.mid(card.size() + 1);
            connector.connected = readFirstLine(drm + u'/' + entry + u"/status"_s) == u"connected"_s;
            if (connector.connected) {
                QFile edid(drm + u'/' + entry + u"/edid"_s);
                if (edid.open(QIODevice::ReadOnly)) {
                    connector.monitor = edidMonitorName(edid.readAll());
                }
            }
            gpu.connectors.append(connector);
        }

        if (!gpu.canRender) {
            gpu.kind = GpuKind::Integrated; // a basic display adapter, built in
        } else if (isIntegratedFamily(gpu.vendorId, gpu.chip, gpu.name)) {
            gpu.kind = GpuKind::Integrated;
        } else if (gpu.vendorId != 0x1002 && gpu.vendorId != 0x10de && gpu.vendorId != 0x8086) {
            gpu.kind = gpu.bootVga ? GpuKind::Integrated : GpuKind::Discrete; // an unknown maker: the firmware's own device
        } else {
            gpu.kind = GpuKind::Discrete;
        }
        gpus.append(gpu);
    }
    return gpus;
}

}
