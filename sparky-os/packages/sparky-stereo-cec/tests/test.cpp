// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#include "adapter.h"
#include "controller.h"
#include <KScreenDpms/Dpms>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QScreen>
#include <QSignalSpy>
#include <QTest>

class Test : public QObject
{
    Q_OBJECT
private:
    QString root = qEnvironmentVariable("CEC_TEST_ROOT");
    QString command = qEnvironmentVariable("CEC_TEST_COMMAND");
    KScreen::Dpms dpms;
    QList<QPair<QString, bool>> modes;

    void write(const QString &path, const QByteArray &data)
    {
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
        QCOMPARE(file.write(data), data.size());
    }
    QString frames()
    {
        QFile file(qEnvironmentVariable("CEC_TEST_FRAMES"));
        if (!file.open(QIODevice::ReadOnly)) return {};
        return QString::fromLatin1(file.readAll());
    }
    void control(const QString &output, const QString &mode)
    {
        QFile file(qEnvironmentVariable("CEC_TEST_CONTROL"));
        QVERIFY(file.open(QIODevice::WriteOnly));
        const auto data = (output + QLatin1Char(' ') + mode + QLatin1Char('\n')).toLatin1();
        QCOMPARE(file.write(data), data.size());
    }
    AdapterConfig config()
    {
        return {root + QStringLiteral("/devices/cec0"), QStringLiteral("HDMI-A-1"), root + QStringLiteral("/drm/card0-HDMI-A-1/edid"), false};
    }

private Q_SLOTS:
    void initTestCase()
    {
        QVERIFY(QGuiApplication::platformName().startsWith(QStringLiteral("wayland")));
        connect(&dpms, &KScreen::Dpms::modeChanged, this, [this](KScreen::Dpms::Mode mode, QScreen *screen) {
            modes.append({screen->name(), mode == KScreen::Dpms::On});
        });
        QTRY_VERIFY(dpms.isSupported());
        QTRY_COMPARE(QGuiApplication::screens().size(), 2);
        QTRY_VERIFY(modes.size() >= 2);
        QDir().mkpath(root + QStringLiteral("/devices"));
        QDir().mkpath(root + QStringLiteral("/drm/card0-HDMI-A-1"));
        write(config().device, {});
        write(root + QStringLiteral("/drm/card0-HDMI-A-1/status"), "connected\n");
        write(root + QStringLiteral("/drm/card0-HDMI-A-1/connector_id"), "99\n");
        QByteArray edid(256, 0);
        edid.replace(0, 8, QByteArray::fromHex("00ffffffffffff00"));
        edid[18] = 1;
        edid[19] = 4;
        edid[126] = 1;
        edid[128] = 2;
        edid[129] = 3;
        edid[130] = 10;
        edid[132] = 0x65;
        edid[133] = 0x03;
        edid[134] = 0x0c;
        edid[135] = 0;
        edid[136] = 0x10;
        for (int block = 0; block < 2; ++block) {
            uint sum = 0;
            for (int i = 0; i < 127; ++i) sum += uchar(edid[block * 128 + i]);
            edid[block * 128 + 127] = char(0U - sum);
        }
        write(config().edid, edid);
    }
    void init()
    {
        write(qEnvironmentVariable("CEC_TEST_STATE"), "0\n");
        write(qEnvironmentVariable("CEC_TEST_FRAMES"), {});
    }
    void nativeDpms()
    {
        CecController controller(root + QStringLiteral("/devices"), root + QStringLiteral("/drm"), {}, command);
        QSignalSpy sent(&controller, &CecController::transmitted);
        QSignalSpy failed(&controller, &CecController::failed);
        control(QStringLiteral("HDMI-A-1"), QStringLiteral("on"));
        QTest::qWait(100);
        QCOMPARE(frames(), QString());
        control(QStringLiteral("HDMI-A-2"), QStringLiteral("off"));
        QTest::qWait(100);
        QCOMPARE(frames(), QString());
        control(QStringLiteral("HDMI-A-1"), QStringLiteral("off"));
        QTRY_COMPARE(sent.size(), 1);
        QCOMPARE(sent[0][0].toString(), QStringLiteral("HDMI-A-1"));
        QCOMPARE(sent[0][1].toBool(), false);
        QCOMPARE(sent[0][2].toBool(), true);
        QCOMPARE(frames(), QStringLiteral("4036\n"));
        control(QStringLiteral("HDMI-A-1"), QStringLiteral("off"));
        control(QStringLiteral("HDMI-A-1"), QStringLiteral("standby"));
        control(QStringLiteral("HDMI-A-1"), QStringLiteral("suspend"));
        QTest::qWait(100);
        QCOMPARE(sent.size(), 1);
        control(QStringLiteral("HDMI-A-1"), QStringLiteral("on"));
        QTRY_COMPARE(sent.size(), 2);
        QCOMPARE(sent[1][1].toBool(), true);
        QCOMPARE(sent[1][2].toBool(), true);
        QCOMPARE(frames(), QStringLiteral("4036\n4004\n"));
        QCOMPARE(failed.size(), 0);
    }
    void initialOff()
    {
        CecAdapter adapter(config(), command);
        QSignalSpy sent(&adapter, &CecAdapter::transmitted);
        adapter.setScreenOn(false);
        QTRY_COMPARE(sent.size(), 1);
        QCOMPARE(frames(), QStringLiteral("4036\n"));
    }
    void hotplug()
    {
        control(QStringLiteral("HDMI-A-1"), QStringLiteral("on"));
        QTest::qWait(50);
        CecController controller(root + QStringLiteral("/devices"), root + QStringLiteral("/drm"), {}, command);
        QSignalSpy sent(&controller, &CecController::transmitted);
        QTest::qWait(100);
        QCOMPARE(frames(), QString());
        control(QStringLiteral("HDMI-A-1"), QStringLiteral("off"));
        QTRY_COMPARE(sent.size(), 1);
        QVERIFY(QFile::remove(config().device));
        QTest::qWait(100);
        write(config().device, {});
        QTRY_COMPARE(sent.size(), 2);
        QCOMPARE(frames(), QStringLiteral("4036\n4036\n"));
        control(QStringLiteral("HDMI-A-1"), QStringLiteral("on"));
        QTRY_COMPARE(sent.size(), 3);
        QCOMPARE(frames(), QStringLiteral("4036\n4036\n4004\n"));
    }
    void configurePlayback()
    {
        write(qEnvironmentVariable("CEC_TEST_STATE"), "2\n");
        CecAdapter adapter(config(), command);
        QSignalSpy sent(&adapter, &CecAdapter::transmitted);
        adapter.setScreenOn(false);
        QTRY_COMPARE(sent.size(), 1);
        QCOMPARE(sent[0][1].toBool(), true);
        QCOMPARE(frames(), QStringLiteral("4036\n"));
    }
    void usbPhysicalAddress()
    {
        write(qEnvironmentVariable("CEC_TEST_STATE"), "35\n");
        auto device = config();
        device.setPhysicalAddress = true;
        CecAdapter adapter(device, command);
        QSignalSpy sent(&adapter, &CecAdapter::transmitted);
        adapter.setScreenOn(false);
        QTRY_COMPARE(sent.size(), 1);
        QCOMPARE(sent[0][1].toBool(), true);
        QCOMPARE(frames(), QStringLiteral("4036\n"));
    }
    void unavailable_data()
    {
        QTest::addColumn<uint>("flags");
        QTest::newRow("no-transmit") << 4U;
        QTest::newRow("no-logical-address") << 10U;
        QTest::newRow("already-tv-not-playback") << 16U;
        QTest::newRow("disconnected") << 1U;
    }
    void unavailable()
    {
        QFETCH(uint, flags);
        write(qEnvironmentVariable("CEC_TEST_STATE"), QByteArray::number(flags));
        CecAdapter adapter(config(), command);
        QSignalSpy failed(&adapter, &CecAdapter::failed);
        adapter.setScreenOn(false);
        QTRY_COMPARE(failed.size(), 1);
        QCOMPARE(frames(), QString());
    }
    void nackIsFailure()
    {
        write(qEnvironmentVariable("CEC_TEST_STATE"), "64\n");
        CecAdapter adapter(config(), command);
        QSignalSpy sent(&adapter, &CecAdapter::transmitted);
        QSignalSpy failed(&adapter, &CecAdapter::failed);
        adapter.setScreenOn(false);
        QTRY_COMPARE(sent.size(), 1);
        QCOMPARE(sent[0][1].toBool(), false);
        QCOMPARE(failed.size(), 1);
        QCOMPARE(frames(), QStringLiteral("4036\n"));
    }
    void rapidWake()
    {
        write(qEnvironmentVariable("CEC_TEST_STATE"), "128\n");
        CecAdapter adapter(config(), command);
        QSignalSpy sent(&adapter, &CecAdapter::transmitted);
        adapter.setScreenOn(false);
        adapter.setScreenOn(true);
        QTRY_COMPARE(sent.size(), 2);
        QCOMPARE(frames(), QStringLiteral("4036\n4004\n"));
    }
    void missingCommand()
    {
        CecAdapter adapter(config(), QStringLiteral("/missing/cec-ctl"));
        QSignalSpy failed(&adapter, &CecAdapter::failed);
        adapter.setScreenOn(false);
        QTRY_COMPARE(failed.size(), 1);
        QCOMPARE(frames(), QString());
    }
    void discovery()
    {
        const auto devices = root + QStringLiteral("/devices");
        const auto drm = root + QStringLiteral("/drm");
        QCOMPARE(discoverAdapters(devices, drm, {QStringLiteral("HDMI-A-1"), QStringLiteral("HDMI-A-2")}, {}).size(), 1);
        QCOMPARE(discoverAdapters(devices, drm, {QStringLiteral("HDMI-A-2")}, {}).size(), 0);
        QCOMPARE(discoverAdapters(devices, drm, {QStringLiteral("HDMI-A-1"), QStringLiteral("HDMI-A-1")}, {}).size(), 0);
        write(root + QStringLiteral("/drm/card0-HDMI-A-1/connector_id"), "100\n");
        QCOMPARE(discoverAdapters(devices, drm, {QStringLiteral("HDMI-A-1")}, {}).size(), 0);
        write(root + QStringLiteral("/drm/card0-HDMI-A-1/connector_id"), "99\n");
        write(qEnvironmentVariable("CEC_TEST_STATE"), "4\n");
        QCOMPARE(discoverAdapters(devices, drm, {QStringLiteral("HDMI-A-1")}, {}).size(), 0);
        write(qEnvironmentVariable("CEC_TEST_STATE"), "32\n");
        QCOMPARE(discoverAdapters(devices, drm, {QStringLiteral("HDMI-A-1")}, {}).size(), 1);
        write(devices + QStringLiteral("/cec1"), {});
        QCOMPARE(discoverAdapters(devices, drm, {QStringLiteral("HDMI-A-1")}, {}).size(), 0);
        QCOMPARE(discoverAdapters(devices, drm, {QStringLiteral("HDMI-A-1")}, {{QStringLiteral("cec0"), QStringLiteral("HDMI-A-1")}}).size(), 1);
        QVERIFY(QFile::remove(devices + QStringLiteral("/cec1")));
        QVERIFY(QFile::remove(config().device));
        QCOMPARE(discoverAdapters(devices, drm, {QStringLiteral("HDMI-A-1")}, {}).size(), 0);
        write(config().device, {});
    }
};

QTEST_MAIN(Test)
#include "test.moc"
