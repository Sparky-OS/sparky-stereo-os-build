// SPDX-License-Identifier: GPL-3.0-or-later
// Which controls are settings (keepRule), the default a driver really holds (effectiveDefault) and the best mode (bestMode, ORDER 682).
// Each keepRule row names the flag or control of the V4L2 specification it follows (VIDIOC_QUERYCTRL, "Control Flags").
#include "v4l2camera.h"
#include <QtTest>
#include <linux/videodev2.h>

using namespace Sparky::Camera;

namespace
{
Control integer(quint32 id, qint64 min, qint64 max, qint64 step, qint64 def, quint32 flags = 0)
{
    Control c;
    c.id = id;
    c.kind = Control::Integer;
    c.minimum = min;
    c.maximum = max;
    c.step = step;
    c.defaultValue = def;
    c.flags = flags;
    c.inactive = flags & V4L2_CTRL_FLAG_INACTIVE;
    c.readOnly = flags & V4L2_CTRL_FLAG_READ_ONLY;
    c.grabbed = flags & V4L2_CTRL_FLAG_GRABBED;
    return c;
}
}

class ControlRulesTest : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void keepRule_data()
    {
        QTest::addColumn<int>("kind");
        QTest::addColumn<quint32>("id");
        QTest::addColumn<qint64>("min");
        QTest::addColumn<qint64>("max");
        QTest::addColumn<quint32>("flags");
        QTest::addColumn<QString>("expected");
        const int I = Control::Integer;
        const quint32 B = V4L2_CID_BRIGHTNESS;
        QTest::newRow("integer with a range") << I << B << qint64(0) << qint64(255) << 0u << "setting";
        QTest::newRow("boolean") << int(Control::Boolean) << quint32(V4L2_CID_AUTO_WHITE_BALANCE) << qint64(0) << qint64(1) << 0u << "setting";
        QTest::newRow("menu") << int(Control::Menu) << quint32(V4L2_CID_EXPOSURE_AUTO) << qint64(0) << qint64(3) << 0u << "setting";
        QTest::newRow("integer menu") << int(Control::IntegerMenu) << B << qint64(0) << qint64(3) << 0u << "setting";
        QTest::newRow("button (V4L2_CTRL_TYPE_BUTTON)") << int(Control::Button) << quint32(V4L2_CID_PAN_RESET) << qint64(0) << qint64(0) << quint32(V4L2_CTRL_FLAG_WRITE_ONLY | V4L2_CTRL_FLAG_EXECUTE_ON_WRITE) << "button";
        QTest::newRow("integer64 or string (kind the page cannot edit)") << int(Control::Other) << B << qint64(0) << qint64(9) << 0u << "not-editable";
        QTest::newRow("V4L2_CTRL_FLAG_HAS_PAYLOAD") << int(Control::Other) << B << qint64(0) << qint64(9) << quint32(V4L2_CTRL_FLAG_HAS_PAYLOAD) << "payload";
        QTest::newRow("V4L2_CTRL_FLAG_DYNAMIC_ARRAY") << int(Control::Other) << B << qint64(0) << qint64(9) << quint32(V4L2_CTRL_FLAG_DYNAMIC_ARRAY | V4L2_CTRL_FLAG_HAS_PAYLOAD) << "payload";
        QTest::newRow("V4L2_CTRL_FLAG_READ_ONLY") << I << B << qint64(0) << qint64(255) << quint32(V4L2_CTRL_FLAG_READ_ONLY) << "read-only";
        QTest::newRow("V4L2_CTRL_FLAG_WRITE_ONLY") << I << B << qint64(0) << qint64(255) << quint32(V4L2_CTRL_FLAG_WRITE_ONLY) << "write-only";
        QTest::newRow("V4L2_CTRL_FLAG_VOLATILE while active") << I << B << qint64(0) << qint64(255) << quint32(V4L2_CTRL_FLAG_VOLATILE) << "volatile";
        QTest::newRow("V4L2_CTRL_FLAG_VOLATILE with INACTIVE (auto cluster in automatic mode)") << I << quint32(V4L2_CID_WHITE_BALANCE_TEMPERATURE) << qint64(2800) << qint64(6500) << quint32(V4L2_CTRL_FLAG_VOLATILE | V4L2_CTRL_FLAG_INACTIVE) << "setting";
        QTest::newRow("V4L2_CTRL_FLAG_INACTIVE (a setting waiting for its governing control)") << I << quint32(V4L2_CID_WHITE_BALANCE_TEMPERATURE) << qint64(2800) << qint64(6500) << quint32(V4L2_CTRL_FLAG_INACTIVE) << "setting";
        QTest::newRow("V4L2_CTRL_FLAG_EXECUTE_ON_WRITE") << I << B << qint64(0) << qint64(255) << quint32(V4L2_CTRL_FLAG_EXECUTE_ON_WRITE) << "action";
        QTest::newRow("V4L2_CTRL_FLAG_GRABBED (temporary: still a setting)") << I << B << qint64(0) << qint64(255) << quint32(V4L2_CTRL_FLAG_GRABBED) << "setting";
        QTest::newRow("V4L2_CTRL_FLAG_UPDATE") << I << B << qint64(0) << qint64(255) << quint32(V4L2_CTRL_FLAG_UPDATE) << "setting";
        QTest::newRow("V4L2_CTRL_FLAG_SLIDER") << I << B << qint64(0) << qint64(255) << quint32(V4L2_CTRL_FLAG_SLIDER) << "setting";
        QTest::newRow("V4L2_CTRL_FLAG_MODIFY_LAYOUT") << I << quint32(V4L2_CID_ROTATE) << qint64(0) << qint64(270) << quint32(V4L2_CTRL_FLAG_MODIFY_LAYOUT) << "setting";
        QTest::newRow("V4L2_CTRL_FLAG_HAS_WHICH_MIN_MAX") << I << B << qint64(0) << qint64(255) << quint32(V4L2_CTRL_FLAG_HAS_WHICH_MIN_MAX) << "setting";
        QTest::newRow("iMac: Iris, Relative 0..0 step 0, readable") << I << quint32(V4L2_CID_IRIS_RELATIVE) << qint64(0) << qint64(0) << 0u << "motion";
        QTest::newRow("V4L2_CID_PAN_RELATIVE") << I << quint32(V4L2_CID_PAN_RELATIVE) << qint64(-100) << qint64(100) << quint32(V4L2_CTRL_FLAG_WRITE_ONLY) << "motion";
        QTest::newRow("V4L2_CID_TILT_RELATIVE") << I << quint32(V4L2_CID_TILT_RELATIVE) << qint64(-100) << qint64(100) << 0u << "motion";
        QTest::newRow("V4L2_CID_FOCUS_RELATIVE") << I << quint32(V4L2_CID_FOCUS_RELATIVE) << qint64(-10) << qint64(10) << 0u << "motion";
        QTest::newRow("V4L2_CID_ZOOM_RELATIVE") << I << quint32(V4L2_CID_ZOOM_RELATIVE) << qint64(-10) << qint64(10) << 0u << "motion";
        QTest::newRow("V4L2_CID_ZOOM_CONTINUOUS") << I << quint32(V4L2_CID_ZOOM_CONTINUOUS) << qint64(-10) << qint64(10) << 0u << "motion";
        QTest::newRow("V4L2_CID_PAN_SPEED") << I << quint32(V4L2_CID_PAN_SPEED) << qint64(-10) << qint64(10) << 0u << "motion";
        QTest::newRow("V4L2_CID_TILT_SPEED") << I << quint32(V4L2_CID_TILT_SPEED) << qint64(-10) << qint64(10) << 0u << "motion";
        QTest::newRow("integer without a range") << I << B << qint64(0) << qint64(0) << 0u << "no-range";
    }
    void keepRule()
    {
        QFETCH(int, kind);
        QFETCH(quint32, id);
        QFETCH(qint64, min);
        QFETCH(qint64, max);
        QFETCH(quint32, flags);
        QFETCH(QString, expected);
        Control c = integer(id, min, max, 1, min, flags);
        c.kind = Control::Kind(kind);
        QCOMPARE(keepName(Sparky::Camera::keepRule(c)), expected);
    }
    void effectiveDefault_data()
    {
        QTest::addColumn<qint64>("min");
        QTest::addColumn<qint64>("max");
        QTest::addColumn<qint64>("step");
        QTest::addColumn<qint64>("def");
        QTest::addColumn<qint64>("expected");
        QTest::newRow("in range") << qint64(0) << qint64(255) << qint64(1) << qint64(128) << qint64(128);
        QTest::newRow("A10 sharpness: default 120 above maximum 100") << qint64(0) << qint64(100) << qint64(1) << qint64(120) << qint64(100);
        QTest::newRow("below minimum") << qint64(10) << qint64(100) << qint64(1) << qint64(0) << qint64(10);
        QTest::newRow("rounded to the step") << qint64(2500) << qint64(6500) << qint64(10) << qint64(4504) << qint64(4500);
        QTest::newRow("rounded up to the step") << qint64(2500) << qint64(6500) << qint64(10) << qint64(4506) << qint64(4510);
    }
    void effectiveDefault()
    {
        QFETCH(qint64, min);
        QFETCH(qint64, max);
        QFETCH(qint64, step);
        QFETCH(qint64, def);
        QFETCH(qint64, expected);
        QCOMPARE(Sparky::Camera::effectiveDefault(integer(V4L2_CID_SHARPNESS, min, max, step, def)), expected);
    }
    void bestMode()
    {
        const QList<ModeCandidate> d{
            {QStringLiteral("YUYV"), false, {640, 480}, 30},
            {QStringLiteral("YUYV"), false, {1280, 720}, 10},
            {QStringLiteral("YUYV"), false, {2592, 1944}, 5},
            {QStringLiteral("MJPG"), true, {1280, 720}, 60},
            {QStringLiteral("MJPG"), true, {1920, 1080}, 30},
            {QStringLiteral("MJPG"), true, {2592, 1944}, 15},
        };
        // resolution first: 2592x1944, then the highest rate there: MJPG at 15 beats YUYV at 5
        auto m = Sparky::Camera::bestMode(d);
        QVERIFY(m);
        QCOMPARE(m->fourcc, QStringLiteral("MJPG"));
        QCOMPARE(m->size.width, 2592);
        QCOMPARE(m->fps, 15.0);
        // a known machine's caveat names the formats that work: the best of those
        m = Sparky::Camera::bestMode(d, {QStringLiteral("YUYV")});
        QCOMPARE(m->fourcc, QStringLiteral("YUYV"));
        QCOMPARE(m->size.width, 2592);
        QCOMPARE(m->fps, 5.0);
        // a caveat that names no format the camera offers chooses nothing
        QVERIFY(!Sparky::Camera::bestMode(d, {QStringLiteral("H264")}));
        // same pixel count: the wider picture; same size and rate: the format that needs no decoding; else the driver's order
        const QList<ModeCandidate> ties{
            {QStringLiteral("MJPG"), true, {960, 960}, 30},
            {QStringLiteral("MJPG"), true, {1280, 720}, 30},
            {QStringLiteral("YUYV"), false, {1280, 720}, 30},
            {QStringLiteral("NV12"), false, {1280, 720}, 30},
        };
        m = Sparky::Camera::bestMode(ties);
        QCOMPARE(m->size.width, 1280);
        QCOMPARE(m->fourcc, QStringLiteral("YUYV"));
        // the A10's camera: 640x480 YUYV at 30 is its largest
        m = Sparky::Camera::bestMode({{QStringLiteral("YUYV"), false, {640, 480}, 30}, {QStringLiteral("YUYV"), false, {160, 120}, 30}, {QStringLiteral("YUYV"), false, {320, 240}, 30}});
        QCOMPARE(m->size.width, 640);
        QVERIFY(!Sparky::Camera::bestMode({}));
    }
};
QTEST_GUILESS_MAIN(ControlRulesTest)
#include "control-rules-test.moc"
