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
//   sparky-stereo-gpu-env --notify      starts the session's notifier (sparky-stereo-problems-plasma), which shows the
//                                       kept problems
//   sparky-stereo-gpu-env --use KEY GPU "Use NAME" of a kept problem: saves GPU as the person's choice for KEY
//   sparky-stereo-gpu-env --died UNIT   run by the session's systemd when an application's service fails (the drop-in
//                                       app-.service.d/10-sparky-stereo-graphics.conf, ORDER 467): when a program this page
//                                       sent to a GPU stopped right after it started, say so and keep it
//   sparky-stereo-gpu-env --survived UNIT  run when such a service ends cleanly: a program that ran past the window on
//                                       its GPU ends the kept death of that program
//   sparky-stereo-gpu-env --use-app ID GPU  "Use NAME" of a kept death: that program's own desktop entry key (the
//                                       desktop's GPU, or the discrete one), nothing else changes
//   sparky-stereo-gpu-env --paint-failed PROGRAM CODE [WORDS]  run by a program of the edition's Qt that was asked to
//                                       paint its windows on the graphics card and could not (ORDER 518): say and keep it
//   sparky-stereo-gpu-env --paint-ok PROGRAM   run by such a program when the painting did start: its kept failure is over
//   sparky-stereo-gpu-env --use-paint TARGET WAY  "Paint on the processor" of a kept problem, or any way of painting for a
//                                       program (ID.desktop) or a kind (players, games, browsers, other): saved as the
//                                       person's choice; WAY is auto, cpu, batch or opengl
//
// Paint windows (ORDER 518): with the GPU's variables the answer carries QT_WIDGETS_GPU_PAINT=batch or =opengl when the
// program, its kind or the machine's measurement asks for painting on the graphics card, and QT_WIDGETS_GPU_PAINT_TELL,
// the command the program runs when that painting cannot start. Nothing is added for the processor, which is how every
// Qt paints. --print paint names the way (cpu, batch, opengl), --print paint-reason why, --print paint-env only the
// painting's variables. A way that cannot be had (no graphics processor that can draw, a Qt without the painting) is
// said and kept, and the program starts and paints on the processor: the exit status stays 0.
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
// render-node, card-node, id, reason on a computer without one), 2 wrong arguments, 4 the choice cannot be used, 5 Automatic
// cannot place the program now (browsers while the power profile they follow cannot be read): said and kept as for 4, but
// the person chose nothing, so Plasma's launcher starts the program as the session would (ORDER 346g), and
// sparky-stereo-gpu-run asks or does not start it, as for 4.

#include "appentries.h"
#include "gpuinventory.h"
#include "graphicssettings.h"
#include "launchwatch.h"
#include "machinerecord.h"
#include "paint.h"
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
    // the synopsis stays as it is: options and their arguments are the same in every language
    err << problem << '\n'
        << i18nc("@info:shell %1 is the command's synopsis, which stays as it is", "Usage: %1",
                 u"sparky-stereo-gpu-env [--category C | --app ID | --choice X] [--3d] [--profile P] [--root DIR] [--print what] [--shell] [--ask] | "
                 "--session | --list [--json] | --problems | --notify | --use KEY GPU | --use-app ID GPU | --died UNIT | --survived UNIT | "
                 "--paint-failed PROGRAM CODE [WORDS] | --paint-ok PROGRAM | --use-paint TARGET WAY"_s)
        << '\n';
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
        QTextStream(stderr) << "sparky-stereo-gpu-env: " << i18nc("@info:shell kdialog stays as it is", "kdialog is not installed, so the choice cannot be asked") << '\n';
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


// ORDER 467. A program this page sent to a GPU that stops right after it starts is told, never started again on another
// GPU: systemd (the session's manager runs every application as app-NAME@ID.service) knows how it ended, and runs this
// when the service fails. Not told: a program the page did not send anywhere, one that ended cleanly (a launcher, a
// single-instance program handing over to the one already running, a person closing it), one the person or the system
// killed (SIGKILL), and one that stopped after the window ([Launch] DiedWithin, 10 s).
static int died(const QString &unit, const QString &root)
{
    QTextStream err(stderr);
    const QString name = LaunchWatch::appNameOf(unit);
    const int window = LaunchWatch::window();
    if (name.isEmpty() || window == 0) {
        return 0;
    }
    const UnitFacts facts = LaunchWatch::read(unit);
    if (!facts.found) {
        err << "sparky-stereo-gpu-env: " << i18nc("@info:shell %1 is a systemd unit, %2 why not", "Could not ask systemd how %1 ended: %2", unit, facts.error) << '\n';
        return 3;
    }
    if (facts.result == u"success"_s) {
        return 0;
    }
    QString how;
    QString word;
    if (facts.result == u"core-dump"_s || (facts.result == u"signal"_s && facts.exitCode != 9 && facts.exitCode != 15 && facts.exitCode != 2 && facts.exitCode != 1 && facts.exitCode != 13)) {
        how = u"crash"_s;
    } else if (facts.result == u"signal"_s) {
        return 0;
    } else if (facts.result == u"exit-code"_s) {
        how = u"exit"_s;
    } else {
        how = u"result"_s;
        word = facts.result;
    }
    const double seconds = facts.seconds();
    if (seconds < 0 || seconds > window) {
        return 0;
    }
    const AppEntry entry = AppEntries::fromFile(facts.sourcePath);
    if (entry.id.isEmpty()) {
        return 0;
    }
    const QList<Gpu> gpus = GpuInventory::read(root);
    const GraphicsSettings settings;
    const MachineRecord record = MachineRecord::read();
    const Resolver resolver(gpus, settings.mainGpu(), PowerProfiles::read(), record.bestGpu);
    const Resolution resolution = resolver.resolveApp(entry, settings, false);
    if (!resolution.problem.isEmpty() || resolution.gpuIndex < 0 || resolution.environment.isEmpty()) {
        return 0;
    }
    bool sent = true;
    for (const QString &line : resolution.environment) {
        sent = sent && facts.environment.contains(line);
    }
    if (!sent && entry.preference == AppPreference::OtherGpu) {
        // KDE's own key, which KIO applies with its own variables
        for (const QString &line : std::as_const(facts.environment)) {
            sent = sent || line.startsWith(u"DRI_PRIME="_s) || line.startsWith(u"__NV_PRIME_RENDER_OFFLOAD="_s);
        }
    }
    if (!sent) {
        return 0;
    }
    // the GPUs this program can be sent to instead, as its own desktop entry can say it
    QList<int> instead;
    for (AppPreference preference : {AppPreference::MainGpu, AppPreference::OtherGpu}) {
        AppEntry other = entry;
        other.preference = preference;
        const Resolution r = resolver.resolveApp(other, settings, false);
        if (r.problem.isEmpty() && r.gpuIndex >= 0 && r.gpuIndex != resolution.gpuIndex && gpus.at(r.gpuIndex).usable() && !instead.contains(r.gpuIndex)) {
            instead << r.gpuIndex;
        }
    }
    const Problem problem = Problems::fromDeath(name, entry.id, entry.name, how, facts.exitCode, word, LaunchWatch::lastLines(unit), resolution.gpuIndex, gpus, instead);
    err << "sparky-stereo-gpu-env: " << Problems::message(problem) << '\n';
    return Problems::keep(problem, Problems::userDir()) ? 0 : 3;
}

// A program that ran past the window on its GPU and ended cleanly works there: the kept death of it is over
static int survived(const QString &unit)
{
    const QString name = LaunchWatch::appNameOf(unit);
    if (name.isEmpty()) {
        return 0;
    }
    const UnitFacts facts = LaunchWatch::read(unit);
    if (!facts.found || facts.result != u"success"_s || facts.seconds() < qMax(LaunchWatch::window(), 1)) {
        return 0;
    }
    return Problems::clear(LaunchWatch::keyOf(name), Problems::userDir()) ? 0 : 3;
}

// "Use NAME" of a kept death: the desktop entry's own PrefersNonDefaultGPU, as the page writes it. The desktop's GPU is
// false and the discrete GPU is true; another GPU has no key, so it is chosen on the page
static int useApp(const QString &id, const QString &gpuId, const QString &root)
{
    const AppEntry entry = AppEntries::fromEnvironment().find(id);
    if (entry.id.isEmpty()) {
        return usage(i18nc("@info:shell %1 is an application ID", "No desktop entry %1", id));
    }
    const QList<Gpu> gpus = GpuInventory::read(root);
    const GraphicsSettings settings;
    const MachineRecord record = MachineRecord::read();
    const Resolver resolver(gpus, settings.mainGpu(), PowerProfiles::read(), record.bestGpu);
    for (AppPreference preference : {AppPreference::MainGpu, AppPreference::OtherGpu}) {
        AppEntry other = entry;
        other.preference = preference;
        const Resolution r = resolver.resolveApp(other, settings, false);
        if (r.problem.isEmpty() && r.gpuIndex >= 0 && gpus.at(r.gpuIndex).id == gpuId) {
            if (!AppEntries::fromEnvironment().setPreference(entry.id, preference)) {
                QTextStream(stderr) << "sparky-stereo-gpu-env: " << i18nc("@info", "The graphics settings could not be saved.") << '\n';
                return 3;
            }
            QString name = entry.id;
            name.chop(8); // ".desktop"
            return Problems::clear(LaunchWatch::keyOf(name), Problems::userDir()) ? 0 : 3;
        }
    }
    QTextStream(stderr) << "sparky-stereo-gpu-env: "
                        << i18nc("@info", "That GPU cannot be chosen for one program here. Choose it in System Settings, Graphics.") << '\n';
    return 4;
}

// ORDER 518. A program asked to paint on the graphics card that could not start that painting says so itself (the
// edition's Qt runs this through QT_WIDGETS_GPU_PAINT_TELL), since only the program knows: it painted on the processor,
// which is said and kept until the painting starts (--paint-ok) or the person chooses another way
static int paintFailed(const QString &program, const QString &code, const QString &words)
{
    static const QStringList known = {u"no-opengl"_s, u"software"_s, u"library"_s, u"context"_s};
    if (program.isEmpty() || !known.contains(code)) {
        // "flat-pair" and anything a later Qt tells are the program's own warning, not kept here
        return 0;
    }
    QString id = program.endsWith(u".desktop"_s) ? program : program + u".desktop"_s;
    const AppEntry entry = AppEntries::fromEnvironment().find(id);
    const Problem problem = Problems::fromPaint(Paint::runKey(program), entry.id, entry.id.isEmpty() ? program : entry.name,
                                                qEnvironmentVariable("QT_WIDGETS_GPU_PAINT"), code, words);
    QTextStream(stderr) << "sparky-stereo-gpu-env: " << Problems::message(problem) << '\n';
    return Problems::keep(problem, Problems::userDir()) ? 0 : 3;
}

static int usePaint(const QString &target, const QString &way)
{
    PaintSettings settings;
    QString key;
    if (target.endsWith(u".desktop"_s)) {
        if (!PaintSettings::validKindChoice(way)) {
            return usage(i18nc("@info:shell %1 is what was given; auto, cpu, batch and opengl stay as they are", "Not a way of painting: %1 (auto, cpu, batch or opengl)", way));
        }
        settings.setProgramChoice(target, way == u"auto"_s ? QString() : way);
        key = Paint::problemKey(Category::Other, target);
    } else {
        bool found = false;
        for (Category category : allCategories()) {
            if (categoryKey(category).toLower() == target.toLower()) {
                if (!PaintSettings::validKindChoice(way)) {
                    return usage(i18nc("@info:shell %1 is what was given; auto, cpu, batch and opengl stay as they are", "Not a way of painting: %1 (auto, cpu, batch or opengl)", way));
                }
                settings.setKindChoice(category, way);
                key = Paint::problemKey(category, QString());
                found = true;
            }
        }
        if (!found) {
            return usage(i18nc("@info:shell %1 is the KEY given to --use: main-gpu or a kind of program", "Unknown kind %1", target));
        }
    }
    if (!settings.save()) {
        QTextStream(stderr) << "sparky-stereo-gpu-env: " << i18nc("@info", "The graphics settings could not be saved.") << '\n';
        return 3;
    }
    bool ok = Problems::clear(key, Problems::userDir());
    if (target.endsWith(u".desktop"_s)) {
        ok = Problems::clear(Paint::runKey(target), Problems::userDir()) && ok;
    }
    return ok ? 0 : 3;
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
    QString useKey;
    QString useGpu;
    QString diedUnit;
    QString survivedUnit;
    QString useApp_;
    QString useAppGpu;
    QStringList paintFailedArgs;
    QString paintOk;
    QStringList usePaintArgs;
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
        } else if (arg == u"--died"_s) {
            diedUnit = value();
        } else if (arg == u"--survived"_s) {
            survivedUnit = value();
        } else if (arg == u"--use-app"_s) {
            useApp_ = value();
            useAppGpu = value();
        } else if (arg == u"--paint-failed"_s) {
            paintFailedArgs = args.mid(i + 1, 3);
            i = args.size();
        } else if (arg == u"--paint-ok"_s) {
            paintOk = value();
        } else if (arg == u"--use-paint"_s) {
            usePaintArgs << value();
            usePaintArgs << value();
        } else if (arg == u"--use"_s) {
            useKey = value();
            useGpu = value();
        } else {
            return usage(i18nc("@info:shell %1 is the argument given", "Unknown argument %1", arg));
        }
    }

    if (!diedUnit.isEmpty()) {
        return died(diedUnit, root);
    }
    if (!survivedUnit.isEmpty()) {
        return survived(survivedUnit);
    }
    if (!useApp_.isEmpty()) {
        return useApp(useApp_, useAppGpu, root);
    }
    if (!paintFailedArgs.isEmpty()) {
        return paintFailed(paintFailedArgs.value(0), paintFailedArgs.value(1), paintFailedArgs.value(2));
    }
    if (!paintOk.isEmpty()) {
        return Problems::clear(Paint::runKey(paintOk), Problems::userDir()) ? 0 : 3;
    }
    if (!usePaintArgs.isEmpty()) {
        if (usePaintArgs.value(0).isEmpty() || usePaintArgs.value(1).isEmpty()) {
            return usage(i18nc("@info:shell --use-paint, TARGET and WAY stay as they are", "--use-paint needs TARGET and WAY"));
        }
        return usePaint(usePaintArgs.at(0), usePaintArgs.at(1));
    }
    if (notify) {
        // the edition's one engine and its session notifier show the kept problems (ORDER 350): this starts it
        return QProcess::execute(u"systemctl"_s, {u"--user"_s, u"start"_s, u"sparky-stereo-problems-notifier.service"_s});
    }
    if (!useKey.isEmpty()) {
        // "Use NAME" of a kept problem: the person's explicit choice of a GPU that can draw, saved; the problem of the
        // old choice is over
        if (useGpu.isEmpty()) {
            return usage(i18nc("@info:shell --use, KEY and GPU stay as they are", "--use needs KEY and GPU"));
        }
        GraphicsSettings settings;
        if (useKey == u"main-gpu"_s) {
            settings.setMainGpu(useGpu);
        } else {
            bool found = false;
            for (Category category : allCategories()) {
                if (categoryKey(category).toLower() == useKey) {
                    settings.setRenderChoice(category, useGpu);
                    found = true;
                }
            }
            if (!found) {
                return usage(i18nc("@info:shell %1 is the KEY given to --use: main-gpu or a kind of program", "Unknown kind %1", useKey));
            }
        }
        if (!settings.save()) {
            QTextStream(stderr) << "sparky-stereo-gpu-env: " << i18nc("@info", "The graphics settings could not be saved.") << '\n';
            return 3;
        }
        return Problems::clear(useKey, Problems::userDir()) ? 0 : 3;
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
        return usage(i18nc("@info:shell %1 is what was given; power-saver, balanced and performance stay as they are",
                            "Not a power profile: %1 (power-saver, balanced or performance)", profile));
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
    QString paintId; // the program whose windows are painted, when one is known
    QString paintName;
    if (!appId.isEmpty()) {
        const AppEntry entry = QDir::isAbsolutePath(appId) ? AppEntries::fromFile(appId) : AppEntries::fromEnvironment().find(appId);
        if (entry.id.isEmpty()) {
            return usage(i18nc("@info:shell %1 is an application ID", "No desktop entry %1", appId));
        }
        resolution = resolver.resolveApp(entry, settings, stereo);
        asked = entry.category;
        paintId = entry.id;
        paintName = entry.name;
        if (entry.preference == AppPreference::Unset) {
            saved = categoryKey(entry.category).toLower();
        }
    } else if (!choice.isEmpty()) {
        if (!GraphicsSettings::validChoice(choice)) {
            return usage(i18nc("@info:shell %1 is what was given to --choice", "Not a choice: %1", choice));
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
            return usage(i18nc("@info:shell %1 is what was given to --category", "Not a category: %1", category));
        }
        resolution = resolver.resolveCategory(selected, settings, stereo);
        asked = selected;
        saved = categoryKey(selected).toLower();
    }
    // Paint windows (ORDER 518): the way this program's Qt Widgets windows are painted, with what names it for the program
    PaintFacts paintFacts = PaintFacts::read(!resolver.usableIndices().isEmpty());
    const PaintSettings paintSettings;
    const PaintRecord paintRecord = PaintRecord::read();
    PaintResolution paint = Paint::resolve(asked, paintId, paintSettings, paintRecord, paintFacts);
    if (paint.way != PaintWay::Processor && paint.reason != u"session"_s) {
        paintFacts.qtPaintsOnGpu = PaintFacts::qtHasPainting();
        paint = Paint::resolve(asked, paintId, paintSettings, paintRecord, paintFacts);
    }
    if (paint.reason != u"session"_s && paint.asked != PaintWay::Processor) {
        const QString key = Paint::problemKey(asked, paintId);
        if (!paint.problem.isEmpty()) {
            // said and kept; the program starts and paints on the processor, which is what it does without this page
            const Problem problem = Problems::fromPaint(key, paintId.isEmpty() ? categoryKey(asked).toLower() : paintId, paintName, paintWayKey(paint.asked),
                                                        paint.problem, QString());
            Problems::keep(problem, Problems::userDir());
            QTextStream(stderr) << "sparky-stereo-gpu-env: " << Problems::message(problem) << '\n';
        } else {
            Problems::clear(key, Problems::userDir());
            // a failure this program told at an earlier start is kept until it tells that the painting started
            if (!paintId.isEmpty()) {
                const QString run = Paint::runKey(paintId);
                for (const Problem &kept : Problems::read(Problems::userDir())) {
                    if (kept.key == run) {
                        paint.environment << u"QT_WIDGETS_GPU_PAINT_TELL_OK=1"_s;
                    }
                }
            }
        }
    }
    const auto printPaint = [&out, &paint, shell]() {
        for (const QString &line : std::as_const(paint.environment)) {
            if (shell) {
                const int eq = line.indexOf(u'=');
                out << "export " << line.left(eq) << '=' << shellQuote(line.mid(eq + 1)) << '\n';
            } else {
                out << line << '\n';
            }
        }
    };
    if (print == u"paint"_s) {
        out << paintWayKey(paint.way) << '\n';
        return 0;
    }
    if (print == u"paint-reason"_s) {
        out << (paint.problem.isEmpty() ? paint.reason : paint.problem) << '\n';
        return 0;
    }
    if (print == u"paint-env"_s) {
        printPaint();
        return 0;
    }
    if (!resolution.problem.isEmpty()) {
        const Problem problem = Problems::fromResolution(saved.isEmpty() ? categoryKey(asked).toLower() : saved, resolution, gpus, root, powerProfile);
        if (!saved.isEmpty()) {
            Problems::keep(problem, Problems::userDir());
        }
        tell(problem, true);
        const QString picked = askChoice ? ask(problem) : QString();
        if (picked.isEmpty()) {
            // Automatic is a rule, not the person's choice: said apart, so a launcher never refuses a program the person
            // placed nowhere
            return resolution.requested == u"auto"_s ? 5 : 4;
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
        // (a way of painting set by hand in the session is the session's, so nothing is printed for it either)
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
        printPaint();
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
        return usage(i18nc("@info:shell %1 is what was given to --print", "Not something to print: %1", print));
    }
    return 0;
}
