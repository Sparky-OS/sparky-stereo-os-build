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
    void playersOnTheMeasuredGpu_data();
    void playersOnTheMeasuredGpu();
    void threeDFollowsTheMeasuredGpu();
    void followThePowerProfileIsAChoice();
    void oneGpuIgnoresTheRecord();
    void automaticMain_data();
    void automaticMain();
    void profileMapping_data();
    void profileMapping();
    void explicitChoices();
    void missingGpuIsSaidNotReplaced();
    void oneGpuKeepsTheChoiceVisible();
    void oneGpuHasNothingToChoose();
    void profileThatCannotBeReadIsNotBalanced();
    void profileRuleSaysAnAbsentKind();
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
    qputenv("XDG_STATE_HOME", m_config.path().toUtf8());
    qputenv("XDG_CONFIG_DIRS", m_config.path().toUtf8());
}

void ResolverTest::profileNames()
{
    QVERIFY(powerProfileFromString(u"power-saver"_s) == PowerProfile::PowerSaver);
    QVERIFY(powerProfileFromString(u"balanced"_s) == PowerProfile::Balanced);
    QVERIFY(powerProfileFromString(u"performance"_s) == PowerProfile::Performance);
    // a name that is no profile is no profile, never Balanced in its place
    QVERIFY(!powerProfileFromString(u"something-new"_s));
    QVERIFY(!powerProfileFromString(QString()));
    QCOMPARE(powerProfileToString(PowerProfile::PowerSaver), u"power-saver"_s);
    QCOMPARE(powerProfileToString(PowerProfile::Balanced), u"balanced"_s);
    QCOMPARE(powerProfileToString(PowerProfile::Performance), u"performance"_s);
}

void ResolverTest::automaticTargets()
{
    // Daniel, 2026-10-24, split by kind: players, games and any program presenting 3D on the GPU measured best,
    // battery included; browsers by the power profile; other programs on the GPU that draws the desktop
    for (PowerProfile profile : {PowerProfile::PowerSaver, PowerProfile::Balanced, PowerProfile::Performance}) {
        QCOMPARE(Resolver::automaticTarget(Category::Players, profile), u"measured"_s);
        QCOMPARE(Resolver::automaticTarget(Category::Games, profile), u"measured"_s);
        QCOMPARE(Resolver::automaticTarget(Category::Other, profile), u"main"_s);
        for (Category category : {Category::Players, Category::Games, Category::Browsers, Category::Other}) {
            QCOMPARE(Resolver::automaticTarget(category, profile, true), u"measured"_s);
        }
    }
    QCOMPARE(Resolver::automaticTarget(Category::Browsers, PowerProfile::PowerSaver), u"integrated"_s);
    QCOMPARE(Resolver::automaticTarget(Category::Browsers, PowerProfile::Balanced), u"main"_s);
    QCOMPARE(Resolver::automaticTarget(Category::Browsers, PowerProfile::Performance), u"discrete"_s);
}

void ResolverTest::playersOnTheMeasuredGpu_data()
{
    QTest::addColumn<int>("machine"); // 1 a10, 2 host, 4 three
    QTest::addColumn<QString>("record"); // the machine record's BestGpu
    QTest::addColumn<QString>("profile");
    QTest::addColumn<int>("expected");
    QTest::addColumn<QString>("reason");
    QTest::addColumn<QString>("environmentContains");
    // the A10: the R5 M430 (Hainan) dropped about a ninth of the frames the Carrizo that drives the screens did (ORDER 234)
    for (const QString &profile : {u"power-saver"_s, u"balanced"_s, u"performance"_s}) {
        QTest::addRow("a10 record by id, %s", qPrintable(profile)) << 1 << u"1002:6660"_s << profile << 1 << u"measured"_s << u"DRI_PRIME=pci-0000_03_00_0"_s;
        QTest::addRow("a10 record by slot, %s", qPrintable(profile)) << 1 << u"pci-0000:03:00.0"_s << profile << 1 << u"measured"_s << u"DRI_PRIME=pci-0000_03_00_0"_s;
        // without a record: the discrete GPU, also on battery
        QTest::addRow("a10 not measured, %s", qPrintable(profile)) << 1 << QString() << profile << 1 << u"unmeasured"_s << u"DRI_PRIME=pci-0000_03_00_0"_s;
        QTest::addRow("host not measured, %s", qPrintable(profile)) << 2 << QString() << profile << 1 << u"unmeasured"_s << u"__NV_PRIME_RENDER_OFFLOAD=1"_s;
        // a record that names the GPU that draws the desktop keeps players there, even on performance
        QTest::addRow("host record names the APU, %s", qPrintable(profile)) << 2 << u"1002:1638"_s << profile << 0 << u"measured"_s << QString();
        QTest::addRow("three record names the third, %s", qPrintable(profile)) << 4 << u"pci-0000:02:00.0"_s << profile << 2 << u"measured"_s << u"DRI_PRIME=pci-0000_02_00_0"_s;
        // a record for a GPU that is not here: Automatic's rule gives the discrete GPU, and says the measured GPU is missing
        QTest::addRow("a10 record names a missing GPU, %s", qPrintable(profile)) << 1 << u"10de:2504"_s << profile << 1 << u"measured-missing"_s << u"DRI_PRIME=pci-0000_03_00_0"_s;
    }
}

void ResolverTest::playersOnTheMeasuredGpu()
{
    QFETCH(int, machine);
    QFETCH(QString, record);
    QFETCH(QString, profile);
    QFETCH(int, expected);
    QFETCH(QString, reason);
    QFETCH(QString, environmentContains);
    const QList<QList<FixtureGpu>> machines = {{SysfsFixture::intel()}, SysfsFixture::a10(), SysfsFixture::host(), {}, SysfsFixture::three()};
    Resolver resolver(read(machines[machine]), QString(), *powerProfileFromString(profile), record);
    GraphicsSettings settings;
    const Resolution r = resolver.resolveCategory(Category::Players, settings);
    QCOMPARE(r.gpuIndex, expected);
    QCOMPARE(r.reason, reason);
    if (environmentContains.isEmpty()) {
        QVERIFY2(r.environment.isEmpty(), qPrintable(r.environment.join(u' ')));
    } else {
        QVERIFY2(r.environment.contains(environmentContains), qPrintable(r.environment.join(u' ')));
    }
    QCOMPARE(resolver.presentingIndex(), expected);
}

void ResolverTest::threeDFollowsTheMeasuredGpu()
{
    GraphicsSettings settings;
    // the A10 on battery: a game on the measured R5 M430 in 2D and in 3D; a browser in 2D on the integrated GPU, in 3D on the R5 M430
    Resolver battery(read(SysfsFixture::a10()), QString(), PowerProfile::PowerSaver, u"1002:6660"_s);
    QCOMPARE(battery.resolveCategory(Category::Games, settings).gpuIndex, 1);
    QCOMPARE(battery.resolveCategory(Category::Games, settings).reason, u"measured"_s);
    QCOMPARE(battery.resolveCategory(Category::Browsers, settings).gpuIndex, 0);
    QCOMPARE(battery.resolveCategory(Category::Browsers, settings, true).gpuIndex, 1);
    QCOMPARE(battery.resolveCategory(Category::Games, settings, true).gpuIndex, 1);
    QCOMPARE(battery.resolveCategory(Category::Games, settings, true).reason, u"measured"_s);
    QCOMPARE(battery.resolveCategory(Category::Other, settings, true).gpuIndex, 1);
    // the person's choice wins over Automatic, in 3D as well
    settings.setRenderChoice(Category::Games, u"integrated"_s);
    QCOMPARE(battery.resolveCategory(Category::Games, settings, true).gpuIndex, 0);
    QCOMPARE(battery.resolveCategory(Category::Games, settings, true).reason, u"choice"_s);
    settings.setRenderChoice(Category::Players, u"integrated"_s);
    QCOMPARE(battery.resolveCategory(Category::Players, settings).gpuIndex, 0);
    // a program's own setting wins over everything
    AppEntry app;
    app.category = Category::Players;
    app.preference = AppPreference::MainGpu;
    GraphicsSettings automatic;
    QCOMPARE(battery.resolveApp(app, automatic, true).gpuIndex, 0);
    app.preference = AppPreference::Unset;
    QCOMPARE(battery.resolveApp(app, automatic).gpuIndex, 1);
    app.category = Category::Other;
    QCOMPARE(battery.resolveApp(app, automatic).gpuIndex, 0);
    QCOMPARE(battery.resolveApp(app, automatic, true).gpuIndex, 1);
}

void ResolverTest::followThePowerProfileIsAChoice()
{
    // "profile" keeps the power profile in charge where Automatic would not: players, and 3D
    GraphicsSettings settings;
    settings.setRenderChoice(Category::Players, u"profile"_s);
    settings.setRenderChoice(Category::Games, u"profile"_s);
    Resolver battery(read(SysfsFixture::a10()), QString(), PowerProfile::PowerSaver, u"1002:6660"_s);
    QCOMPARE(battery.resolveCategory(Category::Players, settings).gpuIndex, 0);
    QCOMPARE(battery.resolveCategory(Category::Players, settings).reason, u"profile:power-saver"_s);
    QCOMPARE(battery.resolveCategory(Category::Games, settings, true).gpuIndex, 0);
    Resolver mains(read(SysfsFixture::a10()), QString(), PowerProfile::Performance, u"1002:6660"_s);
    QCOMPARE(mains.resolveCategory(Category::Players, settings).gpuIndex, 1);
    Resolver balanced(read(SysfsFixture::host()), QString(), PowerProfile::Balanced);
    QCOMPARE(balanced.resolveChoice(u"profile"_s, Category::Players).gpuIndex, 0);
    QCOMPARE(balanced.resolveChoice(u"profile"_s, Category::Players).reason, u"profile:balanced"_s);
}

void ResolverTest::oneGpuIgnoresTheRecord()
{
    Resolver one(read({SysfsFixture::intel()}), QString(), PowerProfile::PowerSaver, u"1002:6660"_s);
    GraphicsSettings settings;
    const Resolution r = one.resolveCategory(Category::Players, settings, true);
    QCOMPARE(r.gpuIndex, 0);
    QCOMPARE(r.reason, u"only-gpu"_s);
    QVERIFY(r.environment.isEmpty());
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
    QTest::addColumn<int>("category");
    QTest::addColumn<int>("machine"); // 0 one, 1 a10, 2 host, 4 three
    QTest::addColumn<QString>("savedMain");
    QTest::addColumn<QString>("profile");
    QTest::addColumn<int>("expected");
    QTest::addColumn<bool>("isMain");
    QTest::addColumn<QString>("environmentContains");

    const int browsers = int(Category::Browsers);
    const int other = int(Category::Other);
    QTest::newRow("browsers one saver") << browsers << 0 << QString() << u"power-saver"_s << 0 << true << QString();
    QTest::newRow("browsers one performance") << browsers << 0 << QString() << u"performance"_s << 0 << true << QString();

    QTest::newRow("browsers a10 saver") << browsers << 1 << QString() << u"power-saver"_s << 0 << true << QString();
    QTest::newRow("browsers a10 balanced") << browsers << 1 << QString() << u"balanced"_s << 0 << true << QString();
    QTest::newRow("browsers a10 performance") << browsers << 1 << QString() << u"performance"_s << 1 << false << u"DRI_PRIME=pci-0000_03_00_0"_s;

    QTest::newRow("browsers host saver") << browsers << 2 << QString() << u"power-saver"_s << 0 << true << QString();
    QTest::newRow("browsers host balanced") << browsers << 2 << QString() << u"balanced"_s << 0 << true << QString();
    QTest::newRow("browsers host performance") << browsers << 2 << QString() << u"performance"_s << 1 << false << u"__NV_PRIME_RENDER_OFFLOAD=1"_s;

    // the person made the RTX 3060 the main GPU: it is then the ordinary path, the APU the offload, with Mesa's EGL and GLX named
    QTest::newRow("browsers host main nvidia saver") << browsers << 2 << u"pci-0000:01:00.0"_s << u"power-saver"_s << 0 << false
                                                     << u"__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json"_s;
    QTest::newRow("browsers host main nvidia balanced") << browsers << 2 << u"pci-0000:01:00.0"_s << u"balanced"_s << 1 << true << QString();
    QTest::newRow("browsers host main nvidia performance") << browsers << 2 << u"pci-0000:01:00.0"_s << u"performance"_s << 1 << true << QString();

    QTest::newRow("browsers three saver") << browsers << 4 << QString() << u"power-saver"_s << 0 << true << QString();
    QTest::newRow("browsers three performance: the first discrete") << browsers << 4 << QString() << u"performance"_s << 1 << false
                                                                   << u"__NV_PRIME_RENDER_OFFLOAD=1"_s;

    // other programs stay on the GPU that draws the desktop in every profile
    for (const QString &profile : {u"power-saver"_s, u"balanced"_s, u"performance"_s}) {
        QTest::addRow("other a10 %s", qPrintable(profile)) << other << 1 << QString() << profile << 0 << true << QString();
        QTest::addRow("other host %s", qPrintable(profile)) << other << 2 << QString() << profile << 0 << true << QString();
        QTest::addRow("other host main nvidia %s", qPrintable(profile)) << other << 2 << u"pci-0000:01:00.0"_s << profile << 1 << true << QString();
        QTest::addRow("other three %s", qPrintable(profile)) << other << 4 << QString() << profile << 0 << true << QString();
    }
}

void ResolverTest::profileMapping()
{
    QFETCH(int, category);
    QFETCH(int, machine);
    QFETCH(QString, savedMain);
    QFETCH(QString, profile);
    QFETCH(int, expected);
    QFETCH(bool, isMain);
    QFETCH(QString, environmentContains);
    const QList<QList<FixtureGpu>> machines = {{SysfsFixture::intel()}, SysfsFixture::a10(), SysfsFixture::host(), {}, SysfsFixture::three()};
    Resolver resolver(read(machines[machine]), savedMain, *powerProfileFromString(profile));
    const Resolution r = resolver.resolveChoice(u"auto"_s, Category(category));
    QCOMPARE(r.gpuIndex, expected);
    QCOMPARE(r.isMain, isMain);
    QVERIFY(!r.missing);
    if (environmentContains.isEmpty()) {
        QVERIFY2(r.environment.isEmpty() == r.isMain, qPrintable(r.environment.join(u' ')));
    } else {
        QVERIFY2(r.environment.contains(environmentContains), qPrintable(r.environment.join(u' ')));
    }
    QVERIFY(r.reason.startsWith(u"profile:"_s) || r.reason == u"desktop"_s || r.reason == u"only-gpu"_s);
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

void ResolverTest::missingGpuIsSaidNotReplaced()
{
    // ORDER 346a, U52: the chosen GPU is kept or said to be unusable; no other GPU is put in its place
    Resolver resolver(read(SysfsFixture::host()), QString(), PowerProfile::Balanced);
    const Resolution r = resolver.resolveChoice(u"pci-0000:09:00.0"_s);
    QCOMPARE(r.gpuIndex, -1);
    QVERIFY(r.missing);
    QCOMPARE(r.problem, u"gpu-missing"_s);
    QCOMPARE(r.requested, u"pci-0000:09:00.0"_s);
    QVERIFY(r.environment.isEmpty());
    QCOMPARE(resolver.usableIndices(), (QList<int>{0, 1}));
    // a saved main GPU that is not there is said; KWin's own order is what draws until the person chooses
    Resolver gone(read(SysfsFixture::host()), u"pci-0000:09:00.0"_s, PowerProfile::Balanced);
    QCOMPARE(gone.mainIndex(), 0);
    QCOMPARE(gone.kwinDrmDevices(), QString());
    QCOMPARE(gone.mainProblem().problem, u"gpu-missing"_s);
    QCOMPARE(gone.mainProblem().requested, u"pci-0000:09:00.0"_s);
    Resolver here(read(SysfsFixture::host()), u"pci-0000:01:00.0"_s, PowerProfile::Balanced);
    QVERIFY(here.mainProblem().problem.isEmpty());
    QCOMPARE(here.mainProblem().gpuIndex, 1);
    Resolver automatic(read(SysfsFixture::host()), QString(), PowerProfile::Balanced);
    QVERIFY(automatic.mainProblem().problem.isEmpty());
}

void ResolverTest::oneGpuKeepsTheChoiceVisible()
{
    // U52: the one-GPU shortcut answered "the only GPU" for a chosen GPU that is gone; now the choice is checked first
    Resolver one(read({SysfsFixture::intel()}), QString(), PowerProfile::Balanced);
    const Resolution r = one.resolveChoice(u"pci-0000:01:00.0"_s);
    QCOMPARE(r.problem, u"gpu-missing"_s);
    QCOMPARE(r.gpuIndex, -1);
    // the GPU that is here, chosen by its id, is simply used
    QCOMPARE(one.resolveChoice(u"pci-0000:00:02.0"_s).gpuIndex, 0);
    QVERIFY(one.resolveChoice(u"pci-0000:00:02.0"_s).problem.isEmpty());
    // no GPU at all: a saved GPU is still said, Automatic has nothing to choose
    Resolver none({}, QString(), PowerProfile::Balanced);
    QCOMPARE(none.resolveChoice(u"pci-0000:01:00.0"_s).problem, u"gpu-missing"_s);
    QCOMPARE(none.resolveChoice(u"discrete"_s).problem, u"kind-missing"_s);
    QVERIFY(none.resolveChoice(u"auto"_s).problem.isEmpty());
}

void ResolverTest::oneGpuHasNothingToChoose()
{
    Resolver resolver(read({SysfsFixture::intel()}), QString(), PowerProfile::Performance);
    for (const QString &choice : {u"auto"_s, u"integrated"_s, u"profile"_s}) {
        const Resolution r = resolver.resolveChoice(choice);
        QCOMPARE(r.gpuIndex, 0);
        QVERIFY(r.isMain);
        QVERIFY(r.environment.isEmpty());
        QVERIFY(r.problem.isEmpty());
    }
    // a discrete GPU chosen when there was one, and gone: said, not the integrated GPU in its place
    const Resolution discrete = resolver.resolveChoice(u"discrete"_s);
    QCOMPARE(discrete.problem, u"kind-missing"_s);
    QCOMPARE(discrete.requested, u"discrete"_s);
    QCOMPARE(discrete.gpuIndex, -1);
    QCOMPARE(resolver.kwinDrmDevices(), QString());
}

void ResolverTest::profileThatCannotBeReadIsNotBalanced()
{
    // U24: without the profile, the kinds that follow it cannot be placed; the others are unaffected
    ProfileReading unread;
    unread.error = u"not-running"_s;
    Resolver resolver(read(SysfsFixture::host()), QString(), unread);
    const Resolution browsers = resolver.resolveChoice(u"auto"_s, Category::Browsers);
    QCOMPARE(browsers.problem, u"profile-unreadable"_s);
    QCOMPARE(browsers.gpuIndex, -1);
    QCOMPARE(resolver.resolveChoice(u"profile"_s, Category::Players).problem, u"profile-unreadable"_s);
    QCOMPARE(resolver.resolveChoice(u"auto"_s, Category::Other).reason, u"desktop"_s);
    QCOMPARE(resolver.resolveChoice(u"auto"_s, Category::Players).reason, u"unmeasured"_s);
    QCOMPARE(resolver.resolveChoice(u"auto"_s, Category::Browsers, true).reason, u"unmeasured"_s); // 3D needs no profile
    QCOMPARE(resolver.resolveChoice(u"discrete"_s, Category::Browsers).gpuIndex, 1);
    // one GPU: nothing to choose, the profile is not needed
    Resolver one(read({SysfsFixture::intel()}), QString(), unread);
    QCOMPARE(one.resolveChoice(u"profile"_s).reason, u"only-gpu"_s);
}

void ResolverTest::profileRuleSaysAnAbsentKind()
{
    // two discrete GPUs: power saver asks for an integrated GPU there is none of; the rule gives the desktop's GPU and says it
    QList<FixtureGpu> desktop = SysfsFixture::host();
    desktop[0].device = 0x7340; // a discrete AMD in place of the APU
    Resolver resolver(read(desktop), QString(), PowerProfile::PowerSaver);
    const Resolution r = resolver.resolveChoice(u"profile"_s, Category::Players);
    QCOMPARE(r.gpuIndex, resolver.mainIndex());
    QCOMPARE(r.kindAbsent, u"integrated"_s);
    QVERIFY(r.problem.isEmpty());
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
    // no integrated GPU that renders: said, not the main GPU in its place
    QCOMPARE(resolver.resolveChoice(u"integrated"_s).problem, u"kind-missing"_s);
    // the chip that cannot render is never used, and a choice of it says why
    const Resolution bmc = resolver.resolveChoice(u"pci-0000:04:00.0"_s);
    QCOMPARE(bmc.problem, u"gpu-cannot-render"_s);
    QCOMPARE(bmc.requestedIndex, 0);
    QCOMPARE(bmc.gpuIndex, -1);
    Resolver mainOnBmc(read(SysfsFixture::bmc()), u"pci-0000:04:00.0"_s, PowerProfile::PowerSaver);
    QCOMPARE(mainOnBmc.mainProblem().problem, u"gpu-cannot-render"_s);
}

void ResolverTest::aGpuTheAccountMayNotOpenIsNotOffered()
{
    QList<FixtureGpu> machine = SysfsFixture::host();
    machine[1].accessible = false;
    Resolver resolver(read(machine), QString(), PowerProfile::Performance);
    // other programs stay on the desktop's GPU on Automatic
    const Resolution r = resolver.resolveChoice(u"auto"_s);
    QCOMPARE(r.gpuIndex, 0);
    QVERIFY(r.isMain);
    // the discrete GPU chosen, which this account cannot open: said, never the main GPU in its place
    const Resolution discrete = resolver.resolveChoice(u"discrete"_s);
    QCOMPARE(discrete.problem, u"gpu-not-allowed"_s);
    QCOMPARE(discrete.requestedIndex, 1);
    QCOMPARE(resolver.resolveChoice(u"pci-0000:01:00.0"_s).problem, u"gpu-not-allowed"_s);
    QCOMPARE(resolver.usableIndices(), QList<int>{0});
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

    // NVIDIA draws the desktop: glvnd would give a program its EGL and GLX first, so a program sent to the APU names Mesa's
    Resolver nvidiaMain(host, u"pci-0000:01:00.0"_s, PowerProfile::Balanced);
    QCOMPARE(nvidiaMain.resolveChoice(u"integrated"_s).environment,
             (QStringList{u"DRI_PRIME=pci-0000_0b_00_0"_s, u"VK_LOADER_DRIVERS_SELECT=*radeon*"_s,
                          u"__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json"_s, u"__GLX_VENDOR_LIBRARY_NAME=mesa"_s}));
    // the APU draws the desktop: Mesa is already first, nothing more to name
    Resolver apuMain(host, QString(), PowerProfile::Balanced);
    QCOMPARE(apuMain.resolveChoice(u"discrete"_s).environment, Resolver::environmentFor(host[1]));
    QCOMPARE(apuMain.resolveChoice(host[0].id).environment, QStringList());
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

    // KDE's meaning of the key (Desktop Entry Specification: "a more powerful discrete GPU if available"; KIO's
    // gpudetection.cpp): the first discrete GPU, also when the person made it the main GPU, so no variables then
    Resolver nvidiaMain(read(SysfsFixture::host()), u"pci-0000:01:00.0"_s, PowerProfile::Balanced);
    r = nvidiaMain.resolveApp(app, settings);
    QCOMPARE(r.gpuIndex, 1);
    QVERIFY(r.environment.isEmpty());

    // three GPUs: the first discrete one, whichever GPU draws the desktop
    Resolver three(read(SysfsFixture::three()), QString(), PowerProfile::Balanced);
    QCOMPARE(three.resolveApp(app, settings).gpuIndex, 1);
    Resolver threeNvidiaMain(read(SysfsFixture::three()), u"pci-0000:01:00.0"_s, PowerProfile::Balanced);
    QCOMPARE(threeNvidiaMain.resolveApp(app, settings).gpuIndex, 1);
    Resolver threeAmdMain(read(SysfsFixture::three()), u"pci-0000:02:00.0"_s, PowerProfile::Balanced);
    QCOMPARE(threeAmdMain.resolveApp(app, settings).gpuIndex, 1);

    // the default GPU (switcheroo-control's Default: the boot VGA) is discrete: the program stays where it is
    QList<FixtureGpu> desktop = SysfsFixture::host();
    desktop[0].bootVga = false;
    desktop[1].bootVga = true;
    Resolver discreteDefault(read(desktop), QString(), PowerProfile::Balanced);
    r = discreteDefault.resolveApp(app, settings);
    QCOMPARE(r.gpuIndex, discreteDefault.mainIndex());
    QVERIFY(r.environment.isEmpty());
    // two integrated GPUs and no discrete one: the first GPU other than the default
    FixtureGpu carrizo = SysfsFixture::a10()[0];
    carrizo.card = 1;
    carrizo.bootVga = false;
    const QList<Gpu> twoIntegrated = read({SysfsFixture::intel(), carrizo});
    QCOMPARE(twoIntegrated[1].kind, GpuKind::Integrated);
    Resolver integrated(twoIntegrated, QString(), PowerProfile::Balanced);
    QCOMPARE(integrated.resolveApp(app, settings).gpuIndex, 1);

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
    // Browsers and Other are Automatic: on performance a browser on the discrete GPU, other programs on the desktop's
    QCOMPARE(host.resolveCategory(Category::Browsers, settings).gpuIndex, 1);
    QCOMPARE(host.resolveCategory(Category::Other, settings).gpuIndex, 0);
    QCOMPARE(host.resolveCategory(Category::Other, settings).reason, u"desktop"_s);
    Resolver saver(read(SysfsFixture::host()), QString(), PowerProfile::PowerSaver);
    QCOMPARE(saver.resolveCategory(Category::Browsers, settings).gpuIndex, 0);
    QCOMPARE(saver.resolveCategory(Category::Games, settings).gpuIndex, 1);
}

QTEST_GUILESS_MAIN(ResolverTest)
#include "resolvertest.moc"
