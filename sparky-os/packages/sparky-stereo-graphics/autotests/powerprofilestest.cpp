// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "fixtures.h"
#include "graphicskcm.h"
#include "powerprofiles.h"

#include <KPluginMetaData>

#include <QFile>

using namespace SparkyGraphics;

// Needs a bus with net.hadess.PowerProfiles on DBUS_SYSTEM_BUS_ADDRESS (run by powerprofiles-test.sh, which starts fake-ppd.py).
class PowerProfilesTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase();
    void profileFromTheDaemon();
    void overrideBeatsTheDaemon();
    void onlyGpuActionsAreOffered();
    void actionIsSwitchedThroughTheDaemon();
    void pageShowsAndSavesThem();

private:
    QString state() const
    {
        QFile f(qEnvironmentVariable("PPD_STATE"));
        return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()) : QString();
    }
};

void PowerProfilesTest::initTestCase()
{
    QVERIFY(!qEnvironmentVariableIsEmpty("PPD_STATE"));
    qunsetenv("SPARKY_STEREO_POWER_PROFILE");
}

void PowerProfilesTest::profileFromTheDaemon()
{
    QVERIFY(PowerProfiles::daemonAvailable());
    QVERIFY(PowerProfiles::active() == PowerProfile::Performance); // fake-ppd.py is started on performance
}

void PowerProfilesTest::overrideBeatsTheDaemon()
{
    qputenv("SPARKY_STEREO_POWER_PROFILE", "power-saver");
    QVERIFY(PowerProfiles::active() == PowerProfile::PowerSaver);
    qunsetenv("SPARKY_STEREO_POWER_PROFILE");
}

void PowerProfilesTest::onlyGpuActionsAreOffered()
{
    const QList<PowerAction> actions = PowerProfiles::gpuActions();
    QStringList names;
    for (const PowerAction &action : actions) {
        names << action.name;
    }
    names.sort();
    QCOMPARE(names, (QStringList{u"amdgpu_dpm"_s, u"amdgpu_panel_power"_s}));
    QCOMPARE(actions[0].description, u"Adjust GPU dynamic power management"_s);
    QVERIFY(!actions[0].enabled);
}

void PowerProfilesTest::actionIsSwitchedThroughTheDaemon()
{
    QVERIFY(PowerProfiles::setActionEnabled(u"amdgpu_dpm"_s, true));
    QVERIFY(state().contains(u"amdgpu_dpm=true"_s));
    bool seen = false;
    for (const PowerAction &action : PowerProfiles::gpuActions()) {
        seen |= action.name == u"amdgpu_dpm"_s && action.enabled;
    }
    QVERIFY(seen);
    QVERIFY(!PowerProfiles::setActionEnabled(u"no_such_action"_s, true));
    QVERIFY(PowerProfiles::setActionEnabled(u"amdgpu_dpm"_s, false));
}

void PowerProfilesTest::pageShowsAndSavesThem()
{
    SysfsFixture fixture;
    fixture.add(SysfsFixture::intel());
    QTemporaryDir config;
    qputenv("XDG_CONFIG_HOME", config.path().toUtf8());
    qputenv("XDG_CONFIG_DIRS", config.path().toUtf8());
    qputenv("SPARKY_STEREO_GRAPHICS_ROOT", fixture.root().toUtf8());
    // one GPU: the page still offers the GPU power switches
    GraphicsKcm kcm(nullptr, KPluginMetaData());
    kcm.load();
    QVERIFY(!kcm.multiGpu());
    QCOMPARE(kcm.powerActions().size(), 2);
    kcm.setPowerAction(u"amdgpu_panel_power"_s, true);
    QVERIFY(kcm.needsSave());
    QVERIFY(state().contains(u"amdgpu_panel_power=false"_s)); // not before Apply
    kcm.save();
    QVERIFY(state().contains(u"amdgpu_panel_power=true"_s));
    QVERIFY(kcm.errorText().isEmpty());
    QVERIFY(PowerProfiles::setActionEnabled(u"amdgpu_panel_power"_s, false));
}

QTEST_GUILESS_MAIN(PowerProfilesTest)
#include "powerprofilestest.moc"
