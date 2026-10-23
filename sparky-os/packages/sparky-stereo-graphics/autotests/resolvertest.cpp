// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "fixtures.h"
#include "resolver.h"

#include <QTemporaryDir>

using namespace SparkyGraphics;

class ResolverTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase();
    void profileNames();
    void automaticTargets();
    void automaticMain_data();
    void automaticMain();
    void profileMapping_data();
    void profileMapping();
    void explicitChoices();
    void missingGpuFallsBackAndSaysSo();
    void oneGpuHasNothingToChoose();
    void noGpu();
    void bmcNeverRendersTheDesktop();
    void aGpuTheAccountMayNotOpenIsNotOffered();
    void kwinDevices();
    void environments();
    void appPreferences();
    void categories();

private:
    QList<Gpu> read(const QList<FixtureGpu> &gpus)
    {
        auto fixture = std::make_unique<SysfsFixture>();
        for (const FixtureGpu &gpu : gpus) {
            fixture->add(gpu);
        }
        const QList<Gpu> list = GpuInventory::read(fixture->root());
        m_fixtures.push_back(std::move(fixture));
        return list;
    }
    std::vector<std::unique_ptr<SysfsFixture>> m_fixtures;
    QTemporaryDir m_config;
};

void ResolverTest::initTestCase()
{
    qputenv("XDG_CONFIG_HOME", m_config.path().toUtf8());
    qputenv("XDG_CONFIG_DIRS", m_config.path().toUtf8());
}

void ResolverTest::profileNames()
{
    QVERIFY(powerProfileFromString(u"power-saver"_s) == PowerProfile::PowerSaver);
    QVERIFY(powerProfileFromString(u"balanced"_s) == PowerProfile::Balanced);
    QVERIFY(powerProfileFromString(u"performance"_s) == PowerProfile::Performance);
    QVERIFY(powerProfileFromString(u"something-new"_s) == PowerProfile::Balanced);
    QVERIFY(powerProfileFromString(QString(), PowerProfile::Performance) == PowerProfile::Performance);
    QCOMPARE(powerProfileToString(PowerProfile::PowerSaver), u"power-saver"_s);
    QCOMPARE(powerProfileToString(PowerProfile::Balanced), u"balanced"_s);
    QCOMPARE(powerProfileToString(PowerProfile::Performance), u"performance"_s);
}

void ResolverTest::automaticTargets()
{
    QCOMPARE(Resolver::automaticTarget(PowerProfile::PowerSaver), u"integrated"_s);
    QCOMPARE(Resolver::automaticTarget(PowerProfile::Balanced), u"main"_s);
    QCOMPARE(Resolver::automaticTarget(PowerProfile::Performance), u"discrete"_s);
}

void ResolverTest::automaticMain_data()
{
    QTest::addColumn<int>("machine");
    QTest::addColumn<int>("expected");
    QTest::newRow("one") << 0 << 0;
    QTest::newRow("a10: the iGPU has the screens") << 1 << 0;
    QTest::newRow("host: most screens") << 2 << 0;
    QTest::newRow("bmc: the BMC cannot render") << 3 << 1;
    QTest::newRow("three: the laptop panel is on the Intel") << 4 << 0;
}

void ResolverTest::automaticMain()
{
    QFETCH(int, machine);
    QFETCH(int, expected);
    const QList<QList<FixtureGpu>> machines = {{SysfsFixture::intel()}, SysfsFixture::a10(), SysfsFixture::host(), SysfsFixture::bmc(), SysfsFixture::three()};
    Resolver resolver(read(machines[machine]), QString(), PowerProfile::Balanced);
    QCOMPARE(resolver.automaticMainIndex(), expected);
    QCOMPARE(resolver.mainIndex(), expected);
}

void ResolverTest::profileMapping_data()
{
    QTest::addColumn<int>("machine"); // 0 one, 1 a10, 2 host, 4 three
    QTest::addColumn<QString>("savedMain");
    QTest::addColumn<QString>("profile");
    QTest::addColumn<int>("expected");
    QTest::addColumn<bool>("isMain");
    QTest::addColumn<QString>("environmentContains");

    QTest::newRow("one saver") << 0 << QString() << u"power-saver"_s << 0 << true << QString();
    QTest::newRow("one performance") << 0 << QString() << u"performance"_s << 0 << true << QString();

    QTest::newRow("a10 saver") << 1 << QString() << u"power-saver"_s << 0 << true << QString();
    QTest::newRow("a10 balanced") << 1 << QString() << u"balanced"_s << 0 << true << QString();
    QTest::newRow("a10 performance") << 1 << QString() << u"performance"_s << 1 << false << u"DRI_PRIME=pci-0000_03_00_0"_s;

    QTest::newRow("host saver") << 2 << QString() << u"power-saver"_s << 0 << true << QString();
    QTest::newRow("host balanced") << 2 << QString() << u"balanced"_s << 0 << true << QString();
    QTest::newRow("host performance") << 2 << QString() << u"performance"_s << 1 << false << u"__NV_PRIME_RENDER_OFFLOAD=1"_s;

    // the person made the RTX 3060 the main GPU: it is then the ordinary path, the APU the offload
    QTest::newRow("host main nvidia saver") << 2 << u"pci-0000:01:00.0"_s << u"power-saver"_s << 0 << false << u"DRI_PRIME=pci-0000_0b_00_0"_s;
    QTest::newRow("host main nvidia balanced") << 2 << u"pci-0000:01:00.0"_s << u"balanced"_s << 1 << true << QString();
    QTest::newRow("host main nvidia performance") << 2 << u"pci-0000:01:00.0"_s << u"performance"_s << 1 << true << QString();

    QTest::newRow("three saver") << 4 << QString() << u"power-saver"_s << 0 << true << QString();
    QTest::newRow("three performance: the first discrete") << 4 << QString() << u"performance"_s << 1 << false << u"__NV_PRIME_RENDER_OFFLOAD=1"_s;
}

void ResolverTest::profileMapping()
{
    QFETCH(int, machine);
    QFETCH(QString, savedMain);
    QFETCH(QString, profile);
    QFETCH(int, expected);
    QFETCH(bool, isMain);
    QFETCH(QString, environmentContains);
    const QList<QList<FixtureGpu>> machines = {{SysfsFixture::intel()}, SysfsFixture::a10(), SysfsFixture::host(), {}, SysfsFixture::three()};
    Resolver resolver(read(machines[machine]), savedMain, powerProfileFromString(profile));
    const Resolution r = resolver.resolveChoice(u"auto"_s);
    QCOMPARE(r.gpuIndex, expected);
    QCOMPARE(r.isMain, isMain);
    QVERIFY(!r.missing);
    if (environmentContains.isEmpty()) {
        QVERIFY2(r.environment.isEmpty() == r.isMain, qPrintable(r.environment.join(u' ')));
    } else {
        QVERIFY2(r.environment.contains(environmentContains), qPrintable(r.environment.join(u' ')));
    }
    QVERIFY(r.reason.startsWith(u"profile:"_s) || r.reason == u"only-gpu"_s);
}

void ResolverTest::explicitChoices()
{
    Resolver resolver(read(SysfsFixture::three()), QString(), PowerProfile::PowerSaver);
    QCOMPARE(resolver.resolveChoice(u"integrated"_s).gpuIndex, 0);
    QCOMPARE(resolver.resolveChoice(u"discrete"_s).gpuIndex, 1);
    const Resolution third = resolver.resolveChoice(u"pci-0000:02:00.0"_s);
    QCOMPARE(third.gpuIndex, 2);
    QVERIFY(!third.isMain);
    QVERIFY(third.environment.contains(u"DRI_PRIME=pci-0000_02_00_0"_s));
    QCOMPARE(third.reason, u"choice"_s);
    // an explicit choice does not follow the profile
    Resolver performance(read(SysfsFixture::three()), QString(), PowerProfile::Performance);
    QCOMPARE(performance.resolveChoice(u"integrated"_s).gpuIndex, 0);
}

void ResolverTest::missingGpuFallsBackAndSaysSo()
{
    Resolver resolver(read(SysfsFixture::host()), QString(), PowerProfile::Balanced);
    const Resolution r = resolver.resolveChoice(u"pci-0000:09:00.0"_s);
    QCOMPARE(r.gpuIndex, 0);
    QVERIFY(r.missing);
    QVERIFY(r.isMain);
    // a saved main GPU that is not there leaves Automatic in charge
    Resolver gone(read(SysfsFixture::host()), u"pci-0000:09:00.0"_s, PowerProfile::Balanced);
    QCOMPARE(gone.mainIndex(), 0);
    QCOMPARE(gone.kwinDrmDevices(), QString());
}

void ResolverTest::oneGpuHasNothingToChoose()
{
    Resolver resolver(read({SysfsFixture::intel()}), QString(), PowerProfile::Performance);
    for (const QString &choice : {u"auto"_s, u"integrated"_s, u"discrete"_s}) {
        const Resolution r = resolver.resolveChoice(choice);
        QCOMPARE(r.gpuIndex, 0);
        QVERIFY(r.isMain);
        QVERIFY(r.environment.isEmpty());
    }
    QCOMPARE(resolver.kwinDrmDevices(), QString());
}

void ResolverTest::noGpu()
{
    Resolver resolver({}, QString(), PowerProfile::Balanced);
    QCOMPARE(resolver.mainIndex(), -1);
    QCOMPARE(resolver.resolveChoice(u"auto"_s).gpuIndex, -1);
    QCOMPARE(resolver.kwinDrmDevices(), QString());
}

void ResolverTest::bmcNeverRendersTheDesktop()
{
    Resolver resolver(read(SysfsFixture::bmc()), QString(), PowerProfile::PowerSaver);
    QCOMPARE(resolver.mainIndex(), 1);
    // no integrated GPU that renders: the main GPU
    QCOMPARE(resolver.resolveChoice(u"integrated"_s).gpuIndex, 1);
    // the chip that cannot render is not chosen even by its id
    QCOMPARE(resolver.resolveChoice(u"pci-0000:04:00.0"_s).gpuIndex, 1);
}

void ResolverTest::aGpuTheAccountMayNotOpenIsNotOffered()
{
    QList<FixtureGpu> machine = SysfsFixture::host();
    machine[1].accessible = false;
    Resolver resolver(read(machine), QString(), PowerProfile::Performance);
    // Performance would send programs to the discrete GPU, which this account cannot open: the main GPU instead
    const Resolution r = resolver.resolveChoice(u"auto"_s);
    QCOMPARE(r.gpuIndex, 0);
    QVERIFY(r.isMain);
    QCOMPARE(resolver.resolveChoice(u"discrete"_s).gpuIndex, 0);
    QCOMPARE(resolver.resolveChoice(u"pci-0000:01:00.0"_s).reason, u"only-gpu"_s); // one GPU left to use
    AppEntry app;
    app.preference = AppPreference::OtherGpu;
    GraphicsSettings settings;
    QCOMPARE(resolver.resolveApp(app, settings).gpuIndex, 0);
}

void ResolverTest::kwinDevices()
{
    Resolver automatic(read(SysfsFixture::host()), QString(), PowerProfile::Balanced);
    QCOMPARE(automatic.kwinDrmDevices(), QString());

    Resolver nvidia(read(SysfsFixture::host()), u"pci-0000:01:00.0"_s, PowerProfile::Balanced);
    QCOMPARE(nvidia.kwinDrmDevices(), u"/dev/dri/card1:/dev/dri/card0"_s);

    Resolver third(read(SysfsFixture::three()), u"pci-0000:02:00.0"_s, PowerProfile::Balanced);
    QCOMPARE(third.kwinDrmDevices(), u"/dev/dri/card2:/dev/dri/card0:/dev/dri/card1"_s);

    // cards that cannot render go last
    Resolver bmc(read(SysfsFixture::bmc()), u"pci-0000:65:00.0"_s, PowerProfile::Balanced);
    QCOMPARE(bmc.kwinDrmDevices(), u"/dev/dri/card1:/dev/dri/card0"_s);
    // a saved choice of a chip that cannot render is not used
    Resolver cannot(read(SysfsFixture::bmc()), u"pci-0000:04:00.0"_s, PowerProfile::Balanced);
    QCOMPARE(cannot.kwinDrmDevices(), QString());
}

void ResolverTest::environments()
{
    const QList<Gpu> host = read(SysfsFixture::host());
    // the same variables switcherooctl prints for these two chips on the workstation
    QCOMPARE(Resolver::environmentFor(host[1]),
             (QStringList{u"__GLX_VENDOR_LIBRARY_NAME=nvidia"_s, u"__NV_PRIME_RENDER_OFFLOAD=1"_s, u"__VK_LAYER_NV_optimus=NVIDIA_only"_s, u"VK_LOADER_DRIVERS_SELECT=*nvidia*"_s}));
    QCOMPARE(Resolver::environmentFor(host[0]), (QStringList{u"DRI_PRIME=pci-0000_0b_00_0"_s, u"VK_LOADER_DRIVERS_SELECT=*radeon*"_s}));
    const QList<Gpu> intel = read({SysfsFixture::intel()});
    QCOMPARE(Resolver::environmentFor(intel[0]), (QStringList{u"DRI_PRIME=pci-0000_00_02_0"_s, u"VK_LOADER_DRIVERS_SELECT=*intel*"_s}));
}

void ResolverTest::appPreferences()
{
    GraphicsSettings settings;
    AppEntry app;
    app.id = u"x.desktop"_s;
    app.category = Category::Players;

    Resolver host(read(SysfsFixture::host()), QString(), PowerProfile::Balanced);
    app.preference = AppPreference::OtherGpu;
    Resolution r = host.resolveApp(app, settings);
    QCOMPARE(r.gpuIndex, 1);
    QCOMPARE(r.reason, u"app"_s);
    QVERIFY(!r.environment.isEmpty());

    // "the other GPU" is relative to the main one, as KDE's key is relative to the default
    Resolver nvidiaMain(read(SysfsFixture::host()), u"pci-0000:01:00.0"_s, PowerProfile::Balanced);
    QCOMPARE(nvidiaMain.resolveApp(app, settings).gpuIndex, 0);

    // three GPUs: the first of the opposite kind
    Resolver three(read(SysfsFixture::three()), QString(), PowerProfile::Balanced);
    QCOMPARE(three.resolveApp(app, settings).gpuIndex, 1);
    Resolver threeNvidiaMain(read(SysfsFixture::three()), u"pci-0000:01:00.0"_s, PowerProfile::Balanced);
    QCOMPARE(threeNvidiaMain.resolveApp(app, settings).gpuIndex, 0);

    // MainGpu keeps the program on the main GPU whatever the category and the profile say
    settings.setRenderChoice(Category::Players, u"discrete"_s);
    app.preference = AppPreference::MainGpu;
    r = host.resolveApp(app, settings);
    QCOMPARE(r.gpuIndex, 0);
    QVERIFY(r.isMain);
    QVERIFY(r.environment.isEmpty());

    // Unset: the category decides
    app.preference = AppPreference::Unset;
    r = host.resolveApp(app, settings);
    QCOMPARE(r.gpuIndex, 1);
    QCOMPARE(r.reason, u"choice"_s);

    // one GPU: nothing to prefer
    Resolver one(read({SysfsFixture::intel()}), QString(), PowerProfile::Balanced);
    app.preference = AppPreference::OtherGpu;
    QCOMPARE(one.resolveApp(app, settings).gpuIndex, 0);
}

void ResolverTest::categories()
{
    GraphicsSettings settings;
    settings.setRenderChoice(Category::Players, u"integrated"_s);
    settings.setRenderChoice(Category::Games, u"discrete"_s);
    Resolver host(read(SysfsFixture::host()), QString(), PowerProfile::Performance);
    QCOMPARE(host.resolveCategory(Category::Players, settings).gpuIndex, 0);
    QCOMPARE(host.resolveCategory(Category::Games, settings).gpuIndex, 1);
    // Browsers and Other are Automatic: performance, so the discrete GPU
    QCOMPARE(host.resolveCategory(Category::Browsers, settings).gpuIndex, 1);
    QCOMPARE(host.resolveCategory(Category::Other, settings).gpuIndex, 1);
    Resolver saver(read(SysfsFixture::host()), QString(), PowerProfile::PowerSaver);
    QCOMPARE(saver.resolveCategory(Category::Browsers, settings).gpuIndex, 0);
    QCOMPARE(saver.resolveCategory(Category::Games, settings).gpuIndex, 1);
}

QTEST_GUILESS_MAIN(ResolverTest)
#include "resolvertest.moc"
