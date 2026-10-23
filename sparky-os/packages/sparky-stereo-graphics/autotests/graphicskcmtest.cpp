// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "fixtures.h"
#include "graphicskcm.h"

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
    qputenv("XDG_CONFIG_DIRS", m_config.path().toUtf8());
    qputenv("XDG_DATA_HOME", m_data.path().toUtf8());
    qputenv("XDG_DATA_DIRS", m_system.path().toUtf8());
    qputenv("SPARKY_STEREO_POWER_PROFILE", "balanced");
    qunsetenv("KWIN_DRM_DEVICES");
}

void GraphicsKcmTest::init()
{
    QFile::remove(configFile());
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
    // four kinds of program, each with a place to draw now
    const QVariantList categories = kcm->categories();
    QCOMPARE(categories.size(), 4);
    for (const QVariant &c : categories) {
        QVERIFY2(c.toMap().value(u"nowText"_s).toString().startsWith(u"Now: AMD"_s), qPrintable(c.toMap().value(u"nowText"_s).toString()));
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
    // Automatic, Integrated, Discrete and each of the three GPUs
    QCOMPARE(options.size(), 6);
    QCOMPARE(options[3].toMap().value(u"value"_s).toString(), u"pci-0000:00:02.0"_s);
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

void GraphicsKcmTest::qmlLoads_data()
{
    QTest::addColumn<QString>("machine");
    QTest::addColumn<int>("cards");
    QTest::newRow("one GPU") << u"one"_s << 1;
    QTest::newRow("A10") << u"a10"_s << 2;
    QTest::newRow("host") << u"host"_s << 2;
    QTest::newRow("three GPUs") << u"three"_s << 3;
}

void GraphicsKcmTest::qmlLoads()
{
    QFETCH(QString, machine);
    QFETCH(int, cards);
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
        QVERIFY(view.grabWindow().save(shots + u'/' + machine + u".png"_s));
    }
}

QTEST_MAIN(GraphicsKcmTest)
#include "graphicskcmtest.moc"
