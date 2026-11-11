// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#include "window.h"
#include <KLocalizedString>
#include <Purpose/AlternativesModel>
#include <Purpose/Configuration>
#include <Purpose/Job>
#include <KFileItemActions>
#include <KFileItemListProperties>
#include <QMenu>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QFile>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QProcess>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

class RendererTest : public QObject
{
    Q_OBJECT
    QProcess fixture;
    QTemporaryDir home;
    QString clip;
    QByteArray get(const QString &path)
    {
        QNetworkAccessManager network;
        auto reply = network.get(QNetworkRequest(QUrl(QStringLiteral("http://127.0.0.1:19494") + path)));
        QSignalSpy spy(reply, &QNetworkReply::finished);
        if (!spy.wait(3000))
            return {};
        return reply->readAll();
    }
    QStringList mprisNames()
    {
        QStringList found;
        for (const auto &n : QDBusConnection::sessionBus().interface()->registeredServiceNames().value())
            if (n.startsWith(QLatin1String("org.mpris.MediaPlayer2.ums_renderer_")))
                found << n;
        return found;
    }
    void select(Window &window, int index = 0)
    {
        auto combo = window.findChild<QComboBox *>(QStringLiteral("devices"));
        QVERIFY(combo && combo->count() > index);
        combo->setCurrentIndex(index);
        QVERIFY(QMetaObject::invokeMethod(combo, "activated", Qt::DirectConnection, Q_ARG(int, index)));
        QVERIFY2(window.findChild<QLabel *>(QStringLiteral("error"))->text().isEmpty(),
                 qPrintable(window.findChild<QLabel *>(QStringLiteral("error"))->text()));
    }
    void python(const QString &mode)
    {
        QProcess process;
        process.start(QStringLiteral("python3"), {QStringLiteral(TEST_SOURCE_DIR "/mpris-client.py"), mode});
        QTRY_VERIFY_WITH_TIMEOUT(process.state() == QProcess::NotRunning, 15000);
        QVERIFY2(process.exitCode() == 0, process.readAllStandardError().constData());
        QVERIFY2(process.readAllStandardError().isEmpty(), "MPRIS client stderr");
    }
private Q_SLOTS:
    void initTestCase()
    {
        KLocalizedString::setApplicationDomain("kcm_ums");
        qputenv("UMS_PROFILE", home.path().toUtf8());
        QDir().mkpath(home.path() + QStringLiteral("/media"));
        clip = home.path() + QStringLiteral("/media/clip.mkv");
        QFile media(clip);
        QVERIFY(media.open(QIODevice::WriteOnly));
        media.write("fixture");
        media.close();
        QFile config(home.path() + QStringLiteral("/SHARED.conf"));
        QVERIFY(config.open(QIODevice::WriteOnly));
        config.write(QJsonDocument(QJsonArray{QJsonObject{{QStringLiteral("file"), QString(home.path() + QStringLiteral("/media"))},
                                                          {QStringLiteral("active"), true},
                                                          {QStringLiteral("type"), QStringLiteral("Folder")}}})
                         .toJson());
        config.close();
        fixture.start(QStringLiteral("python3"), {QStringLiteral(TEST_SOURCE_DIR "/devices.py")});
        QVERIFY(fixture.waitForReadyRead(5000));
        QCOMPARE(fixture.readAllStandardOutput().trimmed(), QByteArray("READY"));
    }
    void selectedRendererAndMprisControl()
    {
        Window window(QUrl(QStringLiteral("http://127.0.0.1:19494")));
        window.Open(QStringLiteral("headset"), QUrl::fromLocalFile(clip).toString());
        auto combo = window.findChild<QComboBox *>(QStringLiteral("devices"));
        QCOMPARE(combo->count(), 1);
        QCOMPARE(combo->currentIndex(), -1);
        select(window);
        window.findChild<QPushButton *>(QStringLiteral("send"))->click();
        QVERIFY2(window.findChild<QLabel *>(QStringLiteral("error"))->text().isEmpty(),
                 qPrintable(window.findChild<QLabel *>(QStringLiteral("error"))->text()));
        python(QStringLiteral("controls"));
        auto records = QJsonDocument::fromJson(get(QStringLiteral("/records"))).object();
        auto state = records.value(QStringLiteral("states")).toObject().value(QStringLiteral("1")).toObject();
        QCOMPARE(state.value(QStringLiteral("volume")).toInt(), 57);
        QVERIFY(state.value(QStringLiteral("uri")).toString().contains(QLatin1String("renderer-1")));
        window.findChild<QPushButton *>(QStringLiteral("refresh"))->click();
        QVERIFY(mprisNames().isEmpty());
        QVERIFY(!window.findChild<QPushButton *>(QStringLiteral("send"))->isEnabled());
    }
    void unsupportedActionsAndTargetChange()
    {
        Window window(QUrl(QStringLiteral("http://127.0.0.1:19494")));
        window.Open(QStringLiteral("tv"), {});
        QCOMPARE(window.findChild<QComboBox *>(QStringLiteral("devices"))->count(), 2);
        select(window, 1);
        QVERIFY(!window.findChild<QPushButton *>(QStringLiteral("pause"))->isEnabled());
        QVERIFY(!window.findChild<QPushButton *>(QStringLiteral("forward"))->isEnabled());
        python(QStringLiteral("limited"));
        window.Open(QStringLiteral("headset"), {});
        QVERIFY(mprisNames().isEmpty());
    }
    void unsharedAndAmbiguousFilesAreNotSent()
    {
        Window window(QUrl(QStringLiteral("http://127.0.0.1:19494")));
        QFile outside(home.path() + QStringLiteral("/outside.mkv"));
        QVERIFY(outside.open(QIODevice::WriteOnly));
        outside.close();
        window.Open(QStringLiteral("headset"), QUrl::fromLocalFile(outside.fileName()).toString());
        select(window);
        window.findChild<QPushButton *>(QStringLiteral("send"))->click();
        QVERIFY(window.findChild<QLabel *>(QStringLiteral("error"))->text().contains(QLatin1String("not in a shared folder")));
        get(QStringLiteral("/mode/ambiguous"));
        window.Open(QStringLiteral("headset"), QUrl::fromLocalFile(clip).toString());
        select(window);
        window.findChild<QPushButton *>(QStringLiteral("send"))->click();
        QVERIFY(window.findChild<QLabel *>(QStringLiteral("error"))->text().contains(QLatin1String("uniquely")));
        get(QStringLiteral("/mode/normal"));
    }
    void authenticationIsHonored()
    {
        get(QStringLiteral("/mode/auth"));
        Backend backend(QUrl(QStringLiteral("http://127.0.0.1:19494")));
        QVERIFY_EXCEPTION_THROWN(backend.renderers(), std::runtime_error);
        backend.login(QStringLiteral("proof"), QStringLiteral("proof"));
        QCOMPARE(backend.renderers().size(), 4);
        get(QStringLiteral("/mode/normal"));
    }
    void soapFaultIsAnErrorOnDbus()
    {
        Window window(QUrl(QStringLiteral("http://127.0.0.1:19494")));
        window.Open(QStringLiteral("headset"), {});
        select(window);
        get(QStringLiteral("/mode/fault"));
        python(QStringLiteral("fault"));
        QVERIFY(window.findChild<QLabel *>(QStringLiteral("error"))->text().contains(QLatin1String("701")));
        get(QStringLiteral("/mode/normal"));
    }

    void purposeListsBothActionsAndHandsOffToTheController() {
        Window window(QUrl(QStringLiteral("http://127.0.0.1:19494")));
        auto bus = QDBusConnection::sessionBus();
        QVERIFY(bus.registerService(QStringLiteral("org.sparky.UMS.Controller")));
        QVERIFY(bus.registerObject(QStringLiteral("/Controller"), &window, QDBusConnection::ExportScriptableSlots));
        Purpose::AlternativesModel model;
        model.setPluginType(QStringLiteral("Export"));
        model.setInputData(QJsonObject{{QStringLiteral("urls"), QJsonArray{QUrl::fromLocalFile(clip).toString()}}, {QStringLiteral("mimeType"), QStringLiteral("video/x-matroska")}});
        QSet<QString> found;
        for (int row = 0; row < model.rowCount(); ++row) {
            const auto id = model.data(model.index(row, 0), Purpose::AlternativesModel::PluginIdRole).toString();
            if (id != QLatin1String("ums_headset") && id != QLatin1String("ums_tv")) continue;
            found.insert(id);
            auto config = model.configureJob(row);
            QVERIFY(config && config->isReady());
            auto job = config->createJob();
            QVERIFY(job);
            job->setAutoDelete(false);
            QSignalSpy spy(job, &KJob::result);
            job->start();
            QTRY_COMPARE(spy.count(), 1);
            QCOMPARE(job->error(), 0);
            auto combo = window.findChild<QComboBox *>(QStringLiteral("devices"));
            const int expected = id == QLatin1String("ums_headset") ? 1 : 2;
            QTRY_COMPARE_WITH_TIMEOUT(combo->count(), expected, 5000);
            QCOMPARE(combo->currentIndex(), -1);
            delete job;
        }
        QCOMPARE(found, QSet<QString>({QStringLiteral("ums_headset"), QStringLiteral("ums_tv")}));
        model.setInputData(QJsonObject{{QStringLiteral("urls"), QJsonArray{QStringLiteral("file:///test.txt")}}, {QStringLiteral("mimeType"), QStringLiteral("text/plain")}});
        for (int row = 0; row < model.rowCount(); ++row) QVERIFY(!model.data(model.index(row, 0), Purpose::AlternativesModel::PluginIdRole).toString().startsWith(QLatin1String("ums_")));
        bus.unregisterObject(QStringLiteral("/Controller"));
        bus.unregisterService(QStringLiteral("org.sparky.UMS.Controller"));
    }
    void kioMenuAndTranslations() {
        KFileItem item(QUrl::fromLocalFile(clip), QStringLiteral("video/x-matroska"), 0100644);
        KFileItemActions actions;
        actions.setItemListProperties(KFileItemListProperties(KFileItemList{item}));
        QMenu menu;
        actions.addActionsTo(&menu, KFileItemActions::MenuActionSource::Services);
        QSet<QString> names;
        for (auto a : menu.actions()) names.insert(a->text());
        QVERIFY2(names.contains(QStringLiteral("Play on TV")), qPrintable(QStringList(names.values()).join(QLatin1Char(','))));
        QVERIFY(names.contains(QStringLiteral("Play on the headset")));
        const auto output = qEnvironmentVariable("UMS94_CAPTURES");
        if (!output.isEmpty()) {
            QDir().mkpath(output);
            const QStringList languages{QStringLiteral("en"), QStringLiteral("de"), QStringLiteral("es"), QStringLiteral("fr"), QStringLiteral("pl"), QStringLiteral("pt_BR"), QStringLiteral("ja"), QStringLiteral("ko"), QStringLiteral("zh_CN"), QStringLiteral("zh_TW")};
            for (const auto &language : languages) {
                KLocalizedString::setLanguages({language});
                Window window(QUrl(QStringLiteral("http://127.0.0.1:19494")));
                window.Open(QStringLiteral("headset"), {});
                QVERIFY(QTest::qWaitForWindowExposed(&window));
                if (language != QLatin1String("en")) QVERIFY(window.windowTitle() != QLatin1String("Media Devices"));
                QVERIFY(window.grab().save(output + QLatin1Char('/') + language + QStringLiteral(".png")));
                if (language == QLatin1String("pt_BR") && !qEnvironmentVariableIsEmpty("UMS94_SCREENSHOT_SCRIPT")) {
                    QProcess capture;
                    capture.start(QStringLiteral("python3"), {qEnvironmentVariable("UMS94_SCREENSHOT_SCRIPT"), output + QStringLiteral("/kwin-controller.png")});
                    QTRY_VERIFY_WITH_TIMEOUT(capture.state() == QProcess::NotRunning, 35000);
                    QVERIFY2(capture.exitCode() == 0, capture.readAllStandardError().constData());
                    qInfo().noquote() << capture.readAllStandardOutput();
                }

                QTest::qWait(100);
            }
            KLocalizedString::setLanguages({QStringLiteral("en")});
        }
    }
    void cleanupTestCase()
    {
        const auto records = get(QStringLiteral("/records"));
        if (!qEnvironmentVariableIsEmpty("UMS94_CAPTURES")) {
            QFile evidence(qEnvironmentVariable("UMS94_CAPTURES") + QStringLiteral("/wire-records.json"));
            QVERIFY(evidence.open(QIODevice::WriteOnly)); evidence.write(records);
        }
        qInfo().noquote() << fixture.readAllStandardError();
        fixture.terminate();
        fixture.waitForFinished(3000);
    }
};
QTEST_MAIN(RendererTest)
#include "renderertest.moc"
