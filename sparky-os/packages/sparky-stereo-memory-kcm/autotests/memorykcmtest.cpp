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
    void saveThroughKAuth();
    void repairThroughPolkit();

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
    write(MemorySettings::cushionConfigPath(), "AREA=/swapfile\n");
    kcm.load();
    QVERIFY(kcm.cushionEnabled());

    write(MemorySettings::cushionConfigPath(), "AREA=/swapfile\nCUSHION_SWAP=\"off\" # by hand\n");
    kcm.load();
    QVERIFY(!kcm.cushionEnabled());

    kcm.load();
    QVERIFY(!kcm.needsSave());
    kcm.setCushionEnabled(true);
    QVERIFY(kcm.needsSave());
}

void MemoryKcmTest::statusShows()
{
    MemoryKcm kcm(nullptr, KPluginMetaData());
    write(MemorySettings::cushionStatusPath(), "STATE=deployed\nMODE=compatibility\nFAST=no\nAREA=/swap/cushion\n");
    kcm.load();
    QCOMPARE(kcm.cushionState(), u"deployed"_s);
    QCOMPARE(kcm.cushionMode(), u"compatibility"_s);
    QCOMPARE(kcm.cushionArea(), u"/swap/cushion"_s);

    QFile::remove(MemorySettings::cushionStatusPath());
    kcm.load();
    QCOMPARE(kcm.cushionState(), u"stopped"_s);
}

void MemoryKcmTest::saveThroughKAuth()
{
    const QString mode = qEnvironmentVariable("SPARKY_KAUTH_TEST");
    if (mode.isEmpty()) {
        QSKIP("needs the KAuth container (run-kauth-test.sh)");
    }
    write(MemorySettings::cushionConfigPath(), "AREA=/swapfile\n");
    const QByteArray cushionBefore = read(MemorySettings::cushionConfigPath());

    MemoryKcm kcm(nullptr, KPluginMetaData());
    kcm.load();
    kcm.setCushionEnabled(false);
    QSignalSpy finished(&kcm, &MemoryKcm::saveFinished);
    kcm.save();
    QVERIFY(finished.wait(20000));

    if (mode == u"deny"_s) {
        QCOMPARE(finished.first().first().toBool(), false);
        QVERIFY(!kcm.errorText().isEmpty());
        QCOMPARE(read(MemorySettings::cushionConfigPath()), cushionBefore);
        QVERIFY(kcm.needsSave());
        return;
    }
    QCOMPARE(finished.first().first().toBool(), true);
    QCOMPARE(read(MemorySettings::cushionConfigPath()), QByteArray("AREA=/swapfile\nCUSHION_SWAP=off\n"));
    QVERIFY(!kcm.cushionEnabled());
    QVERIFY(!kcm.needsSave());
}

void MemoryKcmTest::repairThroughPolkit()
{
    const QString mode = qEnvironmentVariable("SPARKY_KAUTH_TEST");
    if (mode.isEmpty()) {
        QSKIP("needs the authorization container");
    }
    MemoryKcm kcm(nullptr, KPluginMetaData());
    kcm.load();
    const QVariantList problems = kcm.property("cushionProblems").toList();
    QCOMPARE(problems.size(), 1);
    QCOMPARE(problems.first().toMap().value(u"key"_s).toString(), u"order353-test"_s);
    const bool edited = !kcm.cushionEnabled();
    kcm.setCushionEnabled(edited);
    QVERIFY(QMetaObject::invokeMethod(&kcm, "repairProblem", Qt::DirectConnection, Q_ARG(int, 0)));
    QTRY_VERIFY_WITH_TIMEOUT(!kcm.property("repairing").toBool(), 20000);
    const bool allowed = mode == u"allow"_s;
    QVERIFY2(QFile::exists(u"/run/order353-repaired"_s) == allowed, qPrintable(kcm.errorText()));
    QCOMPARE(kcm.errorText().isEmpty(), allowed);
    QCOMPARE(kcm.cushionEnabled(), edited);
    QVERIFY(kcm.needsSave());
    QCOMPARE(QFile::exists(u"/run/sparky-stereo-problems/sparky-stereo-cushion-swap_order353-test.json"_s), !allowed);
}

QTEST_GUILESS_MAIN(MemoryKcmTest)

#include "memorykcmtest.moc"
