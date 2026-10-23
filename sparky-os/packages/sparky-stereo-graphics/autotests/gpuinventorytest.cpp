// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "fixtures.h"
#include "gpuinventory.h"

using namespace SparkyGraphics;

class GpuInventoryTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void oneGpu();
    void a10TwoAmd();
    void hostAmdAndNvidia();
    void bmcCannotRender();
    void threeGpus();
    void renderNodeWithoutPermission();
    void noGpus();
    void edidName();
    void edidWithoutName();
    void integratedFamilies_data();
    void integratedFamilies();
    void mesaId();

private:
    static QList<Gpu> read(const QList<FixtureGpu> &gpus, SysfsFixture &fixture)
    {
        for (const FixtureGpu &gpu : gpus) {
            fixture.add(gpu);
        }
        return GpuInventory::read(fixture.root());
    }
};

void GpuInventoryTest::oneGpu()
{
    SysfsFixture fixture;
    const QList<Gpu> gpus = read({SysfsFixture::intel()}, fixture);
    QCOMPARE(gpus.size(), 1);
    const Gpu &gpu = gpus.first();
    QCOMPARE(gpu.id, u"pci-0000:00:02.0"_s);
    QCOMPARE(gpu.vendor, u"Intel"_s);
    QCOMPARE(gpu.name, u"Intel Iris Xe Graphics"_s);
    QCOMPARE(gpu.driver, u"i915"_s);
    QCOMPARE(gpu.cardNode, u"/dev/dri/card0"_s);
    QCOMPARE(gpu.renderNode, u"/dev/dri/renderD128"_s);
    QVERIFY(gpu.bootVga);
    QVERIFY(gpu.canRender);
    QVERIFY(gpu.kind == GpuKind::Integrated);
    QCOMPARE(gpu.connectors.size(), 2);
    QCOMPARE(gpu.connectedCount(), 1);
    QVERIFY(gpu.hasInternalScreen());
    QCOMPARE(gpu.connectors.first().name, u"eDP-1"_s);
    QCOMPARE(gpu.connectors.first().monitor, u"LP156WFC"_s);
}

void GpuInventoryTest::a10TwoAmd()
{
    SysfsFixture fixture;
    const QList<Gpu> gpus = read(SysfsFixture::a10(), fixture);
    QCOMPARE(gpus.size(), 2);
    QCOMPARE(gpus[0].chip, u"Wani"_s);
    QVERIFY(gpus[0].kind == GpuKind::Integrated);
    QVERIFY(gpus[0].hasScreens());
    QCOMPARE(gpus[0].connectedCount(), 2);
    QCOMPARE(gpus[0].connectors[1].monitor, u"SONY TV"_s);
    QCOMPARE(gpus[1].chip, u"Sun XT"_s);
    QVERIFY(gpus[1].kind == GpuKind::Discrete);
    QVERIFY(!gpus[1].hasScreens());
    QVERIFY(gpus[1].connectors.isEmpty());
    QVERIFY(gpus[1].canRender);
    QCOMPARE(gpus[1].driver, u"amdgpu"_s);
    QCOMPARE(gpus[1].renderNode, u"/dev/dri/renderD129"_s);
    // two chips of one vendor still get two names and two ids
    QVERIFY(gpus[0].id != gpus[1].id);
    QVERIFY(gpus[0].name != gpus[1].name);
}

void GpuInventoryTest::hostAmdAndNvidia()
{
    SysfsFixture fixture;
    const QList<Gpu> gpus = read(SysfsFixture::host(), fixture);
    QCOMPARE(gpus.size(), 2);
    QCOMPARE(gpus[0].vendor, u"AMD"_s);
    QCOMPARE(gpus[0].chip, u"Cezanne"_s);
    QVERIFY(gpus[0].kind == GpuKind::Integrated);
    QCOMPARE(gpus[0].connectedCount(), 2);
    QCOMPARE(gpus[1].vendor, u"NVIDIA"_s);
    QCOMPARE(gpus[1].name, u"NVIDIA GeForce RTX 3060 Lite Hash Rate"_s);
    QVERIFY(gpus[1].kind == GpuKind::Discrete);
    QCOMPARE(gpus[1].driver, u"nvidia"_s);
    QCOMPARE(gpus[1].connectors.size(), 4);
    QCOMPARE(gpus[1].connectedCount(), 1);
    QCOMPARE(gpus[1].connectors.last().monitor, u"LG TV"_s);
}

void GpuInventoryTest::bmcCannotRender()
{
    SysfsFixture fixture;
    const QList<Gpu> gpus = read(SysfsFixture::bmc(), fixture);
    QCOMPARE(gpus.size(), 2);
    QVERIFY(gpus[0].bootVga);
    QVERIFY(!gpus[0].canRender);
    QVERIFY(gpus[0].renderNode.isEmpty());
    QVERIFY(gpus[1].canRender);
}

void GpuInventoryTest::threeGpus()
{
    SysfsFixture fixture;
    const QList<Gpu> gpus = read(SysfsFixture::three(), fixture);
    QCOMPARE(gpus.size(), 3);
    QVERIFY(gpus[0].kind == GpuKind::Integrated);
    QVERIFY(gpus[1].kind == GpuKind::Discrete);
    QVERIFY(gpus[2].kind == GpuKind::Discrete);
    QCOMPARE(gpus[2].name, u"AMD Radeon RX 5500/5500M / Pro 5500M"_s);
    QCOMPARE(gpus[2].cardNode, u"/dev/dri/card2"_s);
}

void GpuInventoryTest::renderNodeWithoutPermission()
{
    SysfsFixture fixture;
    QList<FixtureGpu> machine = SysfsFixture::a10();
    machine[1].accessible = false;
    const QList<Gpu> gpus = read(machine, fixture);
    QVERIFY(gpus[0].accessible);
    QVERIFY(gpus[0].usable());
    // the chip can draw, the account may not open it: it is listed, and is not something to send programs to
    QVERIFY(gpus[1].canRender);
    QVERIFY(!gpus[1].accessible);
    QVERIFY(!gpus[1].usable());
}

void GpuInventoryTest::noGpus()
{
    SysfsFixture fixture;
    QVERIFY(GpuInventory::read(fixture.root()).isEmpty());
}

void GpuInventoryTest::edidName()
{
    QCOMPARE(GpuInventory::edidMonitorName(fixtureEdid(u"DELL U2720Q"_s)), u"DELL U2720Q"_s);
    QCOMPARE(GpuInventory::edidMonitorName(fixtureEdid(u"A"_s)), u"A"_s);
}

void GpuInventoryTest::edidWithoutName()
{
    QByteArray edid = fixtureEdid(u"X"_s);
    edid.replace(75, 1, QByteArray(1, '\x10')); // the tag is no longer 0xFC
    QCOMPARE(GpuInventory::edidMonitorName(edid), QString());
    QCOMPARE(GpuInventory::edidMonitorName(QByteArray()), QString());
    QCOMPARE(GpuInventory::edidMonitorName(QByteArray(20, '\0')), QString());
}

void GpuInventoryTest::integratedFamilies_data()
{
    QTest::addColumn<int>("vendor");
    QTest::addColumn<QString>("chip");
    QTest::addColumn<QString>("name");
    QTest::addColumn<bool>("integrated");
    QTest::newRow("renoir") << 0x1002 << u"Renoir"_s << u"x"_s << true;
    QTest::newRow("cezanne") << 0x1002 << u"Cezanne"_s << u"x"_s << true;
    QTest::newRow("wani") << 0x1002 << u"Wani"_s << u"x"_s << true;
    QTest::newRow("phoenix") << 0x1002 << u"Phoenix1"_s << u"x"_s << true;
    QTest::newRow("sun xt") << 0x1002 << u"Sun XT"_s << u"x"_s << false;
    QTest::newRow("navi") << 0x1002 << u"Navi 14"_s << u"x"_s << false;
    QTest::newRow("intel iris") << 0x8086 << u"Alder Lake-P GT2"_s << u"Intel Iris Xe Graphics"_s << true;
    QTest::newRow("intel arc") << 0x8086 << u"DG2"_s << u"Intel Arc A770"_s << false;
    QTest::newRow("nvidia") << 0x10de << u"GA106"_s << u"x"_s << false;
}

void GpuInventoryTest::integratedFamilies()
{
    QFETCH(int, vendor);
    QFETCH(QString, chip);
    QFETCH(QString, name);
    QFETCH(bool, integrated);
    QCOMPARE(GpuInventory::isIntegratedFamily(quint16(vendor), chip, name), integrated);
}

void GpuInventoryTest::mesaId()
{
    Gpu gpu;
    gpu.pciSlot = u"0000:0b:00.0"_s;
    QCOMPARE(gpu.mesaId(), u"pci-0000_0b_00_0"_s);
}

QTEST_GUILESS_MAIN(GpuInventoryTest)
#include "gpuinventorytest.moc"
