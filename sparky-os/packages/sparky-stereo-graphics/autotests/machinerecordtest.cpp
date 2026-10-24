// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "fixtures.h"
#include "machinerecord.h"

#include <QDir>
#include <QFile>
#include <QTemporaryDir>

using namespace SparkyGraphics;

// The machine record: where the page and libmedia-gpu-route read the GPU measured best and the copy-back
// setting, the records shipped for known models, and what sparky-stereo-gpu-record writes.
class MachineRecordTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void init();
    void systemFoldersOnlyTheFirstMostImportant();
    void gpuNames();
    void identityFromTheFirmwareAndThePciBus();
    void theA10IsAKnownModel();
    void matching_data();
    void matching();
    void applyKnownWritesTheA10sRecordOnce();
    void applyKnownOnAnUnknownMachineWritesNothing();
    void aShippedRecordGoesWhenTheDiskMovesToAnotherMachine();
    void aLocalRecordIsNeverReplaced();
    void copyBackAloneMakesTheRecordLocal();
    void forgetRemovesOnlyWhatTheToolWrote();

private:
    QString machine(const QList<FixtureGpu> &gpus, const QByteArray &vendor, const QByteArray &product)
    {
        auto fixture = std::make_unique<SysfsFixture>();
        for (const FixtureGpu &gpu : gpus) {
            fixture->add(gpu);
        }
        fixture->setDmi(vendor, product);
        const QString root = fixture->root();
        m_fixtures.push_back(std::move(fixture));
        return root;
    }
    static QByteArray text(const QString &path)
    {
        QFile f(path);
        return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
    }
    static void write(const QString &path, const QByteArray &data)
    {
        QDir().mkpath(QFileInfo(path).path());
        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(data);
    }
    static KnownMachine a10Record()
    {
        for (const KnownMachine &known : KnownMachine::readAll(QStringLiteral(MACHINES_DIR))) {
            if (known.name == u"lenovo-ideapad-310-15abr"_s) {
                return known;
            }
        }
        return {};
    }

    std::vector<std::unique_ptr<SysfsFixture>> m_fixtures;
    QTemporaryDir m_home;
};

void MachineRecordTest::init()
{
    qputenv("XDG_CONFIG_HOME", m_home.path().toUtf8());
}

void MachineRecordTest::systemFoldersOnlyTheFirstMostImportant()
{
    QTemporaryDir first;
    QTemporaryDir second;
    write(second.filePath(u"sparky-stereo-graphicsrc"_s), "[Measured]\nBestGpu=1002:9874\nModel=Second\n\n[Decoding]\nCopyBack=true\n");
    write(first.filePath(u"sparky-stereo-graphicsrc"_s), "[Measured]\nBestGpu=1002:6660\n\n[Record]\nOrigin=local\n");
    // the person's own file is not the machine's record
    write(m_home.filePath(u"sparky-stereo-graphicsrc"_s), "[Measured]\nBestGpu=10de:2504\n\n[Decoding]\nCopyBack=false\n");
    qputenv("XDG_CONFIG_DIRS", (first.path() + u':' + second.path()).toUtf8());
    const MachineRecord record = MachineRecord::read();
    QCOMPARE(record.bestGpu, u"1002:6660"_s);
    QCOMPARE(record.model, u"Second"_s); // key by key, as KConfig and libmedia-gpu-route merge them
    QCOMPARE(record.copyBack, std::optional<bool>(true));
    QCOMPARE(record.origin, u"local"_s);
    qputenv("XDG_CONFIG_DIRS", second.path().toUtf8());
    QCOMPARE(MachineRecord::read().bestGpu, u"1002:9874"_s);
    qputenv("XDG_CONFIG_DIRS", (m_home.path() + u"/none"_s).toUtf8());
    QVERIFY(MachineRecord::read().isEmpty());
    // a value that is not a GPU is not used
    write(second.filePath(u"sparky-stereo-graphicsrc"_s), "[Measured]\nBestGpu=fastest\n\n[Decoding]\nCopyBack=maybe\n");
    qputenv("XDG_CONFIG_DIRS", second.path().toUtf8());
    QVERIFY(MachineRecord::read().isEmpty());
    QFile::remove(m_home.filePath(u"sparky-stereo-graphicsrc"_s));
}

void MachineRecordTest::gpuNames()
{
    QVERIFY(MachineRecord::validGpu(u"pci-0000:03:00.0"_s));
    QVERIFY(MachineRecord::validGpu(u"1002:6660"_s));
    QVERIFY(MachineRecord::validGpu(u"10de:2504"_s));
    QVERIFY(!MachineRecord::validGpu(u"1002:66600"_s));
    QVERIFY(!MachineRecord::validGpu(u"/dev/dri/card1"_s));
    QVERIFY(!MachineRecord::validGpu(u"nvidia"_s));
    QVERIFY(!MachineRecord::validGpu(QString()));
}

void MachineRecordTest::identityFromTheFirmwareAndThePciBus()
{
    const QString root = machine(SysfsFixture::a10(), "LENOVO", "80ST");
    // a device that is not a display controller is not one of the machine's GPUs
    const QString usb = root + u"/sys/devices/pci0000:00/0000:00:10.0"_s;
    write(usb + u"/class"_s, "0x0c0330\n");
    write(usb + u"/vendor"_s, "0x1022\n");
    write(usb + u"/device"_s, "0x7914\n");
    QVERIFY(QFile::link(usb, root + u"/sys/bus/pci/devices/0000:00:10.0"_s));
    const MachineIdentity identity = MachineIdentity::read(root);
    QCOMPARE(identity.vendor, u"LENOVO"_s);
    QCOMPARE(identity.product, u"80ST"_s);
    QCOMPARE(identity.gpus, (QStringList{u"1002:6660"_s, u"1002:9874"_s}));
    QVERIFY(MachineIdentity::read(root + u"/none"_s).gpus.isEmpty());
}

void MachineRecordTest::theA10IsAKnownModel()
{
    const KnownMachine known = a10Record();
    QCOMPARE(known.name, u"lenovo-ideapad-310-15abr"_s);
    QCOMPARE(known.vendor, u"LENOVO"_s);
    QCOMPARE(known.gpus, (QStringList{u"1002:6660"_s, u"1002:9874"_s}));
    // ORDER 234: the R5 M430 dropped about a ninth of the frames of the Carrizo that drives the screens, and
    // copying decoded pictures back dropped more than software decoding
    QCOMPARE(known.record.bestGpu, u"1002:6660"_s);
    QCOMPARE(known.record.copyBack, std::optional<bool>(false));
    QCOMPARE(known.record.model, u"Lenovo ideapad 310-15ABR"_s);
    QVERIFY(known.record.measurement.contains(u"589.6"_s));
    QVERIFY(known.record.measurement.contains(u"65.3"_s));
}

void MachineRecordTest::matching_data()
{
    QTest::addColumn<QString>("vendor");
    QTest::addColumn<QString>("product");
    QTest::addColumn<int>("gpus"); // 0 the A10's two, 1 the host's, 2 the A10's and a third
    QTest::addColumn<bool>("matches");
    QTest::newRow("the A10") << u"LENOVO"_s << u"80ST"_s << 0 << true;
    QTest::newRow("the vendor in other letters") << u"Lenovo"_s << u"80ST"_s << 0 << true;
    QTest::newRow("a full machine type and model") << u"LENOVO"_s << u"80ST0012US"_s << 0 << true;
    QTest::newRow("another make with the same chips") << u"HP"_s << u"80ST"_s << 0 << false;
    QTest::newRow("another Lenovo") << u"LENOVO"_s << u"81DE"_s << 0 << false;
    QTest::newRow("the A10's name on other chips") << u"LENOVO"_s << u"80ST"_s << 1 << false;
    QTest::newRow("a third GPU changes what was measured") << u"LENOVO"_s << u"80ST"_s << 2 << false;
}

void MachineRecordTest::matching()
{
    QFETCH(QString, vendor);
    QFETCH(QString, product);
    QFETCH(int, gpus);
    MachineIdentity identity;
    identity.vendor = vendor;
    identity.product = product;
    const QList<QStringList> sets = {{u"1002:6660"_s, u"1002:9874"_s}, {u"1002:1638"_s, u"10de:2504"_s}, {u"1002:6660"_s, u"1002:9874"_s, u"10de:2504"_s}};
    identity.gpus = sets[gpus];
    QFETCH(bool, matches);
    QCOMPARE(a10Record().matches(identity), matches);
}

void MachineRecordTest::applyKnownWritesTheA10sRecordOnce()
{
    const QString root = machine(SysfsFixture::a10(), "LENOVO", "80ST");
    const QString file = MachineRecord::systemFile(root);
    QCOMPARE(RecordWriter::applyKnown(root, QStringLiteral(MACHINES_DIR)), RecordWriter::Result::Written);
    const MachineRecord record = MachineRecord::readFile(file);
    QCOMPARE(record.bestGpu, u"1002:6660"_s);
    QCOMPARE(record.copyBack, std::optional<bool>(false));
    QCOMPARE(record.origin, u"shipped"_s);
    QCOMPARE(record.known, u"lenovo-ideapad-310-15abr"_s);
    QCOMPARE(record.model, u"Lenovo ideapad 310-15ABR"_s);
    // libmedia-gpu-route reads the same key in the same group, in every account
    QVERIFY2(text(file).contains("[Decoding]\nCopyBack=false"), text(file).constData());
    QVERIFY(QFile::permissions(file) & QFileDevice::ReadOther);
    // the readers see it through the system folders
    qputenv("XDG_CONFIG_DIRS", (root + u"/etc/xdg"_s).toUtf8());
    QCOMPARE(MachineRecord::read().bestGpu, u"1002:6660"_s);
    // every boot runs it again: nothing changes
    const QByteArray before = text(file);
    QCOMPARE(RecordWriter::applyKnown(root, QStringLiteral(MACHINES_DIR)), RecordWriter::Result::Unchanged);
    QCOMPARE(text(file), before);
}

void MachineRecordTest::applyKnownOnAnUnknownMachineWritesNothing()
{
    const QString root = machine(SysfsFixture::host(), "Example Computers", "Example 1");
    QCOMPARE(RecordWriter::applyKnown(root, QStringLiteral(MACHINES_DIR)), RecordWriter::Result::NothingKnown);
    QVERIFY(!QFile::exists(MachineRecord::systemFile(root)));
    // no folder of shipped records at all
    QCOMPARE(RecordWriter::applyKnown(root, root + u"/none"_s), RecordWriter::Result::NothingKnown);
}

void MachineRecordTest::aShippedRecordGoesWhenTheDiskMovesToAnotherMachine()
{
    const QString a10 = machine(SysfsFixture::a10(), "LENOVO", "80ST");
    QCOMPARE(RecordWriter::applyKnown(a10, QStringLiteral(MACHINES_DIR)), RecordWriter::Result::Written);
    const QString host = machine(SysfsFixture::host(), "Example Computers", "Example 1");
    const QString file = MachineRecord::systemFile(host);
    write(file, text(MachineRecord::systemFile(a10)));
    QCOMPARE(RecordWriter::applyKnown(host, QStringLiteral(MACHINES_DIR)), RecordWriter::Result::Removed);
    QVERIFY(!QFile::exists(file));
    // an administrator's own keys in the same file stay
    write(file, text(MachineRecord::systemFile(a10)) + "\n[Render]\nGames=discrete\n");
    QCOMPARE(RecordWriter::applyKnown(host, QStringLiteral(MACHINES_DIR)), RecordWriter::Result::Removed);
    QVERIFY(text(file).contains("Games=discrete"));
    QVERIFY(!text(file).contains("BestGpu"));
    QVERIFY(!text(file).contains("CopyBack"));
    QVERIFY(!text(file).contains("Origin"));
}

void MachineRecordTest::aLocalRecordIsNeverReplaced()
{
    const QString root = machine(SysfsFixture::a10(), "LENOVO", "80ST");
    const QString file = MachineRecord::systemFile(root);
    QVERIFY(RecordWriter::writeMeasured(root, u"pci-0000:00:01.0"_s, true, QString(), u"a bench on this machine"_s));
    MachineRecord record = MachineRecord::readFile(file);
    QCOMPARE(record.bestGpu, u"pci-0000:00:01.0"_s);
    QCOMPARE(record.origin, u"local"_s);
    QCOMPARE(record.copyBack, std::optional<bool>(true));
    QCOMPARE(record.measurement, u"a bench on this machine"_s);
    QCOMPARE(RecordWriter::applyKnown(root, QStringLiteral(MACHINES_DIR)), RecordWriter::Result::Kept);
    QCOMPARE(MachineRecord::readFile(file).bestGpu, u"pci-0000:00:01.0"_s);
    // a record written by hand, without the tool's mark, is the administrator's
    write(file, "[Measured]\nBestGpu=1002:9874\n");
    QCOMPARE(RecordWriter::applyKnown(root, QStringLiteral(MACHINES_DIR)), RecordWriter::Result::Kept);
    QCOMPARE(text(file), QByteArray("[Measured]\nBestGpu=1002:9874\n"));
    // and a GPU that is no GPU is refused
    QVERIFY(!RecordWriter::writeMeasured(root, u"fastest"_s, std::nullopt, QString(), QString()));
}

void MachineRecordTest::copyBackAloneMakesTheRecordLocal()
{
    const QString root = machine(SysfsFixture::a10(), "LENOVO", "80ST");
    const QString file = MachineRecord::systemFile(root);
    QCOMPARE(RecordWriter::applyKnown(root, QStringLiteral(MACHINES_DIR)), RecordWriter::Result::Written);
    QVERIFY(RecordWriter::writeCopyBack(root, true));
    const MachineRecord record = MachineRecord::readFile(file);
    QCOMPARE(record.copyBack, std::optional<bool>(true));
    QCOMPARE(record.origin, u"local"_s);
    QCOMPARE(record.bestGpu, u"1002:6660"_s); // the shipped measurement stays
    // the next boot keeps the administrator's setting
    QCOMPARE(RecordWriter::applyKnown(root, QStringLiteral(MACHINES_DIR)), RecordWriter::Result::Kept);
    QCOMPARE(MachineRecord::readFile(file).copyBack, std::optional<bool>(true));
    QVERIFY(RecordWriter::writeCopyBack(root, std::nullopt));
    QVERIFY(!MachineRecord::readFile(file).copyBack.has_value());
}

void MachineRecordTest::forgetRemovesOnlyWhatTheToolWrote()
{
    const QString root = machine(SysfsFixture::a10(), "LENOVO", "80ST");
    const QString file = MachineRecord::systemFile(root);
    QVERIFY(RecordWriter::writeMeasured(root, u"1002:6660"_s, false, u"Lenovo ideapad 310-15ABR"_s, u"bench"_s));
    QVERIFY(RecordWriter::forget(root));
    QVERIFY(!QFile::exists(file));
    QVERIFY(RecordWriter::writeMeasured(root, u"1002:6660"_s, false, QString(), QString()));
    write(file, text(file) + "\n[Render]\nGames=discrete\n");
    QVERIFY(RecordWriter::forget(root));
    QCOMPARE(text(file).trimmed(), QByteArray("[Render]\nGames=discrete"));
    // nothing to forget is not a failure
    QVERIFY(RecordWriter::forget(machine(SysfsFixture::host(), "Example Computers", "Example 1")));
}

QTEST_GUILESS_MAIN(MachineRecordTest)
#include "machinerecordtest.moc"
