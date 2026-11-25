// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// The list of savers on a tree of the test's own: which are listed, their kind, the reason of one that cannot be
// offered, the store's two values, names the store holds for savers that are not installed, and the depth conversion.
#include "savermodel.h"
#include "saverpreview.h"

#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QTest>

class SaverModelTest : public QObject
{
    Q_OBJECT
    QTemporaryDir m_dir;
    SaverModel::Paths m_paths;

    void write(const QString &path, const QByteArray &text, bool executable = false)
    {
        QDir().mkpath(QFileInfo(path).absolutePath());
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(text);
        file.close();
        if (executable) {
            file.setPermissions(file.permissions() | QFile::ExeOwner);
        }
    }

private Q_SLOTS:
    void initTestCase()
    {
        const QString root = m_dir.path();
        m_paths = {root + QStringLiteral("/share"), root + QStringLiteral("/lib"), root + QStringLiteral("/config"), root + QStringLiteral("/hacks")};
        write(m_paths.share + QStringLiteral("/catalogue.json"), R"([{"id":"gears"},{"id":"rubik"},{"id":"gears"}])");
        write(m_paths.share + QStringLiteral("/savers.json"),
              R"([{"id":"gears","kind":"hack","title":"Gears","authors":["Danny Sung","Brian Paul"]},{"id":"rubik","kind":"hack","title":"Rubik"}])");
        // the catalogue's own rule, stood in for: rubik's executable differs
        write(m_paths.library + QStringLiteral("/catalogue.py"),
              "def dropped(entries):\n    return [['rubik', [{'kind': 'executable-differs', 'path': '/usr/libexec/xscreensaver/rubik', 'expected': 'a'*64, 'found': 'b'*64}]]]\n");
        const QByteArray xml = "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n<screensaver name=\"deco\" _label=\"Deco\">\n <command arg=\"--root\"/>\n"
                               " <_description>\nSubdivides rectangles.\n\nWritten by Jamie Zawinski and Michael Bayne; 1997.\n </_description>\n</screensaver>\n";
        for (const QString &name : {QStringLiteral("deco"), QStringLiteral("maze"), QStringLiteral("gears"), QStringLiteral("nofile")}) {
            write(m_paths.config + QLatin1Char('/') + name + QStringLiteral(".xml"), QByteArray(xml).replace("deco", name.toLatin1()).replace("Deco", name.toUpper().toLatin1()));
        }
        write(m_paths.hacks + QStringLiteral("/deco"), "#!/bin/sh\n", true);
        write(m_paths.hacks + QStringLiteral("/maze"), "#!/bin/sh\n", true);
        write(m_paths.hacks + QStringLiteral("/gears"), "#!/bin/sh\n", true);
        write(m_paths.hacks + QStringLiteral("/xscreensaver-text"), "#!/bin/sh\n", true); // a helper: no description file, not a saver
    }

    void listsEverySaverOnce()
    {
        SaverModel model;
        model.load(m_paths);
        QCOMPARE(model.problem(), QString());
        QCOMPARE(model.count(), 4); // gears, rubik (catalogue), deco, maze (2D); gears once; nofile has no program
        QCOMPARE(model.stereoCount(), 2);
        QCOMPARE(model.flatCount(), 2);
        QCOMPARE(model.notOffered(), 1);
        const QVariantMap gears = model.get(model.find(QStringLiteral("gears")));
        QCOMPARE(gears.value(QStringLiteral("title")).toString(), QStringLiteral("Gears"));
        QCOMPARE(gears.value(QStringLiteral("authors")).toString(), QStringLiteral("Danny Sung, Brian Paul"));
        QVERIFY(gears.value(QStringLiteral("stereo")).toBool() && gears.value(QStringLiteral("offered")).toBool());
        const QVariantMap rubik = model.get(model.find(QStringLiteral("rubik")));
        QVERIFY(!rubik.value(QStringLiteral("offered")).toBool());
        const QString reason = rubik.value(QStringLiteral("reason")).toString();
        QVERIFY2(reason.contains(QStringLiteral("/usr/libexec/xscreensaver/rubik")) && reason.contains(QStringLiteral("aaaaaaaaaaaa")) && reason.contains(QStringLiteral("bbbbbbbbbbbb"))
                     && !reason.contains(QStringLiteral("aaaaaaaaaaaaa")),
                 qPrintable(reason));
        const QVariantMap deco = model.get(model.find(QStringLiteral("deco")));
        QCOMPARE(deco.value(QStringLiteral("title")).toString(), QStringLiteral("DECO"));
        QCOMPARE(deco.value(QStringLiteral("authors")).toString(), QStringLiteral("Jamie Zawinski and Michael Bayne"));
        QVERIFY(!deco.value(QStringLiteral("stereo")).toBool() && deco.value(QStringLiteral("offered")).toBool());
        QCOMPARE(model.find(QStringLiteral("nofile")), -1);
        QCOMPARE(model.find(QStringLiteral("xscreensaver-text")), -1);
    }

    void storeRoundTrip()
    {
        SaverModel model;
        model.load(m_paths);
        // today's state: nothing stored. Every catalogue saver is in the show, no 2D one is.
        model.setStore({}, {});
        QCOMPARE(model.disabled(), QStringList());
        QCOMPARE(model.flat(), QStringList());
        QCOMPARE(model.tickedCount(), 1); // gears; rubik is ticked but cannot be offered
        // a person's file: one saver left out, one 2D ticked, and names of savers that are not installed now
        model.setStore({QStringLiteral("gears"), QStringLiteral("gone-gl")}, {QStringLiteral("maze"), QStringLiteral("gone-2d")});
        QVERIFY(!model.get(model.find(QStringLiteral("gears"))).value(QStringLiteral("ticked")).toBool());
        QVERIFY(model.get(model.find(QStringLiteral("maze"))).value(QStringLiteral("ticked")).toBool());
        QCOMPARE(model.disabled(), (QStringList{QStringLiteral("gears"), QStringLiteral("gone-gl")}));
        QCOMPARE(model.flat(), (QStringList{QStringLiteral("gone-2d"), QStringLiteral("maze")}));
        model.setTicked(model.find(QStringLiteral("gears")), true);
        model.setTicked(model.find(QStringLiteral("deco")), true);
        QCOMPARE(model.disabled(), (QStringList{QStringLiteral("gone-gl")}));
        QCOMPARE(model.flat(), (QStringList{QStringLiteral("deco"), QStringLiteral("gone-2d"), QStringLiteral("maze")}));
        model.tickOnly(model.find(QStringLiteral("deco")));
        QCOMPARE(model.disabled(), (QStringList{QStringLiteral("gears"), QStringLiteral("gone-gl"), QStringLiteral("rubik")}));
        QCOMPARE(model.flat(), (QStringList{QStringLiteral("deco"), QStringLiteral("gone-2d")}));
        model.tickAllStereo();
        QCOMPARE(model.disabled(), (QStringList{QStringLiteral("gone-gl")}));
        QCOMPARE(model.flat(), (QStringList{QStringLiteral("gone-2d")}));
    }

    void missingPackageIsSaid()
    {
        SaverModel::Paths empty = m_paths;
        empty.share = m_dir.path() + QStringLiteral("/nowhere");
        SaverModel model;
        model.load(empty);
        QVERIFY(!model.problem().isEmpty());
        QCOMPARE(model.stereoCount(), 0);
        QCOMPARE(model.flatCount(), 3); // the 2D ones are still listed (gears has no receipt here, so it is one of them)
    }

    void depthShare()
    {
        // the unit conversion only: the sunk limit already in the buffer's pixels, as a share of one view
        QCOMPARE(SaverPreview::shareFor(10.0, 1920.0), 100.0 * 10 / 1920);
        QCOMPARE(SaverPreview::shareFor(10.0, 320.0), 100.0 * 10 / 320); // a small view: the same pixels, a larger share
        QCOMPARE(SaverPreview::shareFor(0.0, 640.0), 0.0);
        QCOMPARE(SaverPreview::shareFor(100.0, 320.0), 10.0); // the layer's own ceiling
        QCOMPARE(SaverPreview::shareFor(4.0, 0.0), -1.0);
    }
};

QTEST_GUILESS_MAIN(SaverModelTest)
#include "savermodeltest.moc"
