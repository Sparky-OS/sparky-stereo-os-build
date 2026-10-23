// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "appentries.h"

#include <KConfigGroup>
#include <KDesktopFile>
#include <KService>

#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QTest>

using namespace Qt::StringLiterals;
using namespace SparkyGraphics;

// The page writes KDE's own key and KDE's own class reads it back: no second list exists.
class AppEntriesTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void init();
    void listsMenuEntries();
    void categoriesMapToTheFourGroups_data();
    void categoriesMapToTheFourGroups();
    void writeReadByKService();
    void secondWriteEditsInPlace();
    void unsetRemovesTheIdenticalCopy();
    void systemKeyCanBeOverriddenAndRestored();
    void aCopyWithOtherEditsStays();
    void staleCopyFollowsTheSystemEntry();
    void personsFolderInTheDataDirsIsNotASystemFolder();
    void unknownEntry();
    void subdirectoryIds();

private:
    void entry(const QString &dir, const QString &name, const QString &text)
    {
        QDir().mkpath(dir);
        QFile f(dir + u'/' + name);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(text.toUtf8());
    }
    AppEntries entries() const
    {
        return AppEntries(home(), {system()});
    }
    QString home() const
    {
        return m_root.filePath(u"home"_s);
    }
    QString system() const
    {
        return m_root.filePath(u"usr"_s);
    }
    QString userFile(const QString &id) const
    {
        return home() + u"/applications/"_s + id;
    }
    QString systemFile(const QString &id) const
    {
        return system() + u"/applications/"_s + id;
    }
    QByteArray read(const QString &path) const
    {
        QFile f(path);
        return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
    }

    QTemporaryDir m_root;
};

static const QString s_player = u"[Desktop Entry]\nType=Application\nName=Player\nName[pt_BR]=Reprodutor\nExec=player %U\nIcon=player\nCategories=AudioVideo;Player;\n"_s;
static const QString s_game = u"[Desktop Entry]\nType=Application\nName=Game\nExec=game\nCategories=Game;ActionGame;\n"_s;

void AppEntriesTest::init()
{
    QDir(m_root.path()).removeRecursively();
    QDir().mkpath(m_root.path());
    const QString apps = system() + u"/applications"_s;
    entry(apps, u"org.example.player.desktop"_s, s_player);
    entry(apps, u"org.example.game.desktop"_s, s_game);
    entry(apps, u"org.example.browser.desktop"_s, u"[Desktop Entry]\nType=Application\nName=Browser\nExec=browser\nCategories=Network;WebBrowser;\n"_s);
    entry(apps, u"org.example.tool.desktop"_s, u"[Desktop Entry]\nType=Application\nName=Tool\nExec=tool\nCategories=Utility;\n"_s);
    entry(apps, u"org.example.hidden.desktop"_s, u"[Desktop Entry]\nType=Application\nName=Hidden\nExec=hidden\nNoDisplay=true\n"_s);
    entry(apps, u"org.example.dgpu.desktop"_s, u"[Desktop Entry]\nType=Application\nName=Dedicated\nExec=dgpu\nCategories=Game;\nPrefersNonDefaultGPU=true\n"_s);
    entry(apps + u"/kde"_s, u"foo.desktop"_s, u"[Desktop Entry]\nType=Application\nName=Foo\nExec=foo\n"_s);
}

void AppEntriesTest::listsMenuEntries()
{
    const QList<AppEntry> list = entries().list();
    QStringList ids;
    for (const AppEntry &e : list) {
        ids << e.id;
    }
    ids.sort();
    QCOMPARE(ids,
             (QStringList{u"kde-foo.desktop"_s, u"org.example.browser.desktop"_s, u"org.example.dgpu.desktop"_s, u"org.example.game.desktop"_s, u"org.example.player.desktop"_s, u"org.example.tool.desktop"_s}));
    const AppEntry player = entries().find(u"org.example.player.desktop"_s);
    QCOMPARE(player.name, u"Player"_s);
    QCOMPARE(player.icon, u"player"_s);
    QVERIFY(player.category == Category::Players);
    QVERIFY(player.preference == AppPreference::Unset);
    QVERIFY(!player.fromUserCopy);
    const AppEntry dgpu = entries().find(u"org.example.dgpu.desktop"_s);
    QVERIFY(dgpu.preference == AppPreference::OtherGpu);
    QVERIFY(dgpu.systemPrefersOther);
    QVERIFY(dgpu.category == Category::Games);
}

void AppEntriesTest::categoriesMapToTheFourGroups_data()
{
    QTest::addColumn<QStringList>("categories");
    QTest::addColumn<int>("expected");
    QTest::newRow("player") << QStringList{u"AudioVideo"_s, u"Player"_s} << int(Category::Players);
    QTest::newRow("video") << QStringList{u"Video"_s} << int(Category::Players);
    QTest::newRow("audio") << QStringList{u"Audio"_s, u"Music"_s} << int(Category::Players);
    QTest::newRow("game") << QStringList{u"Game"_s} << int(Category::Games);
    QTest::newRow("browser") << QStringList{u"Network"_s, u"WebBrowser"_s} << int(Category::Browsers);
    QTest::newRow("tool") << QStringList{u"Utility"_s} << int(Category::Other);
    QTest::newRow("none") << QStringList{} << int(Category::Other);
    // a video editor is not a player; AudioVideoEditing is no Player category
    QTest::newRow("editor") << QStringList{u"AudioVideo"_s, u"AudioVideoEditing"_s} << int(Category::Other);
    QTest::newRow("game first") << QStringList{u"Game"_s, u"Video"_s} << int(Category::Games);
}

void AppEntriesTest::categoriesMapToTheFourGroups()
{
    QFETCH(QStringList, categories);
    QFETCH(int, expected);
    QCOMPARE(int(AppEntries::categoryFor(categories)), expected);
}

void AppEntriesTest::writeReadByKService()
{
    AppEntries e = entries();
    const QString id = u"org.example.player.desktop"_s;
    QVERIFY(!QFile::exists(userFile(id)));
    QVERIFY(e.setPreference(id, AppPreference::OtherGpu));
    QVERIFY(QFile::exists(userFile(id)));
    // KDE's own class sees it, from the person's copy, which wins over the system entry
    QVERIFY(KService(userFile(id)).runOnDiscreteGpu());
    QVERIFY(!KService(systemFile(id)).runOnDiscreteGpu());
    // the copy keeps everything else
    KDesktopFile copy(userFile(id));
    QCOMPARE(copy.readName(), u"Player"_s);
    QCOMPARE(copy.desktopGroup().readEntry("Exec"), u"player %U"_s);
    QVERIFY(read(userFile(id)).contains("Name[pt_BR]=Reprodutor"));
    // and the page reads it back
    const AppEntry back = entries().find(id);
    QVERIFY(back.preference == AppPreference::OtherGpu);
    QVERIFY(back.fromUserCopy);
    QCOMPARE(back.path, userFile(id));
    // the system file was never touched
    QCOMPARE(read(systemFile(id)), s_player.toUtf8());
}

void AppEntriesTest::secondWriteEditsInPlace()
{
    AppEntries e = entries();
    const QString id = u"org.example.game.desktop"_s;
    QVERIFY(e.setPreference(id, AppPreference::OtherGpu));
    QVERIFY(KService(userFile(id)).runOnDiscreteGpu());
    QVERIFY(e.setPreference(id, AppPreference::MainGpu));
    QVERIFY(!KService(userFile(id)).runOnDiscreteGpu());
    QVERIFY(entries().find(id).preference == AppPreference::MainGpu);
    QCOMPARE(QDir(home() + u"/applications"_s).entryList({u"*.desktop"_s}).size(), 1);
    QVERIFY(read(userFile(id)).contains("PrefersNonDefaultGPU=false"));
}

void AppEntriesTest::unsetRemovesTheIdenticalCopy()
{
    AppEntries e = entries();
    const QString id = u"org.example.player.desktop"_s;
    QVERIFY(e.setPreference(id, AppPreference::OtherGpu));
    QVERIFY(e.setPreference(id, AppPreference::Unset));
    // a copy that now equals the system entry is deleted, so system updates reach the person again
    QVERIFY(!QFile::exists(userFile(id)));
    const AppEntry back = entries().find(id);
    QVERIFY(back.preference == AppPreference::Unset);
    QVERIFY(!back.fromUserCopy);
    // nothing to remove: succeeds
    QVERIFY(e.setPreference(id, AppPreference::Unset));
}

void AppEntriesTest::systemKeyCanBeOverriddenAndRestored()
{
    AppEntries e = entries();
    const QString id = u"org.example.dgpu.desktop"_s;
    QVERIFY(e.setPreference(id, AppPreference::MainGpu));
    QVERIFY(!KService(userFile(id)).runOnDiscreteGpu());
    QVERIFY(KService(systemFile(id)).runOnDiscreteGpu());
    AppEntry now = entries().find(id);
    QVERIFY(now.preference == AppPreference::MainGpu);
    QVERIFY(now.systemPrefersOther);
    QVERIFY(e.setPreference(id, AppPreference::Unset));
    QVERIFY(!QFile::exists(userFile(id)));
    now = entries().find(id);
    QVERIFY(now.preference == AppPreference::OtherGpu);
}

void AppEntriesTest::aCopyWithOtherEditsStays()
{
    AppEntries e = entries();
    const QString id = u"org.example.player.desktop"_s;
    QVERIFY(e.setPreference(id, AppPreference::OtherGpu));
    {
        KDesktopFile copy(userFile(id));
        copy.desktopGroup().writeEntry("Exec", "player --my-flag %U");
        copy.sync();
    }
    QVERIFY(e.setPreference(id, AppPreference::Unset));
    QVERIFY(QFile::exists(userFile(id)));
    KDesktopFile copy(userFile(id));
    QCOMPARE(copy.desktopGroup().readEntry("Exec"), u"player --my-flag %U"_s);
    QVERIFY(!copy.desktopGroup().hasKey("PrefersNonDefaultGPU"));
}

void AppEntriesTest::staleCopyFollowsTheSystemEntry()
{
    AppEntries e = entries();
    const QString id = u"org.example.player.desktop"_s;
    QVERIFY(e.setPreference(id, AppPreference::OtherGpu));
    // a package update changes the system entry
    entry(system() + u"/applications"_s, id, QString(s_player).replace(u"player %U"_s, u"player --new %U"_s));
    QCOMPARE(e.refreshCopies(), 1);
    KDesktopFile copy(userFile(id));
    QCOMPARE(copy.desktopGroup().readEntry("Exec"), u"player --new %U"_s);
    QVERIFY(KService(userFile(id)).runOnDiscreteGpu());
    // up to date now
    QCOMPARE(e.refreshCopies(), 0);
    // a copy the person edited is left alone
    {
        KDesktopFile edited(userFile(id));
        edited.desktopGroup().writeEntry("Exec", "player --mine %U");
        edited.sync();
    }
    entry(system() + u"/applications"_s, id, QString(s_player).replace(u"player %U"_s, u"player --newer %U"_s));
    QCOMPARE(e.refreshCopies(), 0);
    QCOMPARE(KDesktopFile(userFile(id)).desktopGroup().readEntry("Exec"), u"player --mine %U"_s);
}

void AppEntriesTest::personsFolderInTheDataDirsIsNotASystemFolder()
{
    // QStandardPaths::standardLocations() starts with the person's own folder; the copy must never count as the system entry
    AppEntries e(home(), {home(), system()});
    const QString id = u"org.example.player.desktop"_s;
    QVERIFY(e.setPreference(id, AppPreference::OtherGpu));
    QCOMPARE(e.refreshCopies(), 0);
    QVERIFY(QFile::exists(userFile(id)));
    QVERIFY(KService(userFile(id)).runOnDiscreteGpu());
    QVERIFY(e.setPreference(id, AppPreference::Unset));
    QVERIFY(!QFile::exists(userFile(id)));
}

void AppEntriesTest::unknownEntry()
{
    AppEntries e = entries();
    QVERIFY(!e.setPreference(u"nothing.desktop"_s, AppPreference::OtherGpu));
    QVERIFY(e.find(u"nothing.desktop"_s).id.isEmpty());
}

void AppEntriesTest::subdirectoryIds()
{
    AppEntries e = entries();
    QVERIFY(e.setPreference(u"kde-foo.desktop"_s, AppPreference::OtherGpu));
    QVERIFY(KService(userFile(u"kde-foo.desktop"_s)).runOnDiscreteGpu());
    QVERIFY(entries().find(u"kde-foo.desktop"_s).preference == AppPreference::OtherGpu);
}

QTEST_GUILESS_MAIN(AppEntriesTest)
#include "appentriestest.moc"
