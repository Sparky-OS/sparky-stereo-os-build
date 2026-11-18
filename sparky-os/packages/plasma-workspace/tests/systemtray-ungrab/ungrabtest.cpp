// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: LGPL-2.0-or-later
// The mouse area of a system tray item after its context menu opened: the menu's popup takes the release, so the area stays pressed and the next press is spent
// clearing it (the right click that does nothing). SystemTray::showPlasmoidMenu() tries to prevent that with the window's mouseGrabberItem(), which is
// ambiguous (null, with a warning) as soon as several pointing devices have been in use (not reproducible with QtTest's synthetic devices; seen in a Plasma login). releaseMouseAreasAround() is the replacement.
#include <QQuickItem>
#include <QQuickView>
#include <QtTest>
#include <private/qquickmousearea_p.h>
#include <qpa/qwindowsysteminterface.h>

// as in applets/systemtray/systemtray.cpp
static void releaseMouseAreasAround(QQuickItem *item)
{
    for (int depth = 0; item && depth < 12; item = item->parentItem(), ++depth) {
        const auto children = item->childItems();
        for (QQuickItem *child : children) {
            if (child->inherits("QQuickMouseArea")) {
                child->ungrabMouse();
            }
        }
    }
}
static void oldHack(QQuickItem *appletInterface)
{
    if (appletInterface->window() && appletInterface->window()->mouseGrabberItem()) {
        appletInterface->window()->mouseGrabberItem()->ungrabMouse();
    }
}

class UngrabTest : public QObject
{
    Q_OBJECT
private:
    QQuickView *makeView(QQuickItem *&area, QQuickItem *&applet)
    {
        auto *view = new QQuickView;
        view->setSource(QUrl::fromLocalFile(QFINDTESTDATA("ungrab.qml")));
        view->resize(200, 100);
        view->show();
        if (!QTest::qWaitForWindowExposed(view)) qFatal("not exposed");
        area = view->rootObject()->findChild<QQuickItem *>(QStringLiteral("area"));
        applet = view->rootObject()->findChild<QQuickItem *>(QStringLiteral("applet"));
        return view;
    }
private Q_SLOTS:
    void initTestCase()
    {
        // a second pointing device, as a laptop's touchpad beside a mouse or the compositor's virtual pointer
        QWindowSystemInterface::registerInputDevice(new QPointingDevice(QStringLiteral("second"), 77, QInputDevice::DeviceType::TouchPad, QPointingDevice::PointerType::Finger,
                                                                      QPointingDevice::Capability::Position, 1, 3));
    }
    void newWayReleasesIt()
    {
        QQuickItem *area = nullptr, *applet = nullptr;
        std::unique_ptr<QQuickView> view(makeView(area, applet));
        QTest::mousePress(view.get(), Qt::RightButton, {}, QPoint(100, 50));
        QVERIFY(area->property("pressed").toBool());
        releaseMouseAreasAround(applet);
        QVERIFY2(!area->property("pressed").toBool(), "the area is released");
        // and the next right press is a press again, not a press spent on clearing the old one
        QSignalSpy spy(area, SIGNAL(pressed(QQuickMouseEvent *)));
        QTest::mousePress(view.get(), Qt::RightButton, {}, QPoint(100, 50));
        QCOMPARE(spy.count(), 1);
    }
};
QTEST_MAIN(UngrabTest)
#include "ungrabtest.moc"
