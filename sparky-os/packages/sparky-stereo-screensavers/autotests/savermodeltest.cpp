// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// The list of savers on a tree of the test's own: which are listed, their kind, the reason of one that cannot be
// offered, the store's two values, names the store holds for savers that are not installed, and the depth conversion.
#include "savermodel.h"
#include "readabletext.h"
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

    void contrastIsWcags()
    {
        // WCAG 2.2's own figures: black on white 21:1; #767676 on white is the lightest grey that passes 4.5:1, #777777 does not
        const QColor white(255, 255, 255), black(0, 0, 0);
        QCOMPARE(ReadableText::contrast(black, white), 21.0);
        QCOMPARE(ReadableText::contrast(white, black), 21.0);
        QVERIFY(ReadableText::contrast(QColor(0x76, 0x76, 0x76), white) >= 4.5);
        QVERIFY(ReadableText::contrast(QColor(0x77, 0x77, 0x77), white) < 4.5);
        QVERIFY(qAbs(ReadableText::contrast(QColor(0x76, 0x76, 0x76), white) - 4.54) < 0.01);
    }

    void quietTextIsReadable_data()
    {
        QTest::addColumn<QColor>("wanted");
        QTest::addColumn<QColor>("text");
        QTest::addColumn<QColor>("background");
        QTest::addColumn<bool>("kept");
        // Breeze Light: the inactive text on the window and view backgrounds; Breeze Dark: the same roles
        QTest::newRow("breeze light window") << QColor(112, 125, 138) << QColor(35, 38, 41) << QColor(239, 240, 241) << false;
        QTest::newRow("breeze light view") << QColor(112, 125, 138) << QColor(35, 38, 41) << QColor(255, 255, 255) << false;
        QTest::newRow("breeze dark window") << QColor(161, 169, 177) << QColor(252, 252, 252) << QColor(32, 35, 38) << true;
        QTest::newRow("breeze light neutral") << QColor(246, 116, 0) << QColor(35, 38, 41) << QColor(239, 240, 241) << false;
        QTest::newRow("already readable") << QColor(90, 90, 90) << QColor(0, 0, 0) << QColor(255, 255, 255) << true;
        QTest::newRow("the normal text is short too, light ground") << QColor(200, 200, 200) << QColor(150, 150, 150) << QColor(255, 255, 255) << false;
        QTest::newRow("the normal text is short too, dark ground") << QColor(60, 60, 60) << QColor(90, 90, 90) << QColor(20, 20, 20) << false;
        QTest::newRow("translucent") << QColor(0, 0, 0, 100) << QColor(0, 0, 0) << QColor(255, 255, 255) << false;
        QTest::newRow("on the other side of the ground") << QColor(250, 250, 250) << QColor(20, 20, 20) << QColor(230, 230, 230) << false;
    }

    void quietTextIsReadable()
    {
        QFETCH(QColor, wanted);
        QFETCH(QColor, text);
        QFETCH(QColor, background);
        QFETCH(bool, kept);
        const QColor got = ReadableText::colour(wanted, text, background);
        QVERIFY2(ReadableText::contrast(got, background) >= 4.5, qPrintable(got.name()));
        QCOMPARE(got == wanted, kept);
        if (!kept && wanted.alpha() == 255 && ReadableText::contrast(text, background) >= 4.5) {
            // the smallest step: one 64th of the way back towards the wanted colour is short of 4.5:1 again
            const auto channel = [&](int from, int to, int now) { return to == from ? 0.0 : double(now - from) / (to - from); };
            const double share = std::max({channel(wanted.red(), text.red(), got.red()), channel(wanted.green(), text.green(), got.green()), channel(wanted.blue(), text.blue(), got.blue())});
            QVERIFY(share > 0.0 && share <= 1.0);
            const double before = share - 1.0 / 64;
            const QColor earlier(qRound(wanted.red() + (text.red() - wanted.red()) * before), qRound(wanted.green() + (text.green() - wanted.green()) * before), qRound(wanted.blue() + (text.blue() - wanted.blue()) * before));
            QVERIFY2(ReadableText::contrast(earlier, background) < 4.5, qPrintable(earlier.name()));
        }
    }
};

QTEST_GUILESS_MAIN(SaverModelTest)
#include "savermodeltest.moc"
