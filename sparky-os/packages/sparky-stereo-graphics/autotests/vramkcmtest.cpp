// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#include "fixtures.h"
#include "graphicskcm.h"
#include <sparky-stereo-problems.h>
#include <KLocalizedContext>
#include <KPluginMetaData>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickView>
#include <QSignalSpy>

class VramKcmTest : public QObject {
    Q_OBJECT
private Q_SLOTS:
    void initTestCase();
    void switchWritesThePackageSetting();
    void vramRecordAndItsEngineAction();
private:
    QTemporaryDir m_config;
    QTemporaryDir m_state;
    SysfsFixture m_machine;
    static QByteArray setting() {
        QFile file(u"/etc/default/sparky-stereo-vram-boost"_s);
        return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
    }
};
void VramKcmTest::initTestCase()
{
    for (const auto &gpu : SysfsFixture::host()) {
        m_machine.add(gpu);
    }
    qputenv("SPARKY_STEREO_GRAPHICS_ROOT", m_machine.root().toUtf8());
    qputenv("SPARKY_STEREO_ROOT", m_state.path().toUtf8());
    qputenv("XDG_CONFIG_HOME", m_config.path().toUtf8());
    qputenv("XDG_CONFIG_DIRS", m_config.path().toUtf8());
    qputenv("XDG_STATE_HOME", m_state.path().toUtf8());
    qputenv("SPARKY_STEREO_POWER_PROFILE", "balanced");
}
void VramKcmTest::switchWritesThePackageSetting()
{
    GraphicsKcm kcm(nullptr, KPluginMetaData());
    kcm.load();
    QVERIFY2(kcm.property("vramProtection").isValid(), "The published page has no video memory switch");
    QVERIFY(!kcm.property("vramProtection").toBool());
    QQuickView view;
    auto *localized = new KLocalizedContext(view.engine());
    localized->setTranslationDomain(u"kcm_sparkystereo_graphics"_s);
    view.engine()->rootContext()->setContextObject(localized);
    view.engine()->rootContext()->setContextProperty(u"kcm"_s, &kcm);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.resize(1000, 1500);
    view.setSource(QUrl::fromLocalFile(QStringLiteral(SOURCE_UI)));
    QVERIFY2(view.status() == QQuickView::Ready, qPrintable(view.errors().isEmpty() ? QString() : view.errors().first().toString()));
    view.show();
    QVERIFY(QTest::qWaitForWindowExposed(&view));
    auto *control = view.rootObject()->findChild<QQuickItem *>(u"vramProtectionSwitch"_s);
    QVERIFY(control);
    const QByteArray before = setting();
    const QPointF center = control->mapToScene(QPointF(control->width() / 2, control->height() / 2));
    QTest::mouseClick(&view, Qt::LeftButton, Qt::NoModifier, center.toPoint());
    QTRY_VERIFY(kcm.property("vramProtection").toBool());
    QVERIFY(kcm.needsSave());
    QCOMPARE(setting(), before);
    QSignalSpy finished(&kcm, SIGNAL(saveFinished(bool)));
    kcm.save();
    QVERIFY(finished.wait(20000));
    const bool allowed = qEnvironmentVariable("SPARKY_KAUTH_TEST") != u"deny"_s;
    QCOMPARE(finished.first().first().toBool(), allowed);
    if (allowed) {
        QVERIFY(setting().contains("SPARKY_STEREO_VRAM_BOOST=yes\n"));
        QVERIFY(setting().contains("# a person's comment"));
        QVERIFY(kcm.property("vramProtection").toBool());
        QVERIFY(!kcm.needsSave());
        const QString shots = qEnvironmentVariable("SCREENSHOT_DIR");
        if (!shots.isEmpty()) {
            QVERIFY(view.grabWindow().save(shots + u"/graphics-vram.png"_s));
        }
        kcm.defaults();
        QVERIFY(!kcm.property("vramProtection").toBool());
        finished.clear();
        kcm.save();
        QVERIFY(finished.wait(20000));
        QVERIFY(finished.first().first().toBool());
        QVERIFY(setting().contains("SPARKY_STEREO_VRAM_BOOST=no\n"));
    } else {
        QCOMPARE(setting(), before);
        QVERIFY(kcm.needsSave());
        QVERIFY(!kcm.errorText().isEmpty());
    }
}
void VramKcmTest::vramRecordAndItsEngineAction()
{
    const QByteArray marker = m_state.filePath(u"action-ran"_s).toUtf8();
    const QByteArray details = QJsonDocument(QJsonObject{
        {u"text_en"_s, u"VRAM opt-in has no registered region"_s},
        {u"actions"_s, QJsonArray{QJsonObject{{u"id"_s,u"probe"_s},{u"label"_s,QJsonArray{u"LOCAL7"_s}},
            {u"command"_s,QJsonArray{u"/usr/bin/touch"_s,QString::fromUtf8(marker)}}}}}
    }).toJson(QJsonDocument::Compact);
    QCOMPARE(ssp_keep(SSP_PERSON, "sparky-stereo-vram-boost", "region", "LOCAL6", nullptr, 0, details.constData()), 0);
    GraphicsKcm kcm(nullptr, KPluginMetaData());
    kcm.load();
    QVariantMap found;
    for (const auto &value : kcm.property("problems").toList()) {
        const auto row = value.toMap();
        if (row.value(u"package"_s).toString() == u"sparky-stereo-vram-boost"_s) {
            found = row;
        }
    }
    QVERIFY2(!found.isEmpty(), "The published model omits the VRAM engine record");
    QVERIFY(found.value(u"text"_s).toString().contains(u"VRAM"_s));
    QCOMPARE(found.value(u"actions"_s).toList().size(), 1);
    QVERIFY(!found.value(u"actions"_s).toList().first().toMap().value(u"text"_s).toString().isEmpty());
    QVERIFY(QMetaObject::invokeMethod(&kcm, "runProblemAction", Q_ARG(QString,u"sparky-stereo-vram-boost"_s),
                                    Q_ARG(QString,u"region"_s), Q_ARG(QString,u"probe"_s)));
    QTRY_VERIFY(QFile::exists(QString::fromUtf8(marker)));
    QCOMPARE(ssp_clear(SSP_PERSON,"sparky-stereo-vram-boost","region"), 0);
    for (const auto &value : kcm.property("problems").toList()) {
        QVERIFY(value.toMap().value(u"package"_s).toString() != u"sparky-stereo-vram-boost"_s);
    }
}
QTEST_MAIN(VramKcmTest)
#include "vramkcmtest.moc"
