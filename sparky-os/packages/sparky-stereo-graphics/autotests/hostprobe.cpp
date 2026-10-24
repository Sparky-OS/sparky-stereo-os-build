// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

// hostprobe: the page against the machine it runs on (the real sysfs), for the container proofs.
//   hostprobe list                 print what the page lists
//   hostprobe choose MAINID        save a main GPU and Games=discrete, print what a fresh page reads back
//   hostprobe copyback on|off      set "Copy decoded video back" and Apply, print the file and a fresh page
#include "graphicskcm.h"

#include <KPluginMetaData>

#include <QCoreApplication>

using namespace Qt::StringLiterals;
#include <QFile>
#include <QStandardPaths>
#include <QTextStream>

static void print(const GraphicsKcm &kcm, QTextStream &out)
{
    out << "gpuCount=" << kcm.gpuCount() << " multiGpu=" << (kcm.multiGpu() ? "yes" : "no") << "\n";
    for (const QVariant &v : kcm.gpus()) {
        const QVariantMap g = v.toMap();
        out << "gpu id=" << g.value(u"id"_s).toString() << " name=\"" << g.value(u"name"_s).toString() << "\" kind=" << g.value(u"kindText"_s).toString()
            << " draws-desktop=" << (g.value(u"drawsDesktop"_s).toBool() ? "yes" : "no") << " accessible=" << (g.value(u"accessible"_s).toBool() ? "yes" : "no") << "\n  "
            << g.value(u"driverText"_s).toString() << "; " << g.value(u"screensText"_s).toString() << "\n";
    }
    out << "main-choice=\"" << kcm.mainChoice() << "\" main-options:";
    for (const QVariant &o : kcm.mainOptions()) {
        out << " [" << o.toMap().value(u"text"_s).toString() << "]";
    }
    out << "\n";
    for (const QVariant &c : kcm.categories()) {
        const QVariantMap m = c.toMap();
        out << "category " << m.value(u"key"_s).toString() << " choice=" << m.value(u"choice"_s).toString() << " " << m.value(u"nowText"_s).toString() << "\n";
        if (!m.value(u"stereoText"_s).toString().isEmpty()) {
            out << "  " << m.value(u"stereoText"_s).toString() << "\n";
        }
    }
    out << kcm.measuredText() << "\n" << kcm.profileText() << "\n";
    out << "copy-back=" << (kcm.copyBack() ? "on" : "off") << " " << kcm.copyBackMachineText() << "\n";
}

static void printFile(QTextStream &out)
{
    const QString path = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + u"/sparky-stereo-graphicsrc"_s;
    out << "saved; file " << path << ":\n";
    QFile file(path);
    if (file.open(QIODevice::ReadOnly)) {
        out << QString::fromUtf8(file.readAll());
    }
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QTextStream out(stdout);
    const QStringList args = app.arguments().mid(1);
    if (args.isEmpty()) {
        return 2;
    }
    GraphicsKcm kcm(nullptr, KPluginMetaData());
    kcm.load();
    if (args.first() == u"list"_s) {
        print(kcm, out);
        return 0;
    }
    if (args.first() == u"choose"_s && args.size() == 2) {
        kcm.setMainChoice(args.at(1));
        kcm.setCategoryChoice(u"Games"_s, u"discrete"_s);
        kcm.save();
        out << "saved; file "
            << QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + u"/sparky-stereo-graphicsrc"_s << ":\n";
        QFile file(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + u"/sparky-stereo-graphicsrc"_s);
        if (file.open(QIODevice::ReadOnly)) {
            out << QString::fromUtf8(file.readAll());
        }
        GraphicsKcm fresh(nullptr, KPluginMetaData());
        fresh.load();
        out << "-- read back by a fresh page --\n";
        print(fresh, out);
        return 0;
    }
    if (args.first() == u"copyback"_s && args.size() == 2) {
        kcm.setCopyBack(args.at(1) == u"on"_s);
        kcm.save();
        printFile(out);
        GraphicsKcm fresh(nullptr, KPluginMetaData());
        fresh.load();
        out << "-- read back by a fresh page --\n";
        print(fresh, out);
        return 0;
    }
    return 2;
}
