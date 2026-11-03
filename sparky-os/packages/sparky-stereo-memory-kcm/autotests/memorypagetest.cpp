// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#include <KLocalizedString>
#include <KPluginMetaData>
#include <KQuickConfigModule>
#include <KQuickConfigModuleLoader>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTemporaryDir>
#include <QTest>

using namespace Qt::StringLiterals;

class MemoryPageTest : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void zram();
    void presentation_data();
    void presentation();
};

void MemoryPageTest::presentation_data()
{
    QTest::addColumn<QString>("language");
    QTest::addColumn<bool>("record");
    QTest::newRow("en-record") << u"en"_s << true;
    QTest::newRow("pt_BR-record") << u"pt_BR"_s << true;
    QTest::newRow("pt_BR-no-record") << u"pt_BR"_s << false;
}

static QQuickItem *namedItem(QQuickItem *parent, const QString &name)
{
    if (parent->objectName() == name) return parent;
    for (QQuickItem *child : parent->childItems()) {
        if (auto *found = namedItem(child, name)) return found;
    }
    return nullptr;
}

void MemoryPageTest::presentation()
{
    QFETCH(QString, language);
    QFETCH(bool, record);
    QTemporaryDir fixture;
    QVERIFY(fixture.isValid());
    qputenv("SPARKY_STEREO_MEMORY_ROOT", fixture.path().toUtf8());
    qputenv("SPARKY_STEREO_ROOT", fixture.path().toUtf8());
    KLocalizedString::setLanguages({language});
    const auto write = [&](const QString &relative, const QByteArray &text) {
        const QString path = fixture.path() + relative;
        QDir().mkpath(QFileInfo(path).path());
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        QCOMPARE(file.write(text), text.size());
    };
    write(u"/run/cushion-swap/status"_s, "STATE=off\nPROTECTION=no\nPROBLEMS=swapon-failed\nREASON=RAW DAEMON WORDS\n");
    if (record) {
        write(u"/run/sparky-stereo-problems/sparky-stereo-cushion-swap_swapon-failed.json"_s,
              R"({"package":"sparky-stereo-cushion-swap","key":"swapon-failed","message":"LOCAL5","args":["/swap/cushion","test","/swap/cushion"],"severity":"failed","text_en":"Engine text","repair":[["/usr/bin/true"]]})");
    }
    const auto result = KQuickConfigModuleLoader::loadModule(KPluginMetaData(QString::fromUtf8(KCM_PLUGIN)), nullptr);
    QVERIFY2(result.plugin, qPrintable(result.errorString));
    std::unique_ptr<KQuickConfigModule> kcm(result.plugin);
    QQuickItem *page = kcm->mainUi();
    QVERIFY2(page, qPrintable(kcm->errorString()));
    kcm->load();
    QQuickWindow window;
    window.resize(1100, 1100);
    page->setParentItem(window.contentItem());
    page->setSize(QSizeF(1100, 1100));
    window.show();
    QQuickItem *refresh = nullptr;
    QQuickItem *reason = nullptr;
    QTRY_VERIFY((refresh = namedItem(page, u"refreshStatus"_s)));
    QTRY_VERIFY((reason = namedItem(page, u"daemonReason"_s)));
    QTRY_COMPARE(reason->isVisible(), !record);
    if (language == u"pt_BR"_s) {
        QCOMPARE(refresh->property("text").toString(), u"Atualizar estado"_s);
    }
    if (record) {
        QQuickItem *repair = nullptr;
        QTRY_VERIFY((repair = namedItem(page, u"repairProblem"_s)));
        QTRY_VERIFY(repair->mapToScene(QPointF()).y() + repair->height() <= refresh->mapToScene(QPointF()).y());
    } else {
        QCOMPARE(reason->property("text").toString(), u"RAW DAEMON WORDS"_s);
    }
    page->setParentItem(nullptr);
}

void MemoryPageTest::zram()
{
    const QString language = qEnvironmentVariable("TEST_LANGUAGE", u"en"_s);
    KLocalizedString::setLanguages({language});
    const auto result = KQuickConfigModuleLoader::loadModule(KPluginMetaData(
        qEnvironmentVariable("KCM_TEST_PLUGIN", QString::fromUtf8(KCM_PLUGIN))), nullptr);
    QVERIFY2(result.plugin, qPrintable(result.errorString));
    std::unique_ptr<KQuickConfigModule> kcm(result.plugin);
    QQuickItem *page = kcm->mainUi();
    QVERIFY2(page, qPrintable(kcm->errorString()));
    QQuickWindow window;
    window.resize(1100, 1100);
    page->setParentItem(window.contentItem());
    page->setSize(QSizeF(1100, 1100));
    window.show();
    kcm->load();
    QTRY_VERIFY_WITH_TIMEOUT(kcm->property("zram").toMap().value(u"known"_s).toBool(), 15000);
    const bool before = kcm->property("zram").toMap().value(u"installed"_s).toBool();
    if (qEnvironmentVariableIsSet("EXPECT_ZRAM_INSTALLED")) {
        QCOMPARE(before, qEnvironmentVariableIntValue("EXPECT_ZRAM_INSTALLED") != 0);
    }
    if (qEnvironmentVariableIsSet("CHANGE_ZRAM")) {
        QVERIFY(QMetaObject::invokeMethod(kcm.get(), "changeZram"));
        QTRY_VERIFY(kcm->property("zramBusy").toBool());
        QTRY_VERIFY_WITH_TIMEOUT(!kcm->property("zramBusy").toBool(), 120000);
        QTRY_COMPARE_WITH_TIMEOUT(kcm->property("zram").toMap().value(u"installed"_s).toBool(), !before, 15000);
    }
    auto *button = namedItem(page, u"zramAction"_s);
    QVERIFY(button);
    const bool installed = kcm->property("zram").toMap().value(u"installed"_s).toBool();
    const QString expected = language == u"pt_BR"_s ? (installed ? u"Desinstalar"_s : u"Instalar"_s)
                                                   : (installed ? u"Uninstall"_s : u"Install"_s);
    QTRY_COMPARE(button->property("text").toString(), expected);
    if (qEnvironmentVariableIsSet("SCREENSHOT")) {
        QTest::qWait(500);
        QVERIFY(window.grabWindow().save(qEnvironmentVariable("SCREENSHOT")));
    }
    page->setParentItem(nullptr);
}

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    MemoryPageTest test;
    return QTest::qExec(&test, argc, argv);
}
#include "memorypagetest.moc"
