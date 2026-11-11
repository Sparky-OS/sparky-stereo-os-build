// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#include "window.h"
#include <KLocalizedString>
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
    void cleanupTestCase()
    {
        qInfo().noquote() << fixture.readAllStandardError();
        fixture.terminate();
        fixture.waitForFinished(3000);
    }
};
QTEST_MAIN(RendererTest)
#include "renderertest.moc"
