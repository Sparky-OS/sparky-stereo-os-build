/*
    SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>

#include "../src/umsprofile.h"
#include "../src/umsservice.h"

class UmsProfileTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase();
    void defaultFoldersAreTheUserDirectories();
    void defaultFoldersLeaveOutHome();
    void missingSharedConfShowsTheDefaults();
    void roundTripKeepsOtherEntries();
    void keptFolderKeepsItsFlags();
    void serverNameKeepsTheRestOfTheFile();
    void serverNameWithSpecialCharacters();
    void serverNameLineIsAppendedWhenMissing();
    void serviceCommandsReachSystemctl();
    void serviceFailureIsReported();

private:
    QTemporaryDir m_home;
};

static QByteArray readAll(const QString &path)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
}

static void writeAll(const QString &path, const QByteArray &data)
{
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly));
    file.write(data);
}

void UmsProfileTest::initTestCase()
{
    QVERIFY(m_home.isValid());
    qputenv("HOME", m_home.path().toUtf8());
    qunsetenv("XDG_CONFIG_HOME");
    QDir().mkpath(m_home.path() + QStringLiteral("/.config"));
    writeAll(m_home.path() + QStringLiteral("/.config/user-dirs.dirs"),
             "XDG_PICTURES_DIR=\"$HOME/Imagens\"\n"
             "XDG_MUSIC_DIR=\"$HOME/Música\"\n"
             "XDG_VIDEOS_DIR=\"$HOME/Vídeos\"\n");
    qputenv("XDG_CONFIG_HOME", (m_home.path() + QStringLiteral("/.config")).toUtf8());
}

void UmsProfileTest::defaultFoldersAreTheUserDirectories()
{
    const QString home = m_home.path();
    QCOMPARE(UmsProfile::defaultFolders(),
             (QStringList{home + QStringLiteral("/Imagens"), home + QStringLiteral("/Música"), home + QStringLiteral("/Vídeos")}));
}

void UmsProfileTest::defaultFoldersLeaveOutHome()
{
    const QString file = m_home.path() + QStringLiteral("/.config/user-dirs.dirs");
    const QByteArray original = readAll(file);
    writeAll(file, "XDG_PICTURES_DIR=\"$HOME/Pictures\"\nXDG_MUSIC_DIR=\"$HOME\"\nXDG_VIDEOS_DIR=\"$HOME/Videos\"\n");
    const QStringList folders = UmsProfile::defaultFolders();
    QVERIFY(!folders.contains(m_home.path()));
    QCOMPARE(folders.size(), 2);
    writeAll(file, original);
}

void UmsProfileTest::missingSharedConfShowsTheDefaults()
{
    QTemporaryDir profile;
    UmsProfile p(profile.path());
    QCOMPARE(p.folders(), UmsProfile::defaultFolders());
    QVERIFY(!p.folders().contains(QDir::homePath()));
}

void UmsProfileTest::roundTripKeepsOtherEntries()
{
    QTemporaryDir profile;
    const QString file = profile.path() + QStringLiteral("/SHARED.conf");
    writeAll(file,
             R"([{"file":"/a","monitored":true,"metadata":true,"active":true,"groups":[],"type":"Folder"},)"
             R"({"uri":"http://example.org/feed","type":"Feed","active":true}])");
    UmsProfile p(profile.path());
    QCOMPARE(p.folders(), QStringList{QStringLiteral("/a")});
    QVERIFY(p.setFolders({QStringLiteral("/b"), QStringLiteral("/c")}));
    QCOMPARE(p.folders(), (QStringList{QStringLiteral("/b"), QStringLiteral("/c")}));
    const QJsonArray entries = QJsonDocument::fromJson(readAll(file)).array();
    int feeds = 0;
    for (const QJsonValue v : entries) {
        feeds += v.toObject().value(QStringLiteral("type")).toString() == QLatin1String("Feed");
    }
    QCOMPARE(feeds, 1);
}

void UmsProfileTest::keptFolderKeepsItsFlags()
{
    QTemporaryDir profile;
    const QString file = profile.path() + QStringLiteral("/SHARED.conf");
    writeAll(file, R"([{"file":"/a","monitored":false,"metadata":false,"active":false,"groups":["kids"],"type":"Folder"}])");
    UmsProfile p(profile.path());
    QVERIFY(p.setFolders({QStringLiteral("/a"), QStringLiteral("/b")}));
    const QJsonObject a = QJsonDocument::fromJson(readAll(file)).array().at(0).toObject();
    QCOMPARE(a.value(QStringLiteral("monitored")).toBool(), false);
    QCOMPARE(a.value(QStringLiteral("groups")).toArray().size(), 1);
}

void UmsProfileTest::serverNameKeepsTheRestOfTheFile()
{
    QTemporaryDir profile;
    const QString file = profile.path() + QStringLiteral("/UMS.conf");
    writeAll(file, "# comment\nauto_update = false\nserver_name = Old\nport = 5001\n");
    UmsProfile p(profile.path());
    QCOMPARE(p.serverName(), QStringLiteral("Old"));
    QVERIFY(p.setServerName(QStringLiteral("Sala")));
    QCOMPARE(readAll(file), QByteArray("# comment\nauto_update = false\nserver_name = Sala\nport = 5001\n"));
}

void UmsProfileTest::serverNameWithSpecialCharacters()
{
    QTemporaryDir profile;
    UmsProfile p(profile.path());
    const QString name = QStringLiteral("Sala, TV \\ 4K ñ 日本");
    QVERIFY(p.setServerName(name));
    QCOMPARE(p.serverName(), name);
    QVERIFY(readAll(profile.path() + QStringLiteral("/UMS.conf")).contains("Sala, TV \\\\ 4K"));
}

void UmsProfileTest::serverNameLineIsAppendedWhenMissing()
{
    QTemporaryDir profile;
    const QString file = profile.path() + QStringLiteral("/UMS.conf");
    writeAll(file, "auto_update = false\n");
    UmsProfile p(profile.path());
    QVERIFY(p.setServerName(QStringLiteral("X")));
    QCOMPARE(readAll(file), QByteArray("auto_update = false\nserver_name = X\n"));
}

static QString writeFakeSystemctl(const QString &dir, const QString &body)
{
    const QString path = dir + QStringLiteral("/systemctl");
    writeAll(path, QByteArray("#!/bin/sh\n") + body.toUtf8());
    QFile::setPermissions(path, QFile::permissions(path) | QFileDevice::ExeOwner);
    return path;
}

void UmsProfileTest::serviceCommandsReachSystemctl()
{
    QTemporaryDir dir;
    const QString log = dir.path() + QStringLiteral("/log");
    qputenv(
        "UMS_KCM_SYSTEMCTL",
        writeFakeSystemctl(dir.path(), QStringLiteral("echo \"$@\" >>%1\ncase \"$2\" in is-enabled) echo enabled;; is-active) echo inactive;; esac\n").arg(log))
            .toUtf8());
    UmsService service;
    QVERIFY(service.isEnabled());
    QVERIFY(!service.isActive());
    QVERIFY(service.setEnabled(true));
    QVERIFY(service.setEnabled(false));
    QVERIFY(service.restartIfActive());
    QCOMPARE(readAll(log),
             QByteArray("--user is-enabled ums.service\n--user is-active ums.service\n--user enable --now ums.service\n"
                        "--user disable --now ums.service\n--user try-restart ums.service\n"));
    qunsetenv("UMS_KCM_SYSTEMCTL");
}

void UmsProfileTest::serviceFailureIsReported()
{
    QTemporaryDir dir;
    qputenv("UMS_KCM_SYSTEMCTL", writeFakeSystemctl(dir.path(), QStringLiteral("echo 'Unit ums.service not found.' >&2\nexit 1\n")).toUtf8());
    UmsService service;
    QVERIFY(!service.setEnabled(true));
    QCOMPARE(service.errorString(), QStringLiteral("Unit ums.service not found."));
    QVERIFY(!service.isEnabled());
    qunsetenv("UMS_KCM_SYSTEMCTL");
}

QTEST_GUILESS_MAIN(UmsProfileTest)
#include "umsprofiletest.moc"
