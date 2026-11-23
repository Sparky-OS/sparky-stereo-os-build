// SPDX-License-Identifier: GPL-3.0-or-later
#include "camerakcm.h"
#include "packings.h"
#include <KLocalizedContext>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QtTest>

class PreviewRefusalTest : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void actualPage()
    {
        CameraKcm kcm(nullptr, KPluginMetaData());
        QTRY_VERIFY_WITH_TIMEOUT(!kcm.cameras().isEmpty() && kcm.currentNodeId() >= 0, 60000);
        QQmlEngine engine;
        auto *translations = new KLocalizedContext(&engine);
        translations->setTranslationDomain(QStringLiteral("kcm_sparkystereo_camera"));
        engine.rootContext()->setContextObject(translations);
        engine.rootContext()->setContextProperty(QStringLiteral("kcm"), &kcm);
        QQmlComponent component(&engine, QUrl::fromLocalFile(QStringLiteral(CAMERA_QML_PATH)));
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        QScopedPointer<QObject> root(component.create());
        QVERIFY2(root, qPrintable(component.errorString()));
        auto *item = qobject_cast<QQuickItem *>(root.get());
        QVERIFY(item);
        QQuickWindow window;
        window.resize(960, 1000);
        item->setParentItem(window.contentItem());
        item->setSize(QSizeF(960, 1000));
        window.show();
        QVERIFY(QTest::qWaitForWindowExposed(&window));
        auto *button = root->findChild<QQuickItem *>(QStringLiteral("showPair"));
        auto *notice = root->findChild<QQuickItem *>(QStringLiteral("pairRefusal"));
        QVERIFY(button && notice);
        for (const auto &entry : Sparky::Camera::packings()) {
            kcm.setPacking(entry.id);
            const bool offered = entry.id != QStringLiteral("mono");
            QTRY_COMPARE(button->isVisible(), offered);
            QTRY_COMPARE(button->isEnabled(), !entry.videoOutput.isEmpty());
            QTRY_COMPARE(notice->isVisible(), offered && entry.videoOutput.isEmpty());
            if (notice->isVisible())
                QCOMPARE(notice->property("text").toString(), QStringLiteral("This preview cannot show that packing. Other programs can."));
            qInfo().noquote() << entry.id << "expectedRefusal=" << (offered && entry.videoOutput.isEmpty()) << "foundRefusal=" << notice->isVisible();
        }
        item->setParentItem(nullptr);
    }
};
QTEST_MAIN(PreviewRefusalTest)
#include "preview-refusal-test.moc"
