/*
    SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <KPluginFactory>
#include <KPluginMetaData>
#include <KQuickConfigModule>

#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>
#include <QTest>

class KcmUmsTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase();
    void init();
    void cleanup();
    void loadShowsOffAndTheDefaultFolders();
    void switchingOnEnablesTheUserService();
    void changesAreWrittenToUmsOwnFiles();
    void restoreBringsBackTheThree();
    void defaultsMeansOffAndTheThreeFolders();
    void failedServiceKeepsTheChangeAndSaysSo();

private:
    QString log() const;
    QString shared() const;
    QStringList sharedFolders() const;
    QObject *kcm() const;

    QTemporaryDir m_home;
    QTemporaryDir m_bin;
    QObject *m_kcm = nullptr;
    KQuickConfigModule *m_module = nullptr;
    QString m_profile;
};

static void writeAll(const QString &path, const QByteArray &data)
{
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly));
    file.write(data);
}

QString KcmUmsTest::log() const
{
    QFile file(m_bin.path() + QStringLiteral("/log"));
    return file.open(QIODevice::ReadOnly) ? QString::fromUtf8(file.readAll()) : QString();
}

QString KcmUmsTest::shared() const
{
    return m_profile + QStringLiteral("/SHARED.conf");
}

QStringList KcmUmsTest::sharedFolders() const
{
    QFile file(shared());
    QStringList result;
    if (file.open(QIODevice::ReadOnly)) {
        for (const QJsonValue v : QJsonDocument::fromJson(file.readAll()).array()) {
            result << v.toObject().value(QStringLiteral("file")).toString();
        }
    }
    return result;
}

void KcmUmsTest::initTestCase()
{
    QVERIFY(m_home.isValid());
    QVERIFY(m_bin.isValid());
    qputenv("HOME", m_home.path().toUtf8());
    qputenv("XDG_CONFIG_HOME", (m_home.path() + QStringLiteral("/.config")).toUtf8());
    qunsetenv("UMS_PROFILE");
    QDir().mkpath(m_home.path() + QStringLiteral("/.config"));
    writeAll(m_home.path() + QStringLiteral("/.config/user-dirs.dirs"),
             "XDG_PICTURES_DIR=\"$HOME/Imagens\"\nXDG_MUSIC_DIR=\"$HOME/Música\"\nXDG_VIDEOS_DIR=\"$HOME/Vídeos\"\n");
    m_profile = m_home.path() + QStringLiteral("/.config/UMS");
    // a stand-in for systemctl: logs its arguments, reports the unit as disabled and inactive
    const QString script = m_bin.path() + QStringLiteral("/systemctl");
    writeAll(script,
             QByteArray("#!/bin/sh\necho \"$@\" >>") + (m_bin.path() + QStringLiteral("/log")).toUtf8()
                 + QByteArray("\n"
                              "[ -f ")
                 + (m_bin.path() + QStringLiteral("/fail")).toUtf8()
                 + QByteArray(" ] && { echo 'boom' >&2; exit 1; }\n"
                              "case \"$2\" in is-enabled) cat ")
                 + (m_bin.path() + QStringLiteral("/enabled")).toUtf8()
                 + QByteArray(" 2>/dev/null || echo disabled;; is-active) echo inactive;; esac\n"
                              "exit 0\n"));
    QFile::setPermissions(script, QFile::permissions(script) | QFileDevice::ExeOwner);
    qputenv("UMS_KCM_SYSTEMCTL", script.toUtf8());
}

void KcmUmsTest::init()
{
    QDir(m_profile).removeRecursively();
    QFile::remove(m_bin.path() + QStringLiteral("/log"));
    QFile::remove(m_bin.path() + QStringLiteral("/fail"));
    QFile::remove(m_bin.path() + QStringLiteral("/enabled"));
    const KPluginMetaData metaData(QStringLiteral(KCM_PLUGIN_PATH));
    QVERIFY(metaData.isValid());
    m_module = KPluginFactory::instantiatePlugin<KQuickConfigModule>(metaData, this).plugin;
    QVERIFY(m_module);
    m_kcm = m_module;
    m_module->load();
}

void KcmUmsTest::cleanup()
{
    delete m_module;
    m_module = nullptr;
}

void KcmUmsTest::loadShowsOffAndTheDefaultFolders()
{
    const QString home = m_home.path();
    QCOMPARE(m_kcm->property("serverEnabled").toBool(), false);
    QCOMPARE(m_kcm->property("folders").toStringList(),
             (QStringList{home + QStringLiteral("/Imagens"), home + QStringLiteral("/Música"), home + QStringLiteral("/Vídeos")}));
    QVERIFY(!m_kcm->property("folders").toStringList().contains(home));
    QVERIFY(!m_module->needsSave());
}

void KcmUmsTest::switchingOnEnablesTheUserService()
{
    m_kcm->setProperty("serverEnabled", true);
    QVERIFY(m_module->needsSave());
    m_module->save();
    QVERIFY(log().contains(QStringLiteral("--user enable --now ums.service")));
    QVERIFY(!log().contains(QStringLiteral("disable")));
}

void KcmUmsTest::changesAreWrittenToUmsOwnFiles()
{
    m_kcm->setProperty("serverName", QStringLiteral("Sparky, sala"));
    QMetaObject::invokeMethod(m_kcm, "addFolder", Q_ARG(QUrl, QUrl::fromLocalFile(QStringLiteral("/srv/filmes"))));
    QMetaObject::invokeMethod(m_kcm, "removeFolder", Q_ARG(int, 0));
    m_module->save();
    QVERIFY(!m_module->needsSave());
    QFile conf(m_profile + QStringLiteral("/UMS.conf"));
    QVERIFY(conf.open(QIODevice::ReadOnly));
    QVERIFY(conf.readAll().contains("server_name = Sparky, sala\n"));
    const QString home = m_home.path();
    QCOMPARE(sharedFolders(), (QStringList{home + QStringLiteral("/Música"), home + QStringLiteral("/Vídeos"), QStringLiteral("/srv/filmes")}));
}

void KcmUmsTest::restoreBringsBackTheThree()
{
    QMetaObject::invokeMethod(m_kcm, "removeFolder", Q_ARG(int, 0));
    QMetaObject::invokeMethod(m_kcm, "removeFolder", Q_ARG(int, 0));
    QCOMPARE(m_kcm->property("folders").toStringList().size(), 1);
    QMetaObject::invokeMethod(m_kcm, "restoreDefaultFolders");
    QCOMPARE(m_kcm->property("folders").toStringList().size(), 3);
    QVERIFY(!m_module->needsSave());
}

void KcmUmsTest::defaultsMeansOffAndTheThreeFolders()
{
    m_kcm->setProperty("serverEnabled", true);
    m_kcm->setProperty("serverName", QStringLiteral("x"));
    QMetaObject::invokeMethod(m_kcm, "removeFolder", Q_ARG(int, 1));
    m_module->defaults();
    QCOMPARE(m_kcm->property("serverEnabled").toBool(), false);
    QCOMPARE(m_kcm->property("serverName").toString(), QString());
    QCOMPARE(m_kcm->property("folders").toStringList().size(), 3);
    QVERIFY(m_module->representsDefaults());
}

void KcmUmsTest::failedServiceKeepsTheChangeAndSaysSo()
{
    writeAll(m_bin.path() + QStringLiteral("/fail"), "x");
    m_kcm->setProperty("serverEnabled", true);
    m_module->save();
    QVERIFY(m_module->needsSave());
    QVERIFY(m_kcm->property("errorMessage").toString().contains(QStringLiteral("boom")));
}

int main(int argc, char **argv)
{
    qputenv("QT_QPA_PLATFORM", "offscreen");
    QGuiApplication app(argc, argv);
    KcmUmsTest test;
    return QTest::qExec(&test, argc, argv);
}
#include "kcmumstest.moc"
