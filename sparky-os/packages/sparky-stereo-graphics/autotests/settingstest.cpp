// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "graphicssettings.h"

#include <QFile>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>

using namespace Qt::StringLiterals;
using namespace SparkyGraphics;

class SettingsTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void init();
    void defaultsAreAutomatic();
    void roundTripFromAFreshObject();
    void defaultsRemoveTheKeys();
    void aValueEqualToTheDefaultIsNotWritten();
    void invalidChoicesAreRefused();
    void aGpuThatIsNotHereIsKept();
    void handEditShows();
    void isDefaultTracksChanges();

private:
    QString file() const
    {
        return m_config.filePath(u"sparky-stereo-graphicsrc"_s);
    }
    QByteArray text() const
    {
        QFile f(file());
        return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
    }

    QTemporaryDir m_config;
    QTemporaryDir m_dirs;
};

void SettingsTest::init()
{
    qputenv("XDG_CONFIG_HOME", m_config.path().toUtf8());
    qputenv("XDG_CONFIG_DIRS", m_dirs.path().toUtf8());
    QFile::remove(file());
}

void SettingsTest::defaultsAreAutomatic()
{
    GraphicsSettings settings;
    QCOMPARE(settings.mainGpu(), QString());
    for (Category category : allCategories()) {
        QCOMPARE(settings.renderChoice(category), u"auto"_s);
    }
    QVERIFY(settings.isDefault());
}

void SettingsTest::roundTripFromAFreshObject()
{
    {
        GraphicsSettings settings;
        settings.setMainGpu(u"pci-0000:01:00.0"_s);
        settings.setRenderChoice(Category::Players, u"integrated"_s);
        settings.setRenderChoice(Category::Games, u"discrete"_s);
        settings.setRenderChoice(Category::Browsers, u"pci-0000:03:00.0"_s);
        QVERIFY(settings.save());
    }
    GraphicsSettings fresh;
    QCOMPARE(fresh.mainGpu(), u"pci-0000:01:00.0"_s);
    QCOMPARE(fresh.renderChoice(Category::Players), u"integrated"_s);
    QCOMPARE(fresh.renderChoice(Category::Games), u"discrete"_s);
    QCOMPARE(fresh.renderChoice(Category::Browsers), u"pci-0000:03:00.0"_s);
    QCOMPARE(fresh.renderChoice(Category::Other), u"auto"_s);
    QVERIFY(text().contains("MainGpu=pci-0000:01:00.0"));
    QVERIFY(text().contains("[Render]"));
    QVERIFY(text().contains("Players=integrated"));
}

void SettingsTest::defaultsRemoveTheKeys()
{
    GraphicsSettings settings;
    settings.setMainGpu(u"pci-0000:01:00.0"_s);
    settings.setRenderChoice(Category::Players, u"discrete"_s);
    QVERIFY(settings.save());
    QVERIFY(text().contains("Players=discrete"));

    settings.resetToDefaults();
    QVERIFY(settings.isDefault());
    QVERIFY(settings.save());
    QVERIFY(!text().contains("MainGpu"));
    QVERIFY(!text().contains("Players"));
    GraphicsSettings fresh;
    QCOMPARE(fresh.mainGpu(), QString());
    QCOMPARE(fresh.renderChoice(Category::Players), u"auto"_s);
}

void SettingsTest::aValueEqualToTheDefaultIsNotWritten()
{
    GraphicsSettings settings;
    settings.setRenderChoice(Category::Players, u"auto"_s);
    settings.setMainGpu(QString());
    QVERIFY(settings.save());
    QVERIFY(!text().contains("Players"));
    QVERIFY(!text().contains("MainGpu"));
}

void SettingsTest::invalidChoicesAreRefused()
{
    GraphicsSettings settings;
    settings.setRenderChoice(Category::Games, u"discrete"_s);
    settings.setRenderChoice(Category::Games, u"fastest"_s);
    QCOMPARE(settings.renderChoice(Category::Games), u"discrete"_s);
    settings.setMainGpu(u"/dev/dri/card1"_s);
    QCOMPARE(settings.mainGpu(), QString());
    QVERIFY(GraphicsSettings::validChoice(u"auto"_s));
    QVERIFY(GraphicsSettings::validChoice(u"integrated"_s));
    QVERIFY(GraphicsSettings::validChoice(u"discrete"_s));
    QVERIFY(GraphicsSettings::validChoice(u"pci-0000:0b:00.0"_s));
    QVERIFY(!GraphicsSettings::validChoice(u"nvidia"_s));
    QVERIFY(!GraphicsSettings::validChoice(QString()));
}

void SettingsTest::aGpuThatIsNotHereIsKept()
{
    GraphicsSettings settings;
    settings.setMainGpu(u"pci-0000:09:00.0"_s);
    QVERIFY(settings.save());
    GraphicsSettings fresh;
    QCOMPARE(fresh.mainGpu(), u"pci-0000:09:00.0"_s);
}

void SettingsTest::handEditShows()
{
    QFile f(file());
    QVERIFY(f.open(QIODevice::WriteOnly));
    f.write("[General]\nMainGpu=pci-0000:0b:00.0\n\n[Render]\nOther=discrete\n");
    f.close();
    GraphicsSettings settings;
    QCOMPARE(settings.mainGpu(), u"pci-0000:0b:00.0"_s);
    QCOMPARE(settings.renderChoice(Category::Other), u"discrete"_s);
    QCOMPARE(settings.renderChoice(Category::Players), u"auto"_s);
}

void SettingsTest::isDefaultTracksChanges()
{
    GraphicsSettings settings;
    QVERIFY(settings.isDefault());
    settings.setRenderChoice(Category::Other, u"integrated"_s);
    QVERIFY(!settings.isDefault());
    settings.setRenderChoice(Category::Other, u"auto"_s);
    QVERIFY(settings.isDefault());
}

QTEST_GUILESS_MAIN(SettingsTest)
#include "settingstest.moc"
