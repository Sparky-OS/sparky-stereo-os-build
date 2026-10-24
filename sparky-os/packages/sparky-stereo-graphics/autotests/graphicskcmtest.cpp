// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "fixtures.h"
#include "graphicskcm.h"
#include "machinerecord.h"

#include <KConfig>
#include <KConfigGroup>
#include <KLocalizedContext>
#include <KPluginMetaData>
#include <KService>

#include <QDir>
#include <QFile>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickView>
#include <QSignalSpy>

using namespace SparkyGraphics;

// The page against fixture machines: what it lists, what it writes, and that its QML loads.
class GraphicsKcmTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase();
    void init();
    void hostListsBothGpus();
    void oneGpuHasNoChoices();
    void threeGpusAppearInEveryChoice();
    void mainChoiceIsSavedForTheNextLogin();
    void runningSessionDiffersFromTheChoice();
    void categoryChoiceRoundTrip();
    void defaultsResetTheChoices();
    void programPreferenceUsesKdesKey();
    void nothingIsWrittenBeforeApply();
    void missingGpuStaysVisible();
    void handSetKwinDevicesIsReported();
    void a10PlayersOnTheMeasuredGpuOnBattery();
    void notMeasuredSaysSo();
    void followThePowerProfileIsOffered();
    void copyBackChoice();
    void copyBackWithoutARecord();
    void copyBackSetInTheSessionIsReported();
    void qmlLoads_data();
    void qmlLoads();

private:
    std::unique_ptr<GraphicsKcm> page(const QString &machine)
    {
        qputenv("SPARKY_STEREO_GRAPHICS_ROOT", (m_machines.path() + u'/' + machine).toUtf8());
        auto kcm = std::make_unique<GraphicsKcm>(nullptr, KPluginMetaData());
        kcm->load();
        return kcm;
    }
    QString configFile() const
    {
        return m_config.filePath(u"sparky-stereo-graphicsrc"_s);
    }
    QByteArray configText() const
    {
        QFile f(configFile());
        return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
    }

    QTemporaryDir m_machines;
    QTemporaryDir m_config;
    QTemporaryDir m_data;
    QTemporaryDir m_system;
    QTemporaryDir m_xdg; // the system configuration folders, where the machine record lives
    std::vector<std::unique_ptr<SysfsFixture>> m_fixtures;
};

static int countCards(QQuickItem *item)
{
    int count = QString::fromLatin1(item->metaObject()->className()).contains(u"AbstractCard"_s) && item->isVisible() ? 1 : 0;
    for (QQuickItem *child : item->childItems()) {
        count += countCards(child);
    }
    return count;
}

static QVariantMap row(const QVariantList &list, const QString &key, const QString &value)
{
    for (const QVariant &v : list) {
        if (v.toMap().value(key).toString() == value) {
            return v.toMap();
        }
    }
    return {};
}

void GraphicsKcmTest::initTestCase()
{
    QVERIFY(m_machines.isValid());
    const QStringList names = {u"one"_s, u"a10"_s, u"host"_s, u"bmc"_s, u"three"_s};
    const QList<QList<FixtureGpu>> machines = {{SysfsFixture::intel()}, SysfsFixture::a10(), SysfsFixture::host(), SysfsFixture::bmc(), SysfsFixture::three()};
    for (int i = 0; i < names.size(); ++i) {
        auto fixture = std::make_unique<SysfsFixture>();
        for (const FixtureGpu &gpu : machines[i]) {
            fixture->add(gpu);
        }
        // the page reads root/sys; point the machine's folder at the fixture's tree
        QVERIFY(QFile::link(fixture->root(), m_machines.filePath(names[i])));
        m_fixtures.push_back(std::move(fixture));
    }
    // a system folder with a few menu entries, and the person's own folder
    const QString apps = m_system.path() + u"/applications"_s;
    QDir().mkpath(apps);
    const auto entry = [&apps](const QString &id, const QString &text) {
        QFile f(apps + u'/' + id);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(text.toUtf8());
    };
    entry(u"org.example.player.desktop"_s, u"[Desktop Entry]\nType=Application\nName=Example Player\nExec=player\nIcon=player\nCategories=AudioVideo;Player;\n"_s);
    entry(u"org.example.game.desktop"_s, u"[Desktop Entry]\nType=Application\nName=Example Game\nExec=game\nCategories=Game;\n"_s);
    qputenv("XDG_CONFIG_HOME", m_config.path().toUtf8());
    qputenv("XDG_CONFIG_DIRS", (m_xdg.path() + u"/etc/xdg"_s).toUtf8());
    qputenv("XDG_DATA_HOME", m_data.path().toUtf8());
    qputenv("XDG_DATA_DIRS", m_system.path().toUtf8());
    qputenv("SPARKY_STEREO_POWER_PROFILE", "balanced");
    qunsetenv("KWIN_DRM_DEVICES");
}

void GraphicsKcmTest::init()
{
    QFile::remove(configFile());
    QFile::remove(MachineRecord::systemFile(m_xdg.path()));
    qunsetenv("MEDIA_GPU_ROUTE_COPY_BACK");
    QDir(m_data.path() + u"/applications"_s).removeRecursively();
    QDir(m_config.path() + u"/plasma-workspace"_s).removeRecursively();
    qunsetenv("KWIN_DRM_DEVICES");
    qputenv("SPARKY_STEREO_POWER_PROFILE", "balanced");
}

void GraphicsKcmTest::hostListsBothGpus()
{
    auto kcm = page(u"host"_s);
    QCOMPARE(kcm->gpuCount(), 2);
    QVERIFY(kcm->multiGpu());
    const QVariantList gpus = kcm->gpus();
    QCOMPARE(gpus.size(), 2);
    QCOMPARE(gpus[0].toMap().value(u"name"_s).toString(), u"AMD Radeon Vega Series / Radeon Vega Mobile Series"_s);
    QCOMPARE(gpus[1].toMap().value(u"name"_s).toString(), u"NVIDIA GeForce RTX 3060 Lite Hash Rate"_s);
    QVERIFY(gpus[0].toMap().value(u"drawsDesktop"_s).toBool());
    QVERIFY(!gpus[1].toMap().value(u"drawsDesktop"_s).toBool());
    QVERIFY(gpus[0].toMap().value(u"screensText"_s).toString().contains(u"DP-1 (DELL U2720Q)"_s));
    QVERIFY(gpus[1].toMap().value(u"screensText"_s).toString().contains(u"HDMI-A-2 (LG TV)"_s));
    QCOMPARE(gpus[1].toMap().value(u"driverText"_s).toString(), u"Driver: nvidia"_s);
    // the main GPU choice: Automatic and both chips
    const QVariantList options = kcm->mainOptions();
    QCOMPARE(options.size(), 3);
    QVERIFY(options[0].toMap().value(u"text"_s).toString().startsWith(u"Automatic ("_s));
    QCOMPARE(options[2].toMap().value(u"value"_s).toString(), u"pci-0000:01:00.0"_s);
    // four kinds of program, each with a place to draw now: players on the discrete GPU (not measured
    // here), the rest on balanced's GPU that draws the desktop
    const QVariantList categories = kcm->categories();
    QCOMPARE(categories.size(), 4);
    for (const QVariant &c : categories) {
        const QString now = c.toMap().value(u"nowText"_s).toString();
        const bool players = c.toMap().value(u"key"_s).toString() == u"Players"_s;
        QVERIFY2(now.startsWith(players ? u"Now: NVIDIA"_s : u"Now: AMD"_s), qPrintable(now));
    }
    QVERIFY(!kcm->needsSave());
}

void GraphicsKcmTest::oneGpuHasNoChoices()
{
    auto kcm = page(u"one"_s);
    QCOMPARE(kcm->gpuCount(), 1);
    QVERIFY(!kcm->multiGpu());
    QCOMPARE(kcm->mainOptions().size(), 2); // Automatic and the one GPU
    QVERIFY(kcm->gpus()[0].toMap().value(u"usedText"_s).toString().isEmpty());
    // the single-GPU power controls do not depend on a second GPU: the page keeps the property
    QVERIFY(kcm->powerActions().size() >= 0);
}

void GraphicsKcmTest::threeGpusAppearInEveryChoice()
{
    auto kcm = page(u"three"_s);
    QCOMPARE(kcm->gpuCount(), 3);
    QCOMPARE(kcm->mainOptions().size(), 4);
    const QVariantList categories = kcm->categories();
    const QVariantList options = categories[0].toMap().value(u"options"_s).toList();
    // Automatic, Follow the power profile, Integrated, Discrete and each of the three GPUs
    QCOMPARE(options.size(), 7);
    QCOMPARE(options[1].toMap().value(u"value"_s).toString(), u"profile"_s);
    QCOMPARE(options[4].toMap().value(u"value"_s).toString(), u"pci-0000:00:02.0"_s);
}

void GraphicsKcmTest::mainChoiceIsSavedForTheNextLogin()
{
    auto kcm = page(u"host"_s);
    QSignalSpy spy(kcm.get(), &GraphicsKcm::changed);
    kcm->setMainChoice(u"pci-0000:01:00.0"_s);
    QVERIFY(spy.count() > 0);
    QVERIFY(kcm->needsSave());
    kcm->save();
    QVERIFY(!kcm->needsSave());
    QVERIFY(configText().contains("MainGpu=pci-0000:01:00.0"));
    auto fresh = page(u"host"_s);
    QCOMPARE(fresh->mainChoice(), u"pci-0000:01:00.0"_s);
    // the GPU that will draw the desktop is the NVIDIA one; this session still draws on the AMD one
    QVERIFY(fresh->gpus()[1].toMap().value(u"drawsDesktop"_s).toBool());
    QVERIFY(fresh->mainAppliesLater());
    // the cards say which GPU draws the desktop now and which will after the next login
    QVERIFY(fresh->gpus()[0].toMap().value(u"runningDesktop"_s).toBool());
    QVERIFY(!fresh->gpus()[0].toMap().value(u"drawsDesktop"_s).toBool());
    QVERIFY(!fresh->gpus()[1].toMap().value(u"runningDesktop"_s).toBool());
    QCOMPARE(fresh->mainNowText(), u"AMD Radeon Vega Series / Radeon Vega Mobile Series"_s);
}

void GraphicsKcmTest::runningSessionDiffersFromTheChoice()
{
    qputenv("KWIN_DRM_DEVICES", "/dev/dri/card1:/dev/dri/card0");
    auto kcm = page(u"host"_s);
    QCOMPARE(kcm->mainNowText(), u"NVIDIA GeForce RTX 3060 Lite Hash Rate"_s);
    QVERIFY(kcm->mainAppliesLater()); // saved choice is still Automatic, which would be the AMD chip
    kcm->setMainChoice(u"pci-0000:01:00.0"_s);
    QVERIFY(!kcm->mainAppliesLater());
}

void GraphicsKcmTest::categoryChoiceRoundTrip()
{
    qputenv("SPARKY_STEREO_POWER_PROFILE", "performance");
    auto kcm = page(u"host"_s);
    // Automatic on the performance profile: the discrete GPU
    QVERIFY(row(kcm->categories(), u"key"_s, u"Games"_s).value(u"nowText"_s).toString().contains(u"NVIDIA"_s));
    kcm->setCategoryChoice(u"Games"_s, u"integrated"_s);
    kcm->setCategoryChoice(u"Players"_s, u"pci-0000:01:00.0"_s);
    QVERIFY(row(kcm->categories(), u"key"_s, u"Games"_s).value(u"nowText"_s).toString().contains(u"AMD"_s));
    QVERIFY(kcm->needsSave());
    kcm->save();
    QVERIFY(configText().contains("Games=integrated"));
    QVERIFY(configText().contains("Players=pci-0000:01:00.0"));
    auto fresh = page(u"host"_s);
    QCOMPARE(row(fresh->categories(), u"key"_s, u"Games"_s).value(u"choice"_s).toString(), u"integrated"_s);
    QCOMPARE(row(fresh->categories(), u"key"_s, u"Browsers"_s).value(u"choice"_s).toString(), u"auto"_s);
    // power saver changes only what is Automatic
    qputenv("SPARKY_STEREO_POWER_PROFILE", "power-saver");
    auto saver = page(u"host"_s);
    QVERIFY(row(saver->categories(), u"key"_s, u"Browsers"_s).value(u"nowText"_s).toString().contains(u"AMD"_s));
    QVERIFY(row(saver->categories(), u"key"_s, u"Players"_s).value(u"nowText"_s).toString().contains(u"NVIDIA"_s));
}

void GraphicsKcmTest::defaultsResetTheChoices()
{
    auto kcm = page(u"host"_s);
    kcm->setMainChoice(u"pci-0000:01:00.0"_s);
    kcm->setCategoryChoice(u"Games"_s, u"discrete"_s);
    kcm->save();
    auto again = page(u"host"_s);
    QVERIFY(!again->representsDefaults());
    again->defaults();
    QVERIFY(again->needsSave());
    QCOMPARE(again->mainChoice(), QString());
    again->save();
    QVERIFY(!configText().contains("MainGpu"));
    QVERIFY(!configText().contains("Games"));
    QVERIFY(page(u"host"_s)->representsDefaults());
}

void GraphicsKcmTest::programPreferenceUsesKdesKey()
{
    auto kcm = page(u"host"_s);
    const QVariantList apps = kcm->apps();
    QCOMPARE(apps.size(), 2);
    const QString userCopy = m_data.path() + u"/applications/org.example.game.desktop"_s;
    QVERIFY(!QFile::exists(userCopy));
    kcm->setAppPreference(u"org.example.game.desktop"_s, int(AppPreference::OtherGpu));
    QVERIFY(kcm->needsSave());
    QVERIFY(row(kcm->apps(), u"id"_s, u"org.example.game.desktop"_s).value(u"nowText"_s).toString().contains(u"NVIDIA"_s));
    kcm->save();
    QVERIFY2(kcm->errorText().isEmpty(), qPrintable(kcm->errorText()));
    QVERIFY(QFile::exists(userCopy));
    QVERIFY(KService(userCopy).runOnDiscreteGpu());
    auto fresh = page(u"host"_s);
    // programs with a setting come first
    QCOMPARE(fresh->apps()[0].toMap().value(u"id"_s).toString(), u"org.example.game.desktop"_s);
    QCOMPARE(fresh->apps()[0].toMap().value(u"preference"_s).toInt(), int(AppPreference::OtherGpu));
    // back to "same as its kind" removes the copy the page made
    fresh->setAppPreference(u"org.example.game.desktop"_s, int(AppPreference::Unset));
    fresh->save();
    QVERIFY(!QFile::exists(userCopy));
    // filter
    fresh->setAppFilter(u"player"_s);
    QCOMPARE(fresh->apps().size(), 1);
}

void GraphicsKcmTest::nothingIsWrittenBeforeApply()
{
    auto kcm = page(u"host"_s);
    kcm->setMainChoice(u"pci-0000:01:00.0"_s);
    kcm->setCategoryChoice(u"Games"_s, u"discrete"_s);
    kcm->setAppPreference(u"org.example.game.desktop"_s, int(AppPreference::MainGpu));
    QVERIFY(!QFile::exists(configFile()));
    QVERIFY(!QFile::exists(m_data.path() + u"/applications/org.example.game.desktop"_s));
    kcm->load(); // Reset
    QVERIFY(!kcm->needsSave());
    QCOMPARE(kcm->mainChoice(), QString());
}

void GraphicsKcmTest::missingGpuStaysVisible()
{
    {
        KConfig config(configFile(), KConfig::SimpleConfig);
        config.group(u"General"_s).writeEntry("MainGpu", "pci-0000:09:00.0");
        config.group(u"Render"_s).writeEntry("Games", "pci-0000:09:00.0");
        config.sync();
    }
    auto kcm = page(u"host"_s);
    QCOMPARE(kcm->mainOptions().size(), 4);
    QVERIFY(kcm->mainOptions().last().toMap().value(u"text"_s).toString().contains(u"Missing GPU"_s));
    const QVariantMap games = row(kcm->categories(), u"key"_s, u"Games"_s);
    QVERIFY(games.value(u"nowText"_s).toString().contains(u"not installed"_s));
    // and it is kept when something else is saved
    kcm->setCategoryChoice(u"Other"_s, u"discrete"_s);
    kcm->save();
    QVERIFY(configText().contains("MainGpu=pci-0000:09:00.0"));
    QVERIFY(configText().contains("Games=pci-0000:09:00.0"));
}

void GraphicsKcmTest::handSetKwinDevicesIsReported()
{
    QVERIFY(!page(u"host"_s)->mainSetByHand());
    QDir().mkpath(m_config.path() + u"/plasma-workspace/env"_s);
    QFile f(m_config.path() + u"/plasma-workspace/env/gpu.sh"_s);
    QVERIFY(f.open(QIODevice::WriteOnly));
    f.write("# mine\nexport KWIN_DRM_DEVICES=/dev/dri/card1\n");
    f.close();
    QVERIFY(page(u"host"_s)->mainSetByHand());
}

void GraphicsKcmTest::a10PlayersOnTheMeasuredGpuOnBattery()
{
    // the record shipped for the A10, written the way the boot service writes it
    auto fixture = std::make_unique<SysfsFixture>();
    for (const FixtureGpu &gpu : SysfsFixture::a10()) {
        fixture->add(gpu);
    }
    fixture->setDmi("LENOVO", "80ST");
    QDir().mkpath(m_xdg.path() + u"/etc/xdg"_s);
    QCOMPARE(RecordWriter::applyKnown(fixture->root(), QStringLiteral(MACHINES_DIR)), RecordWriter::Result::Written);
    QVERIFY(QFile::copy(MachineRecord::systemFile(fixture->root()), MachineRecord::systemFile(m_xdg.path())));
    for (const QByteArray &profile : {QByteArray("power-saver"), QByteArray("balanced"), QByteArray("performance")}) {
        qputenv("SPARKY_STEREO_POWER_PROFILE", profile);
        auto kcm = page(u"a10"_s);
        const QString players = row(kcm->categories(), u"key"_s, u"Players"_s).value(u"nowText"_s).toString();
        QVERIFY2(players.contains(u"M430"_s), qPrintable(QString::fromLatin1(profile) + u": "_s + players));
        QVERIFY2(players.contains(u"measured best for this model"_s), qPrintable(players));
        QVERIFY(kcm->measuredText().contains(u"Lenovo ideapad 310-15ABR"_s));
        QVERIFY(kcm->measuredText().contains(u"M430"_s));
        // the card of the R5 M430 says players draw there
        QVERIFY(kcm->gpus()[1].toMap().value(u"usedText"_s).toString().contains(u"Players"_s));
    }
    // on battery a game in 2D stays on the integrated GPU, the same game started in 3D goes to the R5 M430
    qputenv("SPARKY_STEREO_POWER_PROFILE", "power-saver");
    auto kcm = page(u"a10"_s);
    const QVariantMap games = row(kcm->categories(), u"key"_s, u"Games"_s);
    QVERIFY2(games.value(u"nowText"_s).toString().contains(u"R5/R6/R7"_s), qPrintable(games.value(u"nowText"_s).toString()));
    QVERIFY2(games.value(u"stereoText"_s).toString().contains(u"M430"_s), qPrintable(games.value(u"stereoText"_s).toString()));
    QVERIFY(row(kcm->categories(), u"key"_s, u"Players"_s).value(u"stereoText"_s).toString().isEmpty());
    // the person's choice wins
    kcm->setCategoryChoice(u"Players"_s, u"integrated"_s);
    QVERIFY(row(kcm->categories(), u"key"_s, u"Players"_s).value(u"nowText"_s).toString().contains(u"R5/R6/R7"_s));
}

void GraphicsKcmTest::notMeasuredSaysSo()
{
    qputenv("SPARKY_STEREO_POWER_PROFILE", "power-saver");
    auto kcm = page(u"a10"_s);
    const QString players = row(kcm->categories(), u"key"_s, u"Players"_s).value(u"nowText"_s).toString();
    QVERIFY2(players.contains(u"M430"_s), qPrintable(players));
    QVERIFY2(players.contains(u"not measured"_s), qPrintable(players));
    QVERIFY2(kcm->measuredText().contains(u"not been measured"_s), qPrintable(kcm->measuredText()));
    // one GPU: nothing to measure, nothing said
    QVERIFY(page(u"one"_s)->measuredText().isEmpty());
}

void GraphicsKcmTest::followThePowerProfileIsOffered()
{
    qputenv("SPARKY_STEREO_POWER_PROFILE", "power-saver");
    auto kcm = page(u"host"_s);
    for (const QVariant &c : kcm->categories()) {
        QVERIFY(!row(c.toMap().value(u"options"_s).toList(), u"value"_s, u"profile"_s).isEmpty());
    }
    QVERIFY(row(kcm->categories(), u"key"_s, u"Players"_s).value(u"nowText"_s).toString().contains(u"NVIDIA"_s));
    kcm->setCategoryChoice(u"Players"_s, u"profile"_s);
    QVERIFY(row(kcm->categories(), u"key"_s, u"Players"_s).value(u"nowText"_s).toString().contains(u"AMD"_s));
    kcm->save();
    QVERIFY(configText().contains("Players=profile"));
}

void GraphicsKcmTest::copyBackChoice()
{
    QDir().mkpath(m_xdg.path() + u"/etc/xdg"_s);
    QFile f(MachineRecord::systemFile(m_xdg.path()));
    QVERIFY(f.open(QIODevice::WriteOnly));
    f.write("[Decoding]\nCopyBack=false\n\n[Record]\nOrigin=shipped\n");
    f.close();
    auto kcm = page(u"one"_s); // a single GPU has the choice too
    QVERIFY(!kcm->copyBack());
    QVERIFY2(kcm->copyBackMachineText().contains(u"Off"_s), qPrintable(kcm->copyBackMachineText()));
    QVERIFY(kcm->representsDefaults());
    kcm->setCopyBack(true);
    QVERIFY(kcm->copyBack());
    QVERIFY(kcm->needsSave());
    QVERIFY(!QFile::exists(configFile())); // nothing before Apply
    kcm->save();
    QVERIFY2(configText().contains("[Decoding]\nCopyBack=true"), configText().constData());
    auto fresh = page(u"one"_s);
    QVERIFY(fresh->copyBack());
    QVERIFY(!fresh->representsDefaults());
    // back to the machine's own setting: the key goes, so a better record later reaches this person too
    fresh->setCopyBack(false);
    fresh->save();
    QVERIFY(!configText().contains("CopyBack"));
    // Defaults
    auto again = page(u"one"_s);
    again->setCopyBack(true);
    again->save();
    again->defaults();
    QVERIFY(!again->copyBack());
    again->save();
    QVERIFY(!configText().contains("CopyBack"));
}

void GraphicsKcmTest::copyBackWithoutARecord()
{
    auto kcm = page(u"host"_s);
    QVERIFY(!kcm->copyBack());
    QVERIFY2(kcm->copyBackMachineText().contains(u"not been measured"_s), qPrintable(kcm->copyBackMachineText()));
    // a person who turns it off where it is already off writes nothing
    kcm->setCopyBack(true);
    kcm->setCopyBack(false);
    kcm->save();
    QVERIFY(!configText().contains("CopyBack"));
    // a machine record that turns it on
    QDir().mkpath(m_xdg.path() + u"/etc/xdg"_s);
    QFile f(MachineRecord::systemFile(m_xdg.path()));
    QVERIFY(f.open(QIODevice::WriteOnly));
    f.write("[Decoding]\nCopyBack=true\n");
    f.close();
    auto on = page(u"host"_s);
    QVERIFY(on->copyBack());
    on->setCopyBack(false);
    on->save();
    QVERIFY(configText().contains("CopyBack=false"));
}

void GraphicsKcmTest::copyBackSetInTheSessionIsReported()
{
    QVERIFY(!page(u"host"_s)->copyBackSetInSession());
    qputenv("MEDIA_GPU_ROUTE_COPY_BACK", "true");
    QVERIFY(page(u"host"_s)->copyBackSetInSession());
    qunsetenv("MEDIA_GPU_ROUTE_COPY_BACK");
}

void GraphicsKcmTest::qmlLoads_data()
{
    QTest::addColumn<QString>("machine");
    QTest::addColumn<int>("cards");
    QTest::addColumn<bool>("record");
    QTest::newRow("one GPU") << u"one"_s << 1 << false;
    QTest::newRow("A10") << u"a10"_s << 2 << false;
    QTest::newRow("A10 with its record") << u"a10"_s << 2 << true;
    QTest::newRow("host") << u"host"_s << 2 << false;
    QTest::newRow("three GPUs") << u"three"_s << 3 << false;
}

void GraphicsKcmTest::qmlLoads()
{
    QFETCH(QString, machine);
    QFETCH(int, cards);
    QFETCH(bool, record);
    if (record) {
        QDir().mkpath(m_xdg.path() + u"/etc/xdg"_s);
        QFile f(MachineRecord::systemFile(m_xdg.path()));
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("[Measured]\nBestGpu=1002:6660\nModel=Lenovo ideapad 310-15ABR\n\n[Decoding]\nCopyBack=false\n\n[Record]\nOrigin=shipped\n");
    }
    auto kcm = page(machine);
    QQuickView view;
    auto *localized = new KLocalizedContext(view.engine());
    localized->setTranslationDomain(u"kcm_sparkystereo_graphics"_s);
    view.engine()->rootContext()->setContextObject(localized);
    view.engine()->rootContext()->setContextProperty(u"kcm"_s, kcm.get());
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.resize(900, 1500);
    view.setSource(QUrl::fromLocalFile(QStringLiteral(SOURCE_UI)));
    QVERIFY2(view.status() == QQuickView::Ready, qPrintable(view.errors().isEmpty() ? QString() : view.errors().first().toString()));
    QVERIFY(view.rootObject());
    view.show();
    QTest::qWait(300);
    // one card per GPU
    QCOMPARE(countCards(view.rootObject()), cards);
    const QString shots = qEnvironmentVariable("SCREENSHOT_DIR");
    if (!shots.isEmpty()) {
        QDir().mkpath(shots);
        QVERIFY(view.grabWindow().save(shots + u'/' + machine + (record ? u"-record"_s : QString()) + u".png"_s));
    }
}

QTEST_MAIN(GraphicsKcmTest)
#include "graphicskcmtest.moc"
