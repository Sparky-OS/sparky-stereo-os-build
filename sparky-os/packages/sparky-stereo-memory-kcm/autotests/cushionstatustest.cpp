// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "memorykcm.h"
#include "memorysettings.h"
#include <KLocalizedString>
#include <KPluginMetaData>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QProcess>
#include <QTemporaryDir>
#include <QTest>

using namespace Qt::StringLiterals;

class CushionStatusTest : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void init();
    void cleanup();
    void status_data();
    void status();
    void unreadable();
    void engineText();
    void missingProblem();
    void refreshKeepsEdits();
private:
    QTemporaryDir root;
    void writeStatus(const QByteArray &bytes);
};

void CushionStatusTest::init()
{
    QVERIFY(root.isValid());
    qputenv("SPARKY_STEREO_MEMORY_ROOT", root.path().toUtf8());
    qputenv("SPARKY_STEREO_ROOT", root.path().toUtf8());
    qputenv("XDG_STATE_HOME", (root.path() + u"/state"_s).toUtf8());
    KLocalizedString::setLanguages({u"en"_s});
    QVERIFY(QDir().mkpath(root.path() + u"/run/cushion-swap"_s));
}

void CushionStatusTest::cleanup()
{
    QFile::setPermissions(MemorySettings::cushionStatusPath(), QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    QFile::remove(MemorySettings::cushionStatusPath());
    QDir(root.path() + u"/run/sparky-stereo-problems"_s).removeRecursively();
}

void CushionStatusTest::writeStatus(const QByteArray &bytes)
{
    QFile file(MemorySettings::cushionStatusPath());
    QVERIFY(file.open(QIODevice::WriteOnly));
    QCOMPARE(file.write(bytes), bytes.size());
}

void CushionStatusTest::status_data()
{
    QTest::addColumn<QByteArray>("fixture");
    QTest::addColumn<int>("expected");
    QTest::newRow("protected") << QByteArray("STATE=off\nPROTECTION=yes\n") << 0;
    QTest::newRow("protected-with-kept-problem") << QByteArray("STATE=off\nPROTECTION=yes\nPROBLEMS=calibration-failed\n") << 1;
    QTest::newRow("degraded") << QByteArray("STATE=deployed\nPROTECTION=degraded\nPROBLEMS=retract-failed\n") << 1;
    QTest::newRow("not-protected") << QByteArray("STATE=off\nPROTECTION=no\nPROBLEMS=swapon-failed\n") << 2;
    QTest::newRow("not-running") << QByteArray("STATE=stopped\nPROTECTION=no\n") << 3;
    QTest::newRow("disabled") << QByteArray("STATE=disabled\nPROTECTION=no\n") << 3;
    QTest::newRow("dead-pid") << QByteArray("STATE=off\nPROTECTION=yes\nPID=999999999\n") << 3;
    QTest::newRow("missing-status") << QByteArray() << 3;
    QTest::newRow("missing-protection") << QByteArray("STATE=off\n") << 4;
    QTest::newRow("invalid-protection") << QByteArray("STATE=off\nPROTECTION=maybe\n") << 4;
}

void CushionStatusTest::status()
{
    QFETCH(QByteArray, fixture);
    QFETCH(int, expected);
    if (!fixture.isEmpty()) {
        fixture += "MODE=psi\nAREA=/swap/cushion\nREASON=fixture reason\n";
        writeStatus(fixture);
    }
    MemoryKcm kcm(nullptr, KPluginMetaData());
    kcm.load();
    // Dynamic properties keep these tests buildable against 0.1.3 for the red run.
    QCOMPARE(kcm.property("cushionStatus"), QVariant(expected));
    if (!fixture.isEmpty()) {
        QCOMPARE(kcm.cushionMode(), u"psi"_s);
        QCOMPARE(kcm.cushionArea(), u"/swap/cushion"_s);
        QCOMPARE(kcm.property("cushionReason").toString(), u"fixture reason"_s);
    }
    if (expected == 4) {
        QVERIFY(!kcm.property("cushionStatusError").toString().isEmpty());
    }
}

void CushionStatusTest::unreadable()
{
    writeStatus("STATE=off\nPROTECTION=yes\n");
    QVERIFY(QFile::setPermissions(MemorySettings::cushionStatusPath(), {}));
    MemoryKcm kcm(nullptr, KPluginMetaData());
    kcm.load();
    QCOMPARE(kcm.property("cushionStatus"), QVariant(4));
    QVERIFY(kcm.property("cushionStatusError").toString().contains(MemorySettings::cushionStatusPath()));
    QVERIFY(kcm.property("cushionStatusError").toString().contains(u"Permission denied"_s));
    QVERIFY(kcm.cushionState() != u"stopped"_s);
}

void CushionStatusTest::engineText()
{
    const QString dir = root.path() + u"/run/sparky-stereo-problems"_s;
    QVERIFY(QDir().mkpath(dir));
    QFile record(dir + u"/sparky-stereo-cushion-swap_swapon-failed.json"_s);
    QVERIFY(record.open(QIODevice::WriteOnly));
    record.write(R"({"package":"sparky-stereo-cushion-swap","key":"swapon-failed","message":"LOCAL5","args":["/swap/cushion","permission denied"],"severity":"failed","text_en":"A kept English explanation with the next step.","repair":[["/usr/bin/true"]]})");
    record.close();
    writeStatus("STATE=off\nPROTECTION=no\nPROBLEMS=swapon-failed\nREASON=swapon failed\n");
    KLocalizedString::setLanguages({u"pt_BR"_s});
    QProcess engine;
    engine.start(u"/usr/bin/sparky-stereo-problems"_s, {u"list"_s, u"--json"_s, u"--lang"_s, u"pt_BR"_s, u"sparky-stereo-cushion-swap"_s});
    QVERIFY(engine.waitForFinished());
    QCOMPARE(engine.exitCode(), 0);
    const QJsonArray expected = QJsonDocument::fromJson(engine.readAllStandardOutput()).array();
    QCOMPARE(expected.size(), 1);
    QCOMPARE(expected.first().toObject().value(u"lang"_s).toString(), u"pt_BR"_s);
    MemoryKcm kcm(nullptr, KPluginMetaData());
    kcm.load();
    const QVariantList problems = kcm.property("cushionProblems").toList();
    QCOMPARE(problems.size(), 1);
    QCOMPARE(problems.first().toMap().value(u"text"_s), expected.first().toObject().value(u"text"_s).toVariant());
    QCOMPARE(problems.first().toMap().value(u"scope"_s).toString(), u"boot"_s);
    QVERIFY(!problems.first().toMap().value(u"repair"_s).toList().isEmpty());
    QVERIFY(kcm.property("cushionProblemsError").toString().isEmpty());
}

void CushionStatusTest::missingProblem()
{
    writeStatus("STATE=off\nPROTECTION=no\nPROBLEMS=missing-record\n");
    MemoryKcm kcm(nullptr, KPluginMetaData());
    kcm.load();
    QVERIFY(!kcm.property("cushionProblemsError").toString().isEmpty());
}

void CushionStatusTest::refreshKeepsEdits()
{
    writeStatus("STATE=off\nPROTECTION=yes\n");
    MemoryKcm kcm(nullptr, KPluginMetaData());
    kcm.load();
    kcm.setZramMode(MemoryKcm::On);
    kcm.setCushionEnabled(false);
    writeStatus("STATE=off\nPROTECTION=no\n");
    QVERIFY(QMetaObject::invokeMethod(&kcm, "refreshStatus", Qt::DirectConnection));
    QCOMPARE(kcm.property("cushionStatus"), QVariant(2));
    QCOMPARE(kcm.zramMode(), int(MemoryKcm::On));
    QVERIFY(!kcm.cushionEnabled());
    QVERIFY(kcm.needsSave());
}

QTEST_GUILESS_MAIN(CushionStatusTest)
#include "cushionstatustest.moc"
