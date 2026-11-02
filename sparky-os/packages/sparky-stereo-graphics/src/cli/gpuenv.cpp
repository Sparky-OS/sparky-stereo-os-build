// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

// sparky-stereo-gpu-env: what the Graphics page decides, for programs that start programs.
//
//   sparky-stereo-gpu-env [--category players|games|browsers|other | --app ID.desktop|/path/to/file.desktop | --choice auto|profile|integrated|discrete|pci-...]
//                         [--3d] [--profile power-saver|balanced|performance] [--root DIR]
//                         [--print env|gpu|render-node|card-node|id|reason] [--shell]
//                         [--ask]
//   sparky-stereo-gpu-env --session     the KWIN_DRM_DEVICES line for the next login, nothing when Automatic
//   sparky-stereo-gpu-env --list        the GPUs, one line each (--json for a machine reader)
//   sparky-stereo-gpu-env --problems    what is kept: each choice that cannot be used, each failed step of the package
//   sparky-stereo-gpu-env --notify      the session's side: each kept problem as a notification (once per session)
//
// --3d: the program presents 3D, so Automatic is the GPU measured best on this machine (the machine record,
// sparky-stereo-gpu-record), whatever the power profile, as it always is for players.
//
// A choice that cannot be used (the chosen GPU is not here, has no driver or render node, the account may not open it, no
// GPU of the chosen kind, the power profile it follows could not be read) is never replaced by another GPU (Daniel,
// 2026-11-01): what failed, why and what to do go to stderr in the person's language, with the GPUs that can draw now as
// explicit choices, and the exit status is 4. A saved choice's problem is kept until the choice works again
// ($XDG_STATE_HOME/sparky-stereo-graphics/problems) and shown at login. --ask, with a display: kdialog asks which of the
// other GPUs the program starts on this time; the answer's variables are printed, nothing is saved.
//
// Exit status: 0 done (no variables when the computer has no GPU and nothing was chosen), 1 no GPU to print (--print gpu,
// render-node, card-node, id, reason on a computer without one), 2 wrong arguments, 4 the choice cannot be used.

#include "appentries.h"
#include "gpuinventory.h"
#include "graphicssettings.h"
#include "machinerecord.h"
#include "notifier.h"
#include "powerprofiles.h"
#include "problems.h"
#include "resolver.h"

#include <KLocalizedString>

#include <QCoreApplication>
#include <QDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QStandardPaths>
#include <QTextStream>

using namespace Qt::StringLiterals;
using namespace SparkyGraphics;

static QString shellQuote(const QString &text)
{
    QString quoted = text;
    quoted.replace(u'\'', u"'\\''"_s);
    return u'\'' + quoted + u'\'';
}

static int usage(const QString &problem)
{
    QTextStream err(stderr);
    err << problem
        << "\nUsage: sparky-stereo-gpu-env [--category C | --app ID | --choice X] [--3d] [--profile P] [--root DIR] [--print what] [--shell] [--ask] | --session | "
           "--list [--json] | --problems | --notify\n";
    return 2;
}

// What failed, why and what to do, then the GPUs that can draw now, each as the explicit choice it is
static void tell(const Problem &problem, bool program)
{
    QTextStream err(stderr);
    err << Problems::message(problem) << '\n';
    QList<Alternative> others;
    for (const Alternative &gpu : problem.alternatives) {
        if (gpu.id != problem.requested) {
            others << gpu;
        }
    }
    if (others.isEmpty()) {
        return;
    }
    err << i18nc("@info", "GPUs that can draw now:") << '\n';
    for (const Alternative &gpu : std::as_const(others)) {
        err << "  " << gpu.id << "  " << gpu.name << '\n';
    }
    if (program) {
        err << i18nc("@info ID and COMMAND stay as they are", "To start a program on one of them this time: sparky-stereo-gpu-run --choice ID COMMAND") << '\n';
    }
}

// --ask: which GPU the program starts on this time, as the person answers; empty when there is no display, no kdialog,
// no other GPU or the person does not start it
static QString ask(const Problem &problem)
{
    if (qEnvironmentVariableIsEmpty("WAYLAND_DISPLAY") && qEnvironmentVariableIsEmpty("DISPLAY")) {
        return {};
    }
    const QString kdialog = QStandardPaths::findExecutable(u"kdialog"_s);
    if (kdialog.isEmpty()) {
        QTextStream(stderr) << "sparky-stereo-gpu-env: kdialog is not installed, so the choice cannot be asked\n";
        return {};
    }
    QStringList args = {u"--title"_s,
                        Problems::title(problem),
                        u"--ok-label"_s,
                        i18nc("@action:button", "Start"),
                        u"--cancel-label"_s,
                        i18nc("@action:button", "Do not start"),
                        u"--radiolist"_s,
                        Problems::message(problem) + u"\n\n"_s + i18nc("@label", "Start it this time on:")};
    bool first = true;
    for (const Alternative &gpu : problem.alternatives) {
        if (gpu.id != problem.requested) {
            args << gpu.id << gpu.name << (first ? u"on"_s : u"off"_s);
            first = false;
        }
    }
    if (first) {
        QProcess::execute(kdialog, {u"--title"_s, Problems::title(problem), u"--error"_s, Problems::message(problem)});
        return {};
    }
    QProcess dialog;
    dialog.start(kdialog, args);
    if (!dialog.waitForFinished(-1) || dialog.exitStatus() != QProcess::NormalExit || dialog.exitCode() != 0) {
        return {};
    }
    return QString::fromUtf8(dialog.readAllStandardOutput()).trimmed();
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    const QStringList args = app.arguments().mid(1);

    QString category;
    QString appId;
    QString choice;
    QString profile;
    QString print = u"env"_s;
    QString root = qEnvironmentVariable("SPARKY_STEREO_GRAPHICS_ROOT", u"/"_s);
    bool shell = false;
    bool session = false;
    bool list = false;
    bool json = false;
    bool stereo = false;
    bool askChoice = false;
    bool problems = false;
    bool notify = false;
    for (int i = 0; i < args.size(); ++i) {
        const QString &arg = args.at(i);
        const auto value = [&]() -> QString {
            return i + 1 < args.size() ? args.at(++i) : QString();
        };
        if (arg == u"--category"_s) {
            category = value();
        } else if (arg == u"--app"_s) {
            appId = value();
        } else if (arg == u"--choice"_s) {
            choice = value();
        } else if (arg == u"--profile"_s) {
            profile = value();
        } else if (arg == u"--root"_s) {
            root = value();
        } else if (arg == u"--print"_s) {
            print = value();
        } else if (arg == u"--shell"_s) {
            shell = true;
        } else if (arg == u"--session"_s) {
            session = true;
        } else if (arg == u"--list"_s) {
            list = true;
        } else if (arg == u"--json"_s) {
            json = true;
        } else if (arg == u"--3d"_s) {
            stereo = true;
        } else if (arg == u"--ask"_s) {
            askChoice = true;
        } else if (arg == u"--problems"_s) {
            problems = true;
        } else if (arg == u"--notify"_s) {
            notify = true;
        } else {
            return usage(u"Unknown argument %1"_s.arg(arg));
        }
    }

    if (notify) {
        Notifier notifier(root);
        return notifier.run();
    }
    QTextStream out(stdout);
    if (problems) {
        for (const Problem &problem : Problems::all(root)) {
            out << problem.file << '\n' << "  " << problem.time << "  " << Problems::message(problem) << '\n';
        }
        return 0;
    }

    // An explicit profile is honoured; a name that is no profile is a wrong argument, never Balanced in its place
    ProfileReading powerProfile;
    if (profile.isEmpty()) {
        powerProfile = PowerProfiles::read();
    } else if (const auto named = powerProfileFromString(profile)) {
        powerProfile = ProfileReading(*named);
    } else {
        return usage(u"Not a power profile: %1 (power-saver, balanced or performance)"_s.arg(profile));
    }
    const QList<Gpu> gpus = GpuInventory::read(root);
    const GraphicsSettings settings;
    const MachineRecord record = MachineRecord::read();
    const Resolver resolver(gpus, settings.mainGpu(), powerProfile, record.bestGpu);

    if (session) {
        // The saved main GPU that cannot draw is said and kept, never replaced: KWin's own order draws this login, as
        // nothing else could show the person why, and the notification at login offers the other GPUs
        const Resolution main = resolver.mainProblem();
        if (!main.problem.isEmpty()) {
            const Problem problem = Problems::fromResolution(u"main-gpu"_s, main, gpus, root);
            Problems::keep(problem, Problems::userDir());
            tell(problem, false);
            return 4;
        }
        Problems::clear(u"main-gpu"_s, Problems::userDir());
        const QString devices = resolver.kwinDrmDevices();
        if (!devices.isEmpty()) {
            out << "export KWIN_DRM_DEVICES=" << shellQuote(devices) << "\n";
        }
        return 0;
    }

    if (list) {
        const int main = resolver.mainIndex();
        const int measured = resolver.measuredIndex();
        QJsonArray array;
        for (int i = 0; i < gpus.size(); ++i) {
            const Gpu &gpu = gpus.at(i);
            QJsonArray connectors;
            for (const Connector &connector : gpu.connectors) {
                connectors.append(QJsonObject{{u"name"_s, connector.name}, {u"connected"_s, connector.connected}, {u"monitor"_s, connector.monitor}});
            }
            const QString kind = gpu.kind == GpuKind::Integrated ? u"integrated"_s : u"discrete"_s;
            if (json) {
                array.append(QJsonObject{{u"id"_s, gpu.id}, {u"name"_s, gpu.name}, {u"vendor"_s, gpu.vendor}, {u"chip"_s, gpu.chip}, {u"driver"_s, gpu.driver},
                                         {u"kind"_s, kind}, {u"cardNode"_s, gpu.cardNode}, {u"renderNode"_s, gpu.renderNode}, {u"canRender"_s, gpu.canRender},
                                         {u"bootVga"_s, gpu.bootVga}, {u"main"_s, i == main}, {u"measuredBest"_s, i == measured},
                                         {u"connectors"_s, connectors}});
            } else {
                out << gpu.id << '\t' << kind << '\t' << gpu.driver << '\t' << gpu.cardNode << '\t' << (gpu.canRender ? gpu.renderNode : u"-"_s) << '\t'
                    << (i == main ? u"main"_s : u"-"_s) << '\t' << gpu.name << '\n';
            }
        }
        if (json) {
            out << QJsonDocument(array).toJson(QJsonDocument::Compact) << '\n';
        }
        return gpus.isEmpty() ? 1 : 0;
    }

    Resolution resolution;
    QString saved; // the saved choice this answer comes from (its kind of program), whose problem is kept or cleared
    Category asked = Category::Other;
    if (!appId.isEmpty()) {
        const AppEntry entry = QDir::isAbsolutePath(appId) ? AppEntries::fromFile(appId) : AppEntries::fromEnvironment().find(appId);
        if (entry.id.isEmpty()) {
            return usage(u"No desktop entry %1"_s.arg(appId));
        }
        resolution = resolver.resolveApp(entry, settings, stereo);
        asked = entry.category;
        if (entry.preference == AppPreference::Unset) {
            saved = categoryKey(entry.category).toLower();
        }
    } else if (!choice.isEmpty()) {
        if (!GraphicsSettings::validChoice(choice)) {
            return usage(u"Not a choice: %1"_s.arg(choice));
        }
        resolution = resolver.resolveChoice(choice, Category::Other, stereo);
    } else {
        const QList<Category> categories = allCategories();
        Category selected = Category::Other;
        bool known = category.isEmpty();
        for (Category candidate : categories) {
            if (categoryKey(candidate).toLower() == category.toLower()) {
                selected = candidate;
                known = true;
            }
        }
        if (!known) {
            return usage(u"Not a category: %1"_s.arg(category));
        }
        resolution = resolver.resolveCategory(selected, settings, stereo);
        asked = selected;
        saved = categoryKey(selected).toLower();
    }
    if (!resolution.problem.isEmpty()) {
        const Problem problem = Problems::fromResolution(saved.isEmpty() ? categoryKey(asked).toLower() : saved, resolution, gpus, root, powerProfile);
        if (!saved.isEmpty()) {
            Problems::keep(problem, Problems::userDir());
        }
        tell(problem, true);
        const QString picked = askChoice ? ask(problem) : QString();
        if (picked.isEmpty()) {
            return 4;
        }
        // the person's answer for this start only: their saved choice stays, and so does its problem
        resolution = resolver.resolveChoice(picked, asked, stereo);
        if (!resolution.problem.isEmpty()) {
            return 4;
        }
    } else if (!saved.isEmpty()) {
        Problems::clear(saved, Problems::userDir());
    }
    if (resolution.gpuIndex < 0) {
        // no GPU at all and nothing chosen: no variable to set, which is the whole answer; there is no GPU to name
        return print == u"env"_s ? 0 : 1;
    }
    const Gpu &gpu = gpus.at(resolution.gpuIndex);
    if (print == u"env"_s) {
        for (const QString &line : resolution.environment) {
            if (shell) {
                const int eq = line.indexOf(u'=');
                out << "export " << line.left(eq) << '=' << shellQuote(line.mid(eq + 1)) << '\n';
            } else {
                out << line << '\n';
            }
        }
    } else if (print == u"gpu"_s) {
        out << gpu.name << '\n';
    } else if (print == u"render-node"_s) {
        out << gpu.renderNode << '\n';
    } else if (print == u"card-node"_s) {
        out << gpu.cardNode << '\n';
    } else if (print == u"id"_s) {
        out << gpu.id << '\n';
    } else if (print == u"reason"_s) {
        out << resolution.reason << '\n';
    } else {
        return usage(u"Not something to print: %1"_s.arg(print));
    }
    return 0;
}
