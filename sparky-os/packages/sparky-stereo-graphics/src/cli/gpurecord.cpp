// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

// sparky-stereo-gpu-record: the machine's record of which GPU players and 3D draw best on, and whether
// decoded video may be copied back, in /etc/xdg/sparky-stereo-graphicsrc. The Graphics page and
// libmedia-gpu-route read it beneath the person's own choices. Run as root.
//
//   sparky-stereo-gpu-record --apply-known      at boot: the record shipped for this model, when the machine has none of its own
//   sparky-stereo-gpu-record --set-best GPU [--copy-back true|false] [--model TEXT] [--measurement TEXT]
//                                               a measurement's result; GPU is pci-0000:03:00.0 or 1002:6660
//   sparky-stereo-gpu-record --copy-back true|false|unset
//   sparky-stereo-gpu-record --forget           removes what this command wrote
//   sparky-stereo-gpu-record --show
// Options: --root DIR (another system's root), --machines DIR (the shipped records).
//
// Exit status: 0 done, 2 wrong arguments, 3 the record could not be written.

#include "graphicssettings.h"
#include "machinerecord.h"

#include <QCoreApplication>
#include <QTextStream>

using namespace Qt::StringLiterals;
using namespace SparkyGraphics;

static int usage(const QString &problem)
{
    QTextStream err(stderr);
    err << problem
        << "\nUsage: sparky-stereo-gpu-record [--root DIR] [--machines DIR] --apply-known | --show | --forget"
           " | --set-best GPU [--copy-back true|false] [--model TEXT] [--measurement TEXT] | --copy-back true|false|unset\n";
    return 2;
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    const QStringList args = app.arguments().mid(1);
    QString root = u"/"_s;
    QString machines = QStringLiteral(SPARKY_MACHINES_DIR);
    QString action;
    QString best;
    QString copyBack;
    QString model;
    QString measurement;
    for (int i = 0; i < args.size(); ++i) {
        const QString &arg = args.at(i);
        const auto value = [&]() -> QString {
            return i + 1 < args.size() ? args.at(++i) : QString();
        };
        if (arg == u"--root"_s) {
            root = value();
        } else if (arg == u"--machines"_s) {
            machines = value();
        } else if (arg == u"--apply-known"_s || arg == u"--show"_s || arg == u"--forget"_s) {
            action = arg;
        } else if (arg == u"--set-best"_s) {
            action = arg;
            best = value();
        } else if (arg == u"--copy-back"_s) {
            copyBack = value();
            if (copyBack.isEmpty()) {
                return usage(u"--copy-back needs true, false or unset"_s);
            }
        } else if (arg == u"--model"_s) {
            model = value();
        } else if (arg == u"--measurement"_s) {
            measurement = value();
        } else {
            return usage(u"Unknown argument %1"_s.arg(arg));
        }
    }
    std::optional<bool> copy;
    if (!copyBack.isEmpty() && copyBack != u"unset"_s) {
        copy = GraphicsSettings::parseBool(copyBack);
        if (!copy.has_value()) {
            return usage(u"Not true or false: %1"_s.arg(copyBack));
        }
    }
    if (action.isEmpty() && !copyBack.isEmpty()) {
        action = u"--copy-back"_s;
    }
    QTextStream out(stdout);

    if (action == u"--apply-known"_s) {
        switch (RecordWriter::applyKnown(root, machines)) {
        case RecordWriter::Result::Written:
            out << "written\n";
            return 0;
        case RecordWriter::Result::Unchanged:
            out << "unchanged\n";
            return 0;
        case RecordWriter::Result::Kept:
            out << "kept\n";
            return 0;
        case RecordWriter::Result::Removed:
            out << "removed\n";
            return 0;
        case RecordWriter::Result::NothingKnown:
            out << "nothing-known\n";
            return 0;
        case RecordWriter::Result::Failed:
            break;
        }
        QTextStream(stderr) << "sparky-stereo-gpu-record: cannot write " << MachineRecord::systemFile(root) << '\n';
        return 3;
    }
    if (action == u"--show"_s) {
        const QString file = MachineRecord::systemFile(root);
        const MachineRecord record = MachineRecord::readFile(file);
        out << "file=" << file << '\n'
            << "origin=" << (record.origin.isEmpty() && !record.isEmpty() ? u"hand"_s : record.origin) << '\n'
            << "known=" << record.known << '\n'
            << "best-gpu=" << record.bestGpu << '\n'
            << "copy-back=" << (record.copyBack.has_value() ? (*record.copyBack ? u"true"_s : u"false"_s) : u"unset"_s) << '\n'
            << "model=" << record.model << '\n'
            << "measurement=" << record.measurement << '\n';
        return 0;
    }
    if (action == u"--set-best"_s) {
        if (!MachineRecord::validGpu(best.trimmed().toLower())) {
            return usage(u"Not a GPU: %1 (pci-0000:03:00.0 or 1002:6660)"_s.arg(best));
        }
        if (!RecordWriter::writeMeasured(root, best, copy, model, measurement)) {
            QTextStream(stderr) << "sparky-stereo-gpu-record: cannot write " << MachineRecord::systemFile(root) << '\n';
            return 3;
        }
        return 0;
    }
    if (action == u"--copy-back"_s) {
        if (!RecordWriter::writeCopyBack(root, copy)) {
            QTextStream(stderr) << "sparky-stereo-gpu-record: cannot write " << MachineRecord::systemFile(root) << '\n';
            return 3;
        }
        return 0;
    }
    if (action == u"--forget"_s) {
        return RecordWriter::forget(root) ? 0 : 3;
    }
    return usage(u"Nothing to do"_s);
}
