// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "fixtures.h"
#include "graphicskcm.h"
#include "problems.h"

#include <KConfig>
#include <KConfigGroup>
#include <KPluginMetaData>

#include <QDir>
#include <QFile>

// ORDER 346a: the Graphics page says what cannot be used and offers the GPUs that can draw, as the person's explicit
// choice (U24, U52). Written against the page's properties and invokable methods by name, so it builds against an older
// page too and fails there (the red half of the proof).
class PageProblemsTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase();
    void init();
    void aProfileThatCannotBeReadIsSaid();
    void aMissingGpuIsSaidWithTheOthersOffered();
    void theOffersAreTheExplicitChoice();
    void aMissingMainGpuIsSaid();
    void aMeasuredGpuThatIsGoneIsSaid();
    void aProgramThatStoppedAtStartIsListedWithItsButtons();

private:
    std::unique_ptr<GraphicsKcm> page(const QString &machine)
    {
        qputenv("SPARKY_STEREO_GRAPHICS_ROOT", (m_machines.path() + u'/' + machine).toUtf8());
        auto kcm = std::make_unique<GraphicsKcm>(nullptr, KPluginMetaData());
        kcm->load();
        return kcm;
    }
    void write(const QString &group, const char *key, const QString &value)
    {
        KConfig config(m_config.filePath(u"sparky-stereo-graphicsrc"_s), KConfig::SimpleConfig);
        config.group(group).writeEntry(key, value);
        config.sync();
    }
    QByteArray configText() const
    {
        QFile f(m_config.filePath(u"sparky-stereo-graphicsrc"_s));
        return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
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

    QTemporaryDir m_machines;
    QTemporaryDir m_config;
    QTemporaryDir m_state;
    QTemporaryDir m_xdg;
    std::vector<std::unique_ptr<SysfsFixture>> m_fixtures;
};

void PageProblemsTest::initTestCase()
{
    const QStringList names = {u"host"_s, u"a10"_s};
    const QList<QList<FixtureGpu>> machines = {SysfsFixture::host(), SysfsFixture::a10()};
    for (int i = 0; i < names.size(); ++i) {
        auto fixture = std::make_unique<SysfsFixture>();
        for (const FixtureGpu &gpu : machines[i]) {
            fixture->add(gpu);
        }
        QVERIFY(QFile::link(fixture->root(), m_machines.filePath(names[i])));
        m_fixtures.push_back(std::move(fixture));
    }
    qputenv("XDG_CONFIG_HOME", m_config.path().toUtf8());
    qputenv("XDG_CONFIG_DIRS", m_xdg.path().toUtf8());
    qputenv("XDG_STATE_HOME", m_state.path().toUtf8());
    qputenv("XDG_DATA_HOME", m_state.path().toUtf8());
    qputenv("XDG_DATA_DIRS", m_state.path().toUtf8());
    // no system bus: power-profiles-daemon cannot be asked
    qputenv("DBUS_SYSTEM_BUS_ADDRESS", "unix:path=/nonexistent/system-bus");
    qunsetenv("SPARKY_STEREO_POWER_PROFILE");
    qunsetenv("KWIN_DRM_DEVICES");
    // the problems are kept by the edition's one engine (ORDER 350), under a root of the test's own: this build of the
    // page is not an installed package there, and nothing judges it removed
    qputenv("SPARKY_STEREO_ROOT", m_state.path().toUtf8());
}

void PageProblemsTest::init()
{
    QFile::remove(m_config.filePath(u"sparky-stereo-graphicsrc"_s));
    QFile::remove(m_xdg.filePath(u"sparky-stereo-graphicsrc"_s));
    QDir(m_state.path() + u"/sparky-stereo-problems"_s).removeRecursively();
}

void PageProblemsTest::aProfileThatCannotBeReadIsSaid()
{
    // U24: never "Power profile: Balanced" in its place
    auto kcm = page(u"host"_s);
    QVERIFY2(kcm->profileText().contains(u"The power profile could not be read: the system bus cannot be reached."_s), qPrintable(kcm->profileText()));
    const QVariantMap browsers = row(kcm->categories(), u"key"_s, u"Browsers"_s);
    QVERIFY2(browsers.value(u"nowText"_s).toString().contains(u"follows the power profile, and the power profile could not be read"_s),
             qPrintable(browsers.value(u"nowText"_s).toString()));
    // other programs need no profile
    QVERIFY(row(kcm->categories(), u"key"_s, u"Other"_s).value(u"nowText"_s).toString().startsWith(u"Now: "_s));
}

void PageProblemsTest::aMissingGpuIsSaidWithTheOthersOffered()
{
    // U52: said as it is, never "so the main GPU", and the GPUs that can draw are offered
    write(u"Render"_s, "Games", u"pci-0000:09:00.0"_s);
    qputenv("SPARKY_STEREO_POWER_PROFILE", "balanced");
    auto kcm = page(u"host"_s);
    qunsetenv("SPARKY_STEREO_POWER_PROFILE");
    const QVariantMap games = row(kcm->categories(), u"key"_s, u"Games"_s);
    QVERIFY2(games.value(u"nowText"_s).toString().contains(u"The GPU you chose for games, at PCI address 0000:09:00.0, is not in this computer now."_s),
             qPrintable(games.value(u"nowText"_s).toString()));
    QVERIFY(!games.value(u"nowText"_s).toString().contains(u"main GPU"_s));
    const QVariant problems = kcm->property("problems");
    QVERIFY(problems.isValid());
    const QVariantMap problem = row(problems.toList(), u"key"_s, u"games"_s);
    QVERIFY(!problem.isEmpty());
    QStringList offered;
    for (const QVariant &gpu : problem.value(u"gpus"_s).toList()) {
        offered << gpu.toMap().value(u"id"_s).toString();
    }
    QCOMPARE(offered, (QStringList{u"pci-0000:0b:00.0"_s, u"pci-0000:01:00.0"_s}));
    // the page keeps it for the notification, as the launchers do
    QVERIFY(QFile::exists(m_state.path() + u"/sparky-stereo-problems/sparky-stereo-graphics_games.json"_s));
}

void PageProblemsTest::theOffersAreTheExplicitChoice()
{
    write(u"Render"_s, "Games", u"pci-0000:09:00.0"_s);
    qputenv("SPARKY_STEREO_POWER_PROFILE", "balanced");
    auto kcm = page(u"host"_s);
    QVERIFY(QMetaObject::invokeMethod(kcm.get(), "useGpu", Q_ARG(QString, u"games"_s), Q_ARG(QString, u"pci-0000:01:00.0"_s)));
    QVERIFY(kcm->needsSave());
    QCOMPARE(row(kcm->categories(), u"key"_s, u"Games"_s).value(u"choice"_s).toString(), u"pci-0000:01:00.0"_s);
    QVERIFY(configText().contains("Games=pci-0000:09:00.0")); // nothing before Apply
    kcm->save();
    qunsetenv("SPARKY_STEREO_POWER_PROFILE");
    QVERIFY(configText().contains("Games=pci-0000:01:00.0"));
    QVERIFY(!QFile::exists(m_state.path() + u"/sparky-stereo-problems/sparky-stereo-graphics_games.json"_s));
    QVERIFY(row(kcm->property("problems").toList(), u"key"_s, u"games"_s).isEmpty());
}

void PageProblemsTest::aMissingMainGpuIsSaid()
{
    write(u"General"_s, "MainGpu", u"pci-0000:09:00.0"_s);
    qputenv("SPARKY_STEREO_POWER_PROFILE", "balanced");
    auto kcm = page(u"host"_s);
    qunsetenv("SPARKY_STEREO_POWER_PROFILE");
    const QVariantMap problem = row(kcm->property("problems").toList(), u"key"_s, u"main-gpu"_s);
    QVERIFY2(problem.value(u"text"_s).toString().contains(u"The GPU you chose to draw the desktop, at PCI address 0000:09:00.0, is not in this computer now."_s),
             qPrintable(problem.value(u"text"_s).toString()));
    QCOMPARE(problem.value(u"gpus"_s).toList().size(), 2);
    QVERIFY(QMetaObject::invokeMethod(kcm.get(), "useGpu", Q_ARG(QString, u"main-gpu"_s), Q_ARG(QString, u"pci-0000:01:00.0"_s)));
    QCOMPARE(kcm->mainChoice(), u"pci-0000:01:00.0"_s);
}

void PageProblemsTest::aMeasuredGpuThatIsGoneIsSaid()
{
    // the machine's record names a GPU that is not here: said, never "not measured yet"
    QFile record(m_xdg.filePath(u"sparky-stereo-graphicsrc"_s));
    QVERIFY(record.open(QIODevice::WriteOnly));
    record.write("[Measured]\nBestGpu=10de:2504\n");
    record.close();
    qputenv("SPARKY_STEREO_POWER_PROFILE", "balanced");
    auto kcm = page(u"a10"_s);
    qunsetenv("SPARKY_STEREO_POWER_PROFILE");
    QVERIFY2(kcm->measuredText().contains(u"The GPU this computer was measured best on, 10de:2504, is not here now"_s), qPrintable(kcm->measuredText()));
    const QVariantMap players = row(kcm->categories(), u"key"_s, u"Players"_s);
    QVERIFY2(players.value(u"nowText"_s).toString().contains(u"the GPU measured best for this computer is not here now"_s), qPrintable(players.value(u"nowText"_s).toString()));
}

void PageProblemsTest::aProgramThatStoppedAtStartIsListedWithItsButtons()
{
    // ORDER 467: what sparky-stereo-gpu-env --died keeps is on the page, with the engine's own buttons
    using namespace SparkyGraphics;
    const QList<Gpu> gpus = GpuInventory::read(m_machines.path() + u"/host"_s);
    QCOMPARE(gpus.size(), 2);
    int discrete = gpus.at(0).kind == GpuKind::Discrete ? 0 : 1;
    const Problem problem = Problems::fromDeath(u"sparky-browser"_s, u"sparky-browser.desktop"_s, u"Sparky Browser"_s, u"crash"_s, 11, QString(), QString(), discrete, gpus, {1 - discrete});
    QVERIFY(Problems::keep(problem, Problems::userDir()));
    auto kcm = page(u"host"_s);
    const QVariantMap row_ = row(kcm->property("problems").toList(), u"key"_s, u"died-sparky-browser"_s);
    QVERIFY(!row_.isEmpty());
    // the text is the engine's, rendered from the installed catalog; this test has none, so it is the message itself
    QVERIFY2(row_.value(u"text"_s).toString().contains(u"stopped right after it started on "_s), qPrintable(row_.value(u"text"_s).toString()));
    QCOMPARE(row_.value(u"package"_s).toString(), u"sparky-stereo-graphics"_s);
    QStringList ids;
    for (const QVariant &action : row_.value(u"actions"_s).toList()) {
        ids << action.toMap().value(u"id"_s).toString();
    }
    QCOMPARE(ids, (QStringList{u"use:"_s + gpus.at(1 - discrete).id, u"open"_s}));
    QVERIFY(row_.value(u"gpus"_s).toList().isEmpty()); // not a saved choice: no change of a kind's GPU is offered
}

QTEST_GUILESS_MAIN(PageProblemsTest)
#include "pageproblemstest.moc"
