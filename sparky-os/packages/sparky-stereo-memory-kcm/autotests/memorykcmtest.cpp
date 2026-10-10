// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "memorykcm.h"
#include "memorysettings.h"

#include <KPluginMetaData>

#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QTest>

using namespace Qt::StringLiterals;

// The page and the files agree: a hand edit shows in the page, and the page
// writes through KAuth (SPARKY_KAUTH_TEST=allow or deny, in the container
// that run-kauth-test.sh prepares).
class MemoryKcmTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase();
    void handEditShows();
    void statusShows();
    void automaticExplained();
    void saveThroughKAuth();

private:
    static void write(const QString &path, const QByteArray &text);
    static QByteArray read(const QString &path);
};

void MemoryKcmTest::write(const QString &path, const QByteArray &text)
{
    QDir().mkpath(path.section(u'/', 0, -2));
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly));
    file.write(text);
}

QByteArray MemoryKcmTest::read(const QString &path)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
}

void MemoryKcmTest::initTestCase()
{
    if (qEnvironmentVariableIsEmpty("SPARKY_KAUTH_TEST")) {
        QVERIFY(!qEnvironmentVariableIsEmpty("SPARKY_STEREO_MEMORY_ROOT"));
    }
}

void MemoryKcmTest::handEditShows()
{
    MemoryKcm kcm(nullptr, KPluginMetaData());
    QFile::remove(MemorySettings::zramConfigPath());
    write(MemorySettings::cushionConfigPath(), "AREA=/swapfile\n");
    kcm.load();
    QCOMPARE(kcm.zramMode(), int(MemoryKcm::Automatic));
    QVERIFY(kcm.cushionEnabled());

    write(MemorySettings::zramConfigPath(), "# the user's own line\nZRAM=on\n");
    write(MemorySettings::cushionConfigPath(), "AREA=/swapfile\nCUSHION_SWAP=\"off\" # by hand\n");
    kcm.load();
    QCOMPARE(kcm.zramMode(), int(MemoryKcm::On));
    QVERIFY(!kcm.cushionEnabled());

    write(MemorySettings::zramConfigPath(), "ZRAM=off\n");
    kcm.load();
    QCOMPARE(kcm.zramMode(), int(MemoryKcm::Off));
    QVERIFY(!kcm.needsSave());
    kcm.setZramMode(MemoryKcm::Automatic);
    QVERIFY(kcm.needsSave());
}

void MemoryKcmTest::statusShows()
{
    MemoryKcm kcm(nullptr, KPluginMetaData());
    write(MemorySettings::cushionStatusPath(), "STATE=deployed\nMODE=compatibility\nFAST=no\nAREA=/swap/cushion\n");
    write(MemorySettings::swapsPath(), "Filename Type Size Used Priority\n/dev/zram0 partition 4194300 0 100\n");
    kcm.load();
    QCOMPARE(kcm.cushionState(), u"deployed"_s);
    QCOMPARE(kcm.cushionMode(), u"compatibility"_s);
    QCOMPARE(kcm.cushionArea(), u"/swap/cushion"_s);
    QVERIFY(kcm.zramActive());

    QFile::remove(MemorySettings::cushionStatusPath());
    write(MemorySettings::swapsPath(), "Filename Type Size Used Priority\n");
    kcm.load();
    QCOMPARE(kcm.cushionState(), u"stopped"_s);
    QVERIFY(!kcm.zramActive());
}

void MemoryKcmTest::automaticExplained()
{
    // zram-auto itself, with sysfs and meminfo fixtures from the environment
    if (!QFile::exists(MemorySettings::zramAutoPath())) {
        QSKIP("zram-auto is not installed under the test root");
    }
    MemoryKcm kcm(nullptr, KPluginMetaData());
    write(MemorySettings::zramConfigPath(), "ZRAM=on\n");
    kcm.load();
    QCOMPARE(kcm.autoZramOn(), qEnvironmentVariable("EXPECT_AUTO") == u"on"_s);
    QCOMPARE(kcm.autoReason(), qEnvironmentVariable("EXPECT_REASON"));
    QCOMPARE(kcm.zramMode(), int(MemoryKcm::On));
}

void MemoryKcmTest::saveThroughKAuth()
{
    const QString mode = qEnvironmentVariable("SPARKY_KAUTH_TEST");
    if (mode.isEmpty()) {
        QSKIP("needs the KAuth container (run-kauth-test.sh)");
    }
    write(MemorySettings::zramConfigPath(), "# kept\nZRAM=auto\n");
    write(MemorySettings::cushionConfigPath(), "AREA=/swapfile\n");
    const QByteArray zramBefore = read(MemorySettings::zramConfigPath());
    const QByteArray cushionBefore = read(MemorySettings::cushionConfigPath());

    MemoryKcm kcm(nullptr, KPluginMetaData());
    kcm.load();
    kcm.setZramMode(MemoryKcm::On);
    kcm.setCushionEnabled(false);
    QSignalSpy finished(&kcm, &MemoryKcm::saveFinished);
    kcm.save();
    QVERIFY(finished.wait(20000));

    if (mode == u"deny"_s) {
        QCOMPARE(finished.first().first().toBool(), false);
        QVERIFY(!kcm.errorText().isEmpty());
        QCOMPARE(read(MemorySettings::zramConfigPath()), zramBefore);
        QCOMPARE(read(MemorySettings::cushionConfigPath()), cushionBefore);
        QVERIFY(kcm.needsSave());
        return;
    }
    QCOMPARE(finished.first().first().toBool(), true);
    QCOMPARE(read(MemorySettings::zramConfigPath()), QByteArray("# kept\nZRAM=on\n"));
    QCOMPARE(read(MemorySettings::cushionConfigPath()), QByteArray("AREA=/swapfile\nCUSHION_SWAP=off\n"));
    QCOMPARE(kcm.zramMode(), int(MemoryKcm::On));
    QVERIFY(!kcm.cushionEnabled());
    QVERIFY(!kcm.needsSave());
}

QTEST_GUILESS_MAIN(MemoryKcmTest)

#include "memorykcmtest.moc"
