// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

// sparky-stereo-gpu-env: what the Graphics page decides, for programs that start programs.
//
//   sparky-stereo-gpu-env [--category players|games|browsers|other | --app ID.desktop|/path/to/file.desktop | --choice auto|profile|integrated|discrete|pci-...]
//                         [--3d] [--profile power-saver|balanced|performance] [--root DIR]
//                         [--print env|gpu|render-node|card-node|id|reason] [--shell]
//   sparky-stereo-gpu-env --session     the KWIN_DRM_DEVICES line for the next login, nothing when Automatic
//   sparky-stereo-gpu-env --list        the GPUs, one line each (--json for a machine reader)
//
// --3d: the program presents 3D, so Automatic is the GPU measured best on this machine (the machine record,
// sparky-stereo-gpu-record), whatever the power profile, as it always is for players.
//
// Exit status: 0 done, 1 no usable GPU, 2 wrong arguments.

#include "appentries.h"
#include "gpuinventory.h"
#include "graphicssettings.h"
#include "machinerecord.h"
#include "powerprofiles.h"
#include "resolver.h"

#include <QCoreApplication>
#include <QDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
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
    err << problem << "\nUsage: sparky-stereo-gpu-env [--category C | --app ID | --choice X] [--3d] [--profile P] [--root DIR] [--print what] [--shell] | --session | --list [--json]\n";
    return 2;
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
        } else {
            return usage(u"Unknown argument %1"_s.arg(arg));
        }
    }

    const QList<Gpu> gpus = GpuInventory::read(root);
    const GraphicsSettings settings;
    const PowerProfile powerProfile = profile.isEmpty() ? PowerProfiles::active() : powerProfileFromString(profile);
    const MachineRecord record = MachineRecord::read();
    const Resolver resolver(gpus, settings.mainGpu(), powerProfile, record.bestGpu);
    QTextStream out(stdout);

    if (session) {
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
    if (!appId.isEmpty()) {
        const AppEntry entry = QDir::isAbsolutePath(appId) ? AppEntries::fromFile(appId) : AppEntries::fromEnvironment().find(appId);
        if (entry.id.isEmpty()) {
            return usage(u"No desktop entry %1"_s.arg(appId));
        }
        resolution = resolver.resolveApp(entry, settings, stereo);
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
    }
    if (resolution.gpuIndex < 0) {
        return 1;
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
