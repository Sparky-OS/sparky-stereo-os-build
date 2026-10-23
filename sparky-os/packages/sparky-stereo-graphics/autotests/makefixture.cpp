// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

// makefixture NAME DIR: writes the sysfs tree of a test machine under DIR (for the shell tests).
#include "fixtures.h"

#include <QCoreApplication>
#include <QDir>

static void copyTree(const QString &from, const QString &to)
{
    const QDir source(from);
    QDir().mkpath(to);
    const QFileInfoList entries = source.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System);
    for (const QFileInfo &info : entries) {
        const QString target = to + u'/' + info.fileName();
        if (info.isSymLink()) {
            QFile::link(info.symLinkTarget(), target);
        } else if (info.isDir()) {
            copyTree(info.filePath(), target);
        } else {
            QFile::copy(info.filePath(), target);
        }
    }
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    if (argc != 3) {
        return 2;
    }
    const QString name = QString::fromLocal8Bit(argv[1]);
    QList<FixtureGpu> gpus;
    if (name == u"one"_s) {
        gpus = {SysfsFixture::intel()};
    } else if (name == u"a10"_s) {
        gpus = SysfsFixture::a10();
    } else if (name == u"host"_s) {
        gpus = SysfsFixture::host();
    } else if (name == u"bmc"_s) {
        gpus = SysfsFixture::bmc();
    } else if (name == u"three"_s) {
        gpus = SysfsFixture::three();
    } else {
        return 2;
    }
    SysfsFixture fixture;
    for (const FixtureGpu &gpu : gpus) {
        fixture.add(gpu);
    }
    // sysfs symlinks hold absolute paths into the temporary tree: rebuild them for the target
    const QString target = QString::fromLocal8Bit(argv[2]);
    QDir().mkpath(target);
    copyTree(fixture.root(), target);
    // re-point class/drm/cardN/device at the copy
    const QStringList cards = QDir(target + u"/sys/class/drm"_s).entryList({u"card[0-9]*"_s}, QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &card : cards) {
        const QString link = target + u"/sys/class/drm/"_s + card + u"/device"_s;
        if (QFileInfo(link).isSymLink()) {
            const QString old = QFileInfo(link).symLinkTarget();
            const int at = old.indexOf(u"/sys/devices/"_s);
            QFile::remove(link);
            QFile::link(target + old.mid(at), link);
        }
    }
    return 0;
}
