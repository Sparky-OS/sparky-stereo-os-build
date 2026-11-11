// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

// The Problems page of System Settings (ORDER 468) against the engine's real library: the plugin is loaded as System
// Settings loads it, the stores are a fixture under SPARKY_STEREO_ROOT and XDG_STATE_HOME, and each check states what
// the person sees or the engine keeps.

#include <sparky-stereo-problems.h>

#include <KLocalizedString>
#include <KPluginMetaData>
#include <KQuickConfigModule>
#include <KQuickConfigModuleLoader>

#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTemporaryDir>
#include <QTest>

using namespace Qt::StringLiterals;

static QQuickItem *namedItem(QQuickItem *parent, const QString &name)
{
    if (parent->objectName() == name) {
        return parent;
    }
    for (QQuickItem *child : parent->childItems()) {
        if (auto *found = namedItem(child, name)) {
            return found;
        }
    }
    return nullptr;
}

static QQuickItem *visibleNamed(QQuickItem *parent, const QString &name)
{
    if (parent->objectName() == name && parent->isVisible()) {
        return parent;
    }
    for (QQuickItem *child : parent->childItems()) {
        if (auto *found = visibleNamed(child, name)) {
            return found;
        }
    }
    return nullptr;
}

static int countNamed(QQuickItem *parent, const QString &name)
{
    int n = parent->objectName() == name && parent->isVisible() ? 1 : 0;
    for (QQuickItem *child : parent->childItems()) {
        n += countNamed(child, name);
    }
    return n;
}

class ProblemsKcmTest : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void initTestCase();
    void init();
    void cleanup();
    void lists();
    void dismissAndBringBack();
    void dismissalIsTheEngines();
    void followsTheStores();
    void bootProblemAfterReboot();
    void unreadableRecord();
    void repair();
    void presentation_data();
    void presentation();

private:
    void keep(int scope, const char *key, const char *message = "LOCAL4", const char *details = nullptr);
    void load();
    QVariantList list(const char *name) { return m_kcm->property(name).toList(); }
    QString dismissedKey(int i) { return list("dismissed").at(i).toMap().value(u"handle"_s).toString(); }

    QTemporaryDir m_root;
    QTemporaryDir m_state;
    std::unique_ptr<KQuickConfigModule> m_kcm;
};

void ProblemsKcmTest::initTestCase()
{
    QVERIFY(m_root.isValid() && m_state.isValid());
    qputenv("SPARKY_STEREO_ROOT", m_root.path().toUtf8());
    qputenv("XDG_STATE_HOME", m_state.path().toUtf8());
    qputenv("LANGUAGE", "en");
}

void ProblemsKcmTest::init()
{
    QDir(m_root.path()).removeRecursively();
    QDir(m_state.path()).removeRecursively();
    QDir().mkpath(m_root.path() + u"/var/lib/sparky-stereo-problems"_s);
    QDir().mkpath(m_root.path() + u"/run/sparky-stereo-problems"_s);
    QDir().mkpath(m_state.path() + u"/sparky-stereo-problems"_s);
    KLocalizedString::setLanguages({u"en"_s});
}

void ProblemsKcmTest::cleanup()
{
    if (m_kcm && m_kcm->mainUi()) {
        m_kcm->mainUi()->setParentItem(nullptr);
    }
    m_kcm.reset();
}

void ProblemsKcmTest::keep(int scope, const char *key, const char *message, const char *details)
{
    const char *args[] = {"A service", "a.service", "@LOCAL8"};
    QCOMPARE(ssp_keep(scope, "sparky-stereo-problems", key, message, args, 3, details ? details : R"({"repair":[["true"]]})"), 0);
}

void ProblemsKcmTest::load()
{
    const auto result = KQuickConfigModuleLoader::loadModule(KPluginMetaData(QString::fromUtf8(KCM_PLUGIN)), nullptr);
    QVERIFY2(result.plugin, qPrintable(result.errorString));
    m_kcm.reset(result.plugin);
    QVERIFY2(m_kcm->mainUi(), qPrintable(m_kcm->errorString()));
    m_kcm->load();
}

void ProblemsKcmTest::lists()
{
    keep(SSP_MACHINE, "m1");
    keep(SSP_BOOT, "b1.service", "LOCAL4", R"({"repair":[["true"]],"unit":null})");
    keep(SSP_PERSON, "p1", "LOCAL4", R"({"severity":"degraded"})");
    load();
    QCOMPARE(list("current").size(), 3);
    QCOMPARE(list("dismissed").size(), 0);
    QVariantMap first;
    for (const QVariant &v : list("current")) {
        if (v.toMap().value(u"handle"_s) == u"machine/sparky-stereo-problems/m1"_s) {
            first = v.toMap();
        }
    }
    QVERIFY(!first.isEmpty());
    QVERIFY2(first.value(u"text"_s).toString().contains(u"A service"_s), qPrintable(first.value(u"text"_s).toString()));
    QCOMPARE(first.value(u"severity"_s).toString(), u"failed"_s);
    QCOMPARE(first.value(u"severityText"_s).toString(), u"Failed"_s);
    QVERIFY(first.value(u"since"_s).toString().startsWith(u"Since "_s));
    QVERIFY(first.value(u"canRepair"_s).toBool());
    QVERIFY(first.value(u"canDismiss"_s).toBool());
    for (const QVariant &v : list("current")) {
        if (v.toMap().value(u"scope"_s) == u"person"_s) {
            QVERIFY(!v.toMap().value(u"canRepair"_s).toBool());
            QCOMPARE(v.toMap().value(u"severity"_s).toString(), u"degraded"_s);
        }
    }
}

void ProblemsKcmTest::dismissAndBringBack()
{
    keep(SSP_MACHINE, "m1");
    keep(SSP_PERSON, "p1");
    load();
    QCOMPARE(list("current").size(), 2);
    QVERIFY(QMetaObject::invokeMethod(m_kcm.get(), "dismiss", Q_ARG(QString, u"machine/sparky-stereo-problems/m1"_s)));
    QCOMPARE(list("current").size(), 1);
    QCOMPARE(list("dismissed").size(), 1);
    QCOMPARE(dismissedKey(0), u"machine/sparky-stereo-problems/m1"_s);
    QVERIFY(list("dismissed").at(0).toMap().value(u"dismissed"_s).toBool());
    QVERIFY(m_kcm->property("errorText").toString().isEmpty());
    // the problem stays kept, whole, with its repair
    QVERIFY(QFile::exists(m_root.path() + u"/var/lib/sparky-stereo-problems/sparky-stereo-problems_m1.json"_s));
    QVERIFY(list("dismissed").at(0).toMap().value(u"canRepair"_s).toBool());
    QVERIFY(QMetaObject::invokeMethod(m_kcm.get(), "bringBack", Q_ARG(QString, u"machine/sparky-stereo-problems/m1"_s)));
    QCOMPARE(list("current").size(), 2);
    QCOMPARE(list("dismissed").size(), 0);
}

// the page and the notifier share one dismissal: the engine's hide and show
void ProblemsKcmTest::dismissalIsTheEngines()
{
    keep(SSP_MACHINE, "m1");
    load();
    QVERIFY(QMetaObject::invokeMethod(m_kcm.get(), "dismiss", Q_ARG(QString, u"machine/sparky-stereo-problems/m1"_s)));
    char *json = ssp_list_json("sparky-stereo-problems", "en");
    QVERIFY(json);
    const QJsonArray all = QJsonDocument::fromJson(QByteArray(json)).array();
    ssp_free(json);
    QCOMPARE(all.size(), 1);
    QVERIFY(all.at(0).toObject().value(u"hidden"_s).toBool());
    QCOMPARE(ssp_show(SSP_MACHINE, "sparky-stereo-problems", "m1"), 0);
    QTRY_COMPARE(list("current").size(), 1);
    QCOMPARE(list("dismissed").size(), 0);
    QCOMPARE(ssp_hide(SSP_MACHINE, "sparky-stereo-problems", "m1"), 0);
    QTRY_COMPARE(list("dismissed").size(), 1);
}

void ProblemsKcmTest::followsTheStores()
{
    load();
    QCOMPARE(list("current").size(), 0);
    keep(SSP_MACHINE, "m1");
    QTRY_COMPARE(list("current").size(), 1);
    keep(SSP_BOOT, "b1.service");
    QTRY_COMPARE(list("current").size(), 2);
    QCOMPARE(ssp_clear(SSP_MACHINE, "sparky-stereo-problems", "m1"), 0);
    QTRY_COMPARE(list("current").size(), 1);
    QCOMPARE(ssp_hide(SSP_BOOT, "sparky-stereo-problems", "b1.service"), 0);
    QTRY_COMPARE(list("dismissed").size(), 1);
    QCOMPARE(list("current").size(), 0);
}

void ProblemsKcmTest::bootProblemAfterReboot()
{
    keep(SSP_BOOT, "svc.service");
    load();
    QVERIFY(QMetaObject::invokeMethod(m_kcm.get(), "dismiss", Q_ARG(QString, u"boot/sparky-stereo-problems/svc.service"_s)));
    QCOMPARE(list("dismissed").size(), 1);
    // the reboot: this boot's store is gone
    QVERIFY(QFile::remove(m_root.path() + u"/run/sparky-stereo-problems/sparky-stereo-problems_svc.service.json"_s));
    QTRY_COMPARE(list("current").size(), 0);
    QTRY_VERIFY(list("dismissed").size() == 1 && list("dismissed").at(0).toMap().value(u"over"_s).toBool());
    QVERIFY(!list("dismissed").at(0).toMap().value(u"canRepair"_s).toBool());
    // the same service fails the same way at the next boot: dismissed, not current
    keep(SSP_BOOT, "svc.service");
    QTRY_COMPARE(list("current").size(), 0);
    QTRY_VERIFY(!list("dismissed").at(0).toMap().value(u"over"_s).toBool());
    QCOMPARE(list("dismissed").size(), 1);
    // and another failure of it shows
    QVERIFY(QFile::remove(m_root.path() + u"/run/sparky-stereo-problems/sparky-stereo-problems_svc.service.json"_s));
    keep(SSP_BOOT, "svc.service", "LOCAL9");
    QTRY_COMPARE(list("current").size(), 1);
    // bring back what is not happening now
    QVERIFY(QFile::remove(m_root.path() + u"/run/sparky-stereo-problems/sparky-stereo-problems_svc.service.json"_s));
    QTRY_COMPARE(list("current").size(), 0);
    QTRY_VERIFY(list("dismissed").size() == 1 && list("dismissed").at(0).toMap().value(u"over"_s).toBool());
    QVERIFY(QMetaObject::invokeMethod(m_kcm.get(), "bringBack", Q_ARG(QString, dismissedKey(0))));
    QCOMPARE(list("dismissed").size(), 0);
    QCOMPARE(list("current").size(), 0);
}

void ProblemsKcmTest::unreadableRecord()
{
    QFile bad(m_root.path() + u"/var/lib/sparky-stereo-problems/sparky-stereo-problems_bad.json"_s);
    QVERIFY(bad.open(QIODevice::WriteOnly));
    bad.write("not json");
    bad.close();
    load();
    QCOMPARE(list("current").size(), 1);
    const QVariantMap e = list("current").at(0).toMap();
    QVERIFY(!e.value(u"canDismiss"_s).toBool());
    QVERIFY(e.value(u"text"_s).toString().contains(u"not a problem record"_s));
    QVERIFY(QMetaObject::invokeMethod(m_kcm.get(), "dismiss", Q_ARG(QString, e.value(u"handle"_s).toString())));
    QCOMPARE(list("current").size(), 1);
    QCOMPARE(list("dismissed").size(), 0);
}

void ProblemsKcmTest::repair()
{
    keep(SSP_PERSON, "fixable", "LOCAL4", R"({"repair":[["true"]]})");
    keep(SSP_PERSON, "broken", "LOCAL4", R"({"repair":[["sh","-c","echo still broken; exit 3"]]})");
    load();
    QCOMPARE(list("current").size(), 2);
    QVERIFY(QMetaObject::invokeMethod(m_kcm.get(), "repair", Q_ARG(QString, u"person/sparky-stereo-problems/fixable"_s)));
    QTRY_VERIFY(!m_kcm->property("noticeText").toString().isEmpty());
    QTRY_COMPARE(list("current").size(), 1);
    QVERIFY(QMetaObject::invokeMethod(m_kcm.get(), "repair", Q_ARG(QString, u"person/sparky-stereo-problems/broken"_s)));
    QTRY_VERIFY(!m_kcm->property("errorText").toString().isEmpty());
    QVERIFY2(m_kcm->property("errorText").toString().contains(u"still broken"_s), qPrintable(m_kcm->property("errorText").toString()));
    QCOMPARE(list("current").size(), 1);
    QVERIFY(list("current").at(0).toMap().value(u"lastRepair"_s).toString().contains(u"3"_s));
    // a dismissed problem whose repair fails is shown again
    QVERIFY(QMetaObject::invokeMethod(m_kcm.get(), "dismiss", Q_ARG(QString, u"person/sparky-stereo-problems/broken"_s)));
    QCOMPARE(list("dismissed").size(), 1);
    QVERIFY(QMetaObject::invokeMethod(m_kcm.get(), "repair", Q_ARG(QString, u"person/sparky-stereo-problems/broken"_s)));
    QTRY_COMPARE(list("current").size(), 1);
    QCOMPARE(list("dismissed").size(), 0);
}

void ProblemsKcmTest::presentation_data()
{
    QTest::addColumn<QString>("language");
    QTest::addColumn<QString>("dismiss");
    QTest::addColumn<QString>("bringBack");
    QTest::newRow("en") << u"en"_s << u"Dismiss"_s << u"Bring back"_s;
    QTest::newRow("pt_BR") << u"pt_BR"_s << u"Dispensar"_s << u"Trazer de volta"_s;
}

// the page with both lists: its buttons are the person's actions, in the person's language
void ProblemsKcmTest::presentation()
{
    QFETCH(QString, language);
    QFETCH(QString, dismiss);
    QFETCH(QString, bringBack);
    qputenv("LANGUAGE", language.toUtf8());
    KLocalizedString::setLanguages({language});
    keep(SSP_MACHINE, "m1");
    keep(SSP_MACHINE, "m2");
    keep(SSP_PERSON, "p1");
    QCOMPARE(ssp_hide(SSP_MACHINE, "sparky-stereo-problems", "m2"), 0);
    load();
    QQuickWindow window;
    window.resize(1920, 1080);
    QQuickItem *page = m_kcm->mainUi();
    page->setParentItem(window.contentItem());
    page->setSize(QSizeF(1920, 1080));
    window.show();
    QTRY_COMPARE(countNamed(page, u"dismissButton"_s), 2);
    QCOMPARE(countNamed(page, u"bringBackButton"_s), 1);
    QCOMPARE(countNamed(page, u"repairButton"_s), 3);
    QCOMPARE(countNamed(page, u"emptyState"_s), 0);
    QVERIFY(namedItem(page, u"dismissedHeading"_s)->isVisible());
    QQuickItem *d = visibleNamed(page, u"dismissButton"_s);
    QQuickItem *b = visibleNamed(page, u"bringBackButton"_s);
    QVERIFY(d && b);
    QCOMPARE(d->property("text").toString(), dismiss);
    QCOMPARE(b->property("text").toString(), bringBack);
    if (qEnvironmentVariableIsSet("SCREENSHOT")) {
        QTest::qWait(500);
        QVERIFY(window.grabWindow().save(qEnvironmentVariable("SCREENSHOT") + u"-"_s + language + u".png"_s));
    }
    // empty: one placeholder, in plain words
    QCOMPARE(ssp_clear(SSP_MACHINE, "sparky-stereo-problems", "m1"), 0);
    QCOMPARE(ssp_clear(SSP_MACHINE, "sparky-stereo-problems", "m2"), 0);
    QCOMPARE(ssp_clear(SSP_PERSON, "sparky-stereo-problems", "p1"), 0);
    QTRY_COMPARE(countNamed(page, u"emptyState"_s), 1);
    QCOMPARE(countNamed(page, u"dismissButton"_s), 0);
    QCOMPARE(countNamed(page, u"currentHeading"_s), 0);
}

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    ProblemsKcmTest test;
    return QTest::qExec(&test, argc, argv);
}
#include "problemskcmtest.moc"
