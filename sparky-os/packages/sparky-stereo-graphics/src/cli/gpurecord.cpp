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
//   sparky-stereo-gpu-record --keep systemd-reload --status N [--output TEXT]
//                                               the package's maintainer scripts: a failed step, said and kept
//   sparky-stereo-gpu-record --clear systemd-reload
// Options: --root DIR (another system's root), --machines DIR (the shipped records).
//
// A record that cannot be written is said on stderr in the system's language and kept in
// /var/lib/sparky-stereo-graphics/problems (shown at each login and on the Graphics page) until --apply-known succeeds.
//
// Exit status: 0 done, 2 wrong arguments, 3 the record could not be written.

#include "graphicssettings.h"
#include "machinerecord.h"
#include "paint.h"
#include "problems.h"

#include <KLocalizedString>

#include <QCoreApplication>
#include <QTextStream>

using namespace Qt::StringLiterals;
using namespace SparkyGraphics;

static int usage(const QString &problem)
{
    QTextStream err(stderr);
    // the synopsis stays as it is: options and their arguments are the same in every language
    err << problem << '\n'
        << i18nc("@info:shell %1 is the command's synopsis, which stays as it is", "Usage: %1",
                 u"sparky-stereo-gpu-record [--root DIR] [--machines DIR] --apply-known | --show | --forget"
                 " | --set-best GPU [--copy-back true|false] [--model TEXT] [--measurement TEXT] | --copy-back true|false|unset"
                 " | --set-paint PROGRAM.desktop CARD cpu|batch|unset [--measurement TEXT]"_s)
        << '\n';
    return 2;
}

// The machine's record could not be written: said, and kept for the people's sessions and the page
static int recordFailed(const QString &root)
{
    Problem problem;
    problem.key = u"machine-record"_s;
    problem.kind = u"record-write"_s;
    problem.detail = MachineRecord::systemFile(root);
    problem.command = u"sparky-stereo-gpu-record --apply-known"_s;
    problem.status = 3;
    problem.system = true;
    QTextStream(stderr) << "sparky-stereo-gpu-record: " << Problems::message(problem) << '\n';
    Problems::keep(problem, Problems::systemDir(root));
    return 3;
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
    QString keepKey;
    QString clearKey;
    QString paintProgram;
    QString paintGpu;
    QString paintWay;
    QString status;
    QString output;
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
        } else if (arg == u"--set-paint"_s) {
            action = arg;
            paintProgram = value();
            paintGpu = value().toLower();
            paintWay = value().toLower();
        } else if (arg == u"--copy-back"_s) {
            copyBack = value();
            if (copyBack.isEmpty()) {
                return usage(i18nc("@info:shell --copy-back, true, false and unset stay as they are", "--copy-back needs true, false or unset"));
            }
        } else if (arg == u"--model"_s) {
            model = value();
        } else if (arg == u"--measurement"_s) {
            measurement = value();
        } else if (arg == u"--keep"_s) {
            action = arg;
            keepKey = value();
        } else if (arg == u"--clear"_s) {
            action = arg;
            clearKey = value();
        } else if (arg == u"--status"_s) {
            status = value();
        } else if (arg == u"--output"_s) {
            output = value();
        } else {
            return usage(i18nc("@info:shell %1 is the argument given", "Unknown argument %1", arg));
        }
    }
    std::optional<bool> copy;
    if (!copyBack.isEmpty() && copyBack != u"unset"_s) {
        copy = GraphicsSettings::parseBool(copyBack);
        if (!copy.has_value()) {
            return usage(i18nc("@info:shell %1 is what was given; true and false stay as they are", "Not true or false: %1", copyBack));
        }
    }
    if (action.isEmpty() && !copyBack.isEmpty()) {
        action = u"--copy-back"_s;
    }
    QTextStream out(stdout);

    if (action == u"--keep"_s || action == u"--clear"_s) {
        // the steps the maintainer scripts say and keep (ORDER 345's way: the package configures, the problem stays shown)
        const QString key = action == u"--keep"_s ? keepKey : clearKey;
        if (key != u"systemd-reload"_s) {
            return usage(i18nc("@info:shell %1 is what was given; systemd-reload stays as it is", "Not a step: %1 (systemd-reload)", key));
        }
        if (action == u"--clear"_s) {
            return Problems::clear(key, Problems::systemDir(root)) ? 0 : 3;
        }
        bool ok = false;
        Problem problem;
        problem.key = key;
        problem.kind = key;
        problem.status = status.toInt(&ok);
        if (!ok) {
            return usage(i18nc("@info:shell --keep, --status and N stay as they are", "--keep needs --status N"));
        }
        problem.command = u"systemctl daemon-reload"_s;
        problem.output = output.right(4000);
        problem.system = true;
        QTextStream(stderr) << "sparky-stereo-gpu-record: " << Problems::message(problem) << '\n';
        return Problems::keep(problem, Problems::systemDir(root)) ? 0 : 3;
    }
    if (action == u"--apply-known"_s) {
        const auto done = [&root](const char *word) {
            QTextStream(stdout) << word << '\n';
            // the record is right again: its kept problem goes
            return Problems::clear(u"machine-record"_s, Problems::systemDir(root)) ? 0 : 3;
        };
        switch (RecordWriter::applyKnown(root, machines)) {
        case RecordWriter::Result::Written:
            return done("written");
        case RecordWriter::Result::Unchanged:
            return done("unchanged");
        case RecordWriter::Result::Kept:
            return done("kept");
        case RecordWriter::Result::Removed:
            return done("removed");
        case RecordWriter::Result::NothingKnown:
            return done("nothing-known");
        case RecordWriter::Result::Failed:
            break;
        }
        return recordFailed(root);
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
        // ORDER 554: the way of painting windows measured for each program on each card
        const PaintRecord paint = PaintRecord::readFile(file);
        for (const PaintProgramRow &row : paint.programs) {
            out << "paint " << row.program << ' ' << row.gpu << ' ' << row.way << '\n';
        }
        out << "paint-origin=" << (paint.origin.isEmpty() && !paint.isEmpty() ? u"hand"_s : paint.origin) << '\n';
        return 0;
    }
    if (action == u"--set-paint"_s) {
        // what a measurement on this machine found for a program on a card: Automatic on the Graphics page follows it
        if (!paintProgram.endsWith(u".desktop"_s) || paintProgram.size() < 9 || paintProgram.contains(u'/')) {
            return usage(i18nc("@info:shell %1 is what was given; the example stays as it is", "Not a program's desktop entry: %1 (as org.kde.konsole.desktop)", paintProgram));
        }
        if (!PaintRecord::validGpuKey(paintGpu)) {
            return usage(i18nc("@info:shell %1 is what was given; the example stays as it is", "Not a graphics card: %1 (as 1002:6660)", paintGpu));
        }
        if (paintWay != u"unset"_s && paintWay != u"cpu"_s && paintWay != u"batch"_s) {
            return usage(i18nc("@info:shell %1 is what was given; cpu, batch and unset stay as they are", "Not a way of painting: %1 (cpu, batch or unset)", paintWay));
        }
        if (!RecordWriter::writePaint(root, paintProgram, paintGpu, paintWay == u"unset"_s ? QString() : paintWay, measurement)) {
            QTextStream(stderr) << "sparky-stereo-gpu-record: " << i18nc("@info:shell %1 is a file", "cannot write %1", MachineRecord::systemFile(root)) << '\n';
            return 3;
        }
        return 0;
    }
    if (action == u"--set-best"_s) {
        if (!MachineRecord::validGpu(best.trimmed().toLower())) {
            return usage(i18nc("@info:shell %1 is what was given; the two examples stay as they are", "Not a GPU: %1 (pci-0000:03:00.0 or 1002:6660)", best));
        }
        if (!RecordWriter::writeMeasured(root, best, copy, model, measurement)) {
            QTextStream(stderr) << "sparky-stereo-gpu-record: " << i18nc("@info:shell %1 is a file", "cannot write %1", MachineRecord::systemFile(root)) << '\n';
            return 3;
        }
        return 0;
    }
    if (action == u"--copy-back"_s) {
        if (!RecordWriter::writeCopyBack(root, copy)) {
            QTextStream(stderr) << "sparky-stereo-gpu-record: " << i18nc("@info:shell %1 is a file", "cannot write %1", MachineRecord::systemFile(root)) << '\n';
            return 3;
        }
        return 0;
    }
    if (action == u"--forget"_s) {
        return RecordWriter::forget(root) ? 0 : 3;
    }
    return usage(i18nc("@info:shell", "Nothing to do"));
}
