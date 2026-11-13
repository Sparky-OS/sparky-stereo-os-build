// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "graphicskcm.h"
#include "vramsettings.h"
#include <KAuth/Action>
#include <KAuth/ExecuteJob>
#include <QJsonObject>
#include <QProcess>

#include <KLocalizedString>
#include <KPluginFactory>

#include <QDir>
#include <QFile>
#include <QRegularExpression>
#include <QStandardPaths>

using namespace Qt::StringLiterals;
using namespace SparkyGraphics;

K_PLUGIN_CLASS_WITH_JSON(GraphicsKcm, "kcm_sparkystereo_graphics.json")

static const int s_maxApps = 150;

GraphicsKcm::GraphicsKcm(QObject *parent, const KPluginMetaData &data)
    : KQuickConfigModule(parent, data)
    , m_root(qEnvironmentVariable("SPARKY_STEREO_GRAPHICS_ROOT", u"/"_s))
{
    setButtons(Apply | Default);
}

Resolver GraphicsKcm::resolver() const
{
    return Resolver(m_gpus, m_settings.mainGpu(), m_profile, m_record.bestGpu);
}

int GraphicsKcm::indexOf(const QString &id) const
{
    for (int i = 0; i < m_gpus.size(); ++i) {
        if (m_gpus.at(i).id == id) {
            return i;
        }
    }
    return -1;
}

QString GraphicsKcm::gpuLabel(int index) const
{
    if (index < 0 || index >= m_gpus.size()) {
        return {};
    }
    const Gpu &gpu = m_gpus.at(index);
    for (int i = 0; i < m_gpus.size(); ++i) {
        if (i != index && m_gpus.at(i).name == gpu.name) {
            return i18nc("@item GPU name, then its PCI address when two GPUs have the same name", "%1 (%2)", gpu.name, gpu.pciSlot);
        }
    }
    return gpu.name;
}

QString GraphicsKcm::categoryLabel(Category category) const
{
    switch (category) {
    case Category::Players:
        return i18nc("@label kind of program", "Players");
    case Category::Games:
        return i18nc("@label kind of program", "Games");
    case Category::Browsers:
        return i18nc("@label kind of program", "Browsers");
    case Category::Other:
        break;
    }
    return i18nc("@label kind of program", "Other programs");
}

QString GraphicsKcm::reasonText(const Resolution &resolution) const
{
    if (resolution.reason == u"measured-missing"_s) {
        return i18nc("@info", "the GPU measured best for this computer is not here now");
    }
    if (resolution.kindAbsent == u"integrated"_s) {
        return i18nc("@info %1 is the power profile's reason", "%1, and this computer has no integrated GPU that can draw", reasonTextOf(resolution.reason));
    }
    if (resolution.kindAbsent == u"discrete"_s) {
        return i18nc("@info %1 is the power profile's reason", "%1, and this computer has no discrete GPU that can draw", reasonTextOf(resolution.reason));
    }
    return reasonTextOf(resolution.reason);
}

QString GraphicsKcm::reasonTextOf(const QString &reason) const
{
    if (reason == u"only-gpu"_s) {
        return i18nc("@info", "the only GPU");
    }
    if (reason == u"profile:power-saver"_s) {
        return i18nc("@info", "power saver profile");
    }
    if (reason == u"profile:performance"_s) {
        return i18nc("@info", "performance profile");
    }
    if (reason == u"profile:balanced"_s) {
        return i18nc("@info", "balanced profile");
    }
    if (reason == u"desktop"_s) {
        return i18nc("@info", "the GPU that draws the desktop");
    }
    if (reason == u"app"_s) {
        return i18nc("@info", "the program's own setting");
    }
    if (reason == u"measured"_s) {
        return m_record.origin == u"shipped"_s ? i18nc("@info", "measured best for this model") : i18nc("@info", "measured best on this computer");
    }
    if (reason == u"unmeasured"_s) {
        return i18nc("@info", "not measured on this computer yet");
    }
    return i18nc("@info", "your choice");
}

void GraphicsKcm::load()
{
    m_vramProtection = m_savedVramProtection = VramSettings::enabled();
    m_gpus = GpuInventory::read(m_root);
    m_settings = GraphicsSettings();
    m_paint = PaintSettings();
    m_paintRecord = PaintRecord::read();
    m_record = MachineRecord::read();
    m_profile = PowerProfiles::read();
    m_actions = PowerProfiles::gpuActions();
    m_appChanges.clear();
    m_actionChanges.clear();
    m_errorText.clear();

    AppEntries entries = AppEntries::fromEnvironment();
    entries.refreshCopies();
    m_apps = entries.list();
    std::sort(m_apps.begin(), m_apps.end(), [this](const AppEntry &a, const AppEntry &b) {
        const bool aSet = a.preference != AppPreference::Unset || a.fromUserCopy || !m_paint.programChoice(a.id).isEmpty();
        const bool bSet = b.preference != AppPreference::Unset || b.fromUserCopy || !m_paint.programChoice(b.id).isEmpty();
        if (aSet != bSet) {
            return aSet;
        }
        return a.name.compare(b.name, Qt::CaseInsensitive) < 0;
    });

    // The session the page runs in: the first device of KWIN_DRM_DEVICES, else what Automatic picks
    const Resolver r = resolver();
    m_runningMain = r.automaticMainIndex();
    const QString first = qEnvironmentVariable("KWIN_DRM_DEVICES").section(u':', 0, 0);
    for (int i = 0; i < m_gpus.size() && !first.isEmpty(); ++i) {
        if (m_gpus.at(i).cardNode == first) {
            m_runningMain = i;
        }
    }
    m_handSet = false;
    const QDir envDir(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + u"/plasma-workspace/env"_s);
    static const QRegularExpression pattern(QStringLiteral(R"(^\s*(export\s+)?KWIN_DRM_DEVICES=)"), QRegularExpression::MultilineOption);
    for (const QString &name : envDir.entryList({u"*.sh"_s}, QDir::Files)) {
        QFile file(envDir.filePath(name));
        if (file.open(QIODevice::ReadOnly) && pattern.match(QString::fromUtf8(file.readAll())).hasMatch()) {
            m_handSet = true;
        }
    }
    syncKept();
    updateState();
    setNeedsSave(false);
    setRepresentsDefaults(m_settings.isDefault() && m_paint.isDefault() && !m_vramProtection);
}

QList<Problem> GraphicsKcm::liveProblems(const GraphicsSettings &settings) const
{
    const Resolver r(m_gpus, settings.mainGpu(), m_profile, m_record.bestGpu);
    QList<Problem> list;
    const Problem main = Problems::fromResolution(u"main-gpu"_s, r.mainProblem(), m_gpus, m_root);
    if (!main.isEmpty()) {
        list << main;
    }
    for (Category category : allCategories()) {
        const QString key = categoryKey(category).toLower();
        const Problem problem = Problems::fromResolution(key, r.resolveCategory(category, settings), m_gpus, m_root, m_profile);
        if (!problem.isEmpty()) {
            list << problem;
        }
    }
    return list;
}

void GraphicsKcm::syncKept()
{
    // the page sees the same problems the launchers keep, so a choice made here clears its record at once
    const QList<Problem> live = liveProblems(GraphicsSettings());
    QStringList keys = {u"main-gpu"_s};
    for (Category category : allCategories()) {
        keys << categoryKey(category).toLower();
    }
    for (const QString &key : std::as_const(keys)) {
        bool found = false;
        for (const Problem &problem : live) {
            if (problem.key == key) {
                Problems::keep(problem, Problems::userDir());
                found = true;
            }
        }
        if (!found) {
            Problems::clear(key, Problems::userDir());
        }
    }
}

QVariantList GraphicsKcm::problems() const
{
    QVariantList list;
    const auto add = [this, &list](const Problem &problem) {
        QVariantList gpus;
        if (problem.isChoice()) {
            for (const Alternative &gpu : problem.alternatives) {
                if (gpu.id != problem.requested) {
                    gpus.append(QVariantMap{{u"id"_s, gpu.id}, {u"text"_s, i18nc("@action:button %1 is a GPU name", "Use %1", gpuLabel(indexOf(gpu.id)))}});
                }
            }
        }
        list.append(QVariantMap{{u"key"_s, problem.key}, {u"text"_s, Problems::message(problem)}, {u"system"_s, problem.system}, {u"gpus"_s, gpus}});
    };
    // the machine's failed steps, then the person's choices as they are now, pending changes included
    for (const Problem &problem : Problems::read(Problems::systemDir(m_root), true)) {
        add(problem);
    }
    for (const Problem &problem : liveProblems(m_settings)) {
        add(problem);
    }
    // the engine's records the page lists as they are kept: the video memory step, and (ORDER 467) a program that stopped
    // right after it started on its GPU, with the engine's own labels and commands
    QJsonArray kept = Problems::records({u"sparky-stereo-vram-boost"_s});
    for (const QJsonValue &value : Problems::records({u"sparky-stereo-graphics"_s})) {
        const QString key = value.toObject().value(u"key"_s).toString();
        // (ORDER 518) and painting on the graphics card that cannot be used for a program
        if (key.startsWith(u"died-"_s) || key.startsWith(u"paint-"_s)) {
            kept.append(value);
        }
    }
    for (const QJsonValue &value : std::as_const(kept)) {
        const QJsonObject record = value.toObject();
        QVariantList actions;
        const auto commands = record.value(u"actions"_s).toArray();
        const auto labels = record.value(u"labels"_s).toArray();
        for (qsizetype i = 0; i < commands.size(); ++i) {
            actions.append(QVariantMap{{u"id"_s, commands.at(i).toObject().value(u"id"_s).toString()},
                                       {u"text"_s, labels.at(i).toString()}});
        }
        list.append(QVariantMap{{u"package"_s, record.value(u"package"_s).toString()},
                                {u"key"_s, record.value(u"key"_s).toString()},
                                {u"text"_s, record.value(u"text"_s).toString()},
                                {u"gpus"_s, QVariantList()}, {u"actions"_s, actions}});
    }
    return list;
}

void GraphicsKcm::runProblemAction(const QString &package, const QString &key, const QString &id)
{
    if (package != u"sparky-stereo-vram-boost"_s
        && !(package == u"sparky-stereo-graphics"_s && (key.startsWith(u"died-"_s) || key.startsWith(u"paint-"_s)))) {
        return;
    }
    for (const QJsonValue &value : Problems::records({package})) {
        const auto record = value.toObject();
        if (record.value(u"key"_s).toString() != key) {
            continue;
        }
        for (const QJsonValue &value : record.value(u"actions"_s).toArray()) {
            const auto action = value.toObject();
            if (action.value(u"id"_s).toString() != id) {
                continue;
            }
            QStringList command;
            for (const auto &arg : action.value(u"command"_s).toArray()) {
                command.append(arg.toString());
            }
            if (!command.isEmpty() && !QProcess::startDetached(command.first(), command.mid(1))) {
                m_errorText = i18nc("@info", "The problem action could not be started.");
                Q_EMIT changed();
            }
        }
    }
}

bool GraphicsKcm::vramProtection() const
{
    return m_vramProtection;
}

void GraphicsKcm::setVramProtection(bool enabled)
{
    if (m_vramProtection != enabled) {
        m_vramProtection = enabled;
        updateState();
        setNeedsSave(true);
    }
}

void GraphicsKcm::useGpu(const QString &key, const QString &id)
{
    if (key == u"main-gpu"_s) {
        setMainChoice(id);
    } else {
        for (Category category : allCategories()) {
            if (categoryKey(category).toLower() == key) {
                setCategoryChoice(categoryKey(category), id);
            }
        }
    }
}

void GraphicsKcm::save()
{
    if (m_savingVram) {
        return;
    }
    m_errorText.clear();
    // what the person's file says about painting before this Apply
    const PaintSettings paintBefore;
    bool paintChanged = paintBefore.programChoices() != m_paint.programChoices();
    for (Category category : allCategories()) {
        paintChanged = paintChanged || paintBefore.kindChoice(category) != m_paint.kindChoice(category);
    }
    if (!m_settings.save() || !m_paint.save()) {
        m_errorText = i18nc("@info", "The graphics settings could not be saved.");
    } else if (paintChanged) {
        // a way of painting the person changed ends what was kept about the old one (ORDER 518): the next start says
        // again what still cannot be had. An Apply that changes nothing about painting keeps what is kept
        for (const QJsonValue &value : Problems::records({u"sparky-stereo-graphics"_s})) {
            const QString key = value.toObject().value(u"key"_s).toString();
            if (key.startsWith(u"paint-"_s) && value.toObject().value(u"scope"_s).toString() == u"person"_s) {
                Problems::clear(key, Problems::userDir());
            }
        }
    }
    AppEntries entries = AppEntries::fromEnvironment();
    for (auto it = m_appChanges.cbegin(); it != m_appChanges.cend(); ++it) {
        if (!entries.setPreference(it.key(), AppPreference(it.value()))) {
            m_errorText = i18nc("@info %1 is a program's menu entry", "The setting for %1 could not be saved.", it.key());
        }
    }
    for (auto it = m_actionChanges.cbegin(); it != m_actionChanges.cend(); ++it) {
        if (!PowerProfiles::setActionEnabled(it.key(), it.value())) {
            m_errorText = i18nc("@info", "The power setting could not be changed. The power profile service may not allow it.");
        }
    }
    if (m_vramProtection != m_savedVramProtection) {
        KAuth::Action action(u"org.sparkylinux.sparkystereo.graphics.savevram"_s);
        action.setHelperId(u"org.sparkylinux.sparkystereo.graphics"_s);
        action.setArguments({{u"enabled"_s, m_vramProtection}});
        auto *job = action.execute();
        m_savingVram = true;
        connect(job, &KJob::result, this, [this, job] {
            m_savingVram = false;
            const bool success = job->error() == KJob::NoError;
            if (success) {
                load();
            } else {
                m_errorText = i18nc("@info", "The graphics settings could not be saved.") + u" "_s + job->errorString();
                setNeedsSave(true);
            }
            Q_EMIT changed();
            Q_EMIT saveFinished(success);
        });
        job->start();
        return;
    }
    const QString error = m_errorText;
    load();
    m_errorText = error;
    Q_EMIT changed();
}

void GraphicsKcm::defaults()
{
    m_vramProtection = false;
    m_settings.resetToDefaults();
    m_paint.resetToDefaults();
    updateState();
    setNeedsSave(true);
}

void GraphicsKcm::updateState()
{
    Q_EMIT changed();
    Q_EMIT appsChanged();
    setRepresentsDefaults(m_settings.isDefault() && m_paint.isDefault() && !m_vramProtection);
}

QVariantList GraphicsKcm::gpus() const
{
    const Resolver r = resolver();
    const int main = r.mainIndex();
    QVariantList list;
    for (int i = 0; i < m_gpus.size(); ++i) {
        const Gpu &gpu = m_gpus.at(i);
        QStringList screens;
        for (const Connector &connector : gpu.connectors) {
            if (connector.connected) {
                screens << (connector.monitor.isEmpty() ? connector.name : u"%1 (%2)"_s.arg(connector.name, connector.monitor));
            }
        }
        QStringList used;
        if (multiGpu()) {
            for (Category category : allCategories()) {
                if (r.resolveCategory(category, m_settings).gpuIndex == i) {
                    used << categoryLabel(category);
                }
            }
        }
        QString kind = gpu.kind == GpuKind::Integrated ? i18nc("@label kind of GPU", "Integrated") : i18nc("@label kind of GPU", "Discrete");
        if (!gpu.canRender) {
            kind = i18nc("@label kind of GPU", "Display adapter only");
        }
        list.append(QVariantMap{
            {u"id"_s, gpu.id},
            {u"name"_s, gpuLabel(i)},
            {u"kindText"_s, kind},
            {u"driverText"_s, gpu.driver.isEmpty() ? i18nc("@info", "No driver loaded") : i18nc("@info %1 is a kernel driver name", "Driver: %1", gpu.driver)},
            {u"screensText"_s, screens.isEmpty() ? i18nc("@info", "No screen attached") : i18nc("@info %1 is a list of screens", "Screens: %1", screens.join(u", "_s))},
            {u"drawsDesktop"_s, i == main},
            {u"runningDesktop"_s, i == m_runningMain},
            {u"canRender"_s, gpu.canRender},
            {u"accessible"_s, gpu.accessible},
            {u"usedText"_s, used.isEmpty() ? QString() : i18nc("@info %1 is a list of kinds of program", "Used now for: %1", used.join(u", "_s))},
        });
    }
    return list;
}

int GraphicsKcm::gpuCount() const
{
    return m_gpus.size();
}

bool GraphicsKcm::multiGpu() const
{
    int renderers = 0;
    for (const Gpu &gpu : m_gpus) {
        renderers += gpu.usable() ? 1 : 0;
    }
    return renderers > 1;
}

QString GraphicsKcm::mainChoice() const
{
    return m_settings.mainGpu();
}

void GraphicsKcm::setMainChoice(const QString &choice)
{
    if (choice == m_settings.mainGpu()) {
        return;
    }
    m_settings.setMainGpu(choice);
    updateState();
    setNeedsSave(true);
}

QVariantList GraphicsKcm::mainOptions() const
{
    const Resolver r = resolver();
    QVariantList options;
    options.append(QVariantMap{{u"value"_s, QString()}, {u"text"_s, i18nc("@item:inlistbox %1 is a GPU name", "Automatic (%1)", gpuLabel(r.automaticMainIndex()))}});
    for (int i = 0; i < m_gpus.size(); ++i) {
        if (m_gpus.at(i).canRender) {
            options.append(QVariantMap{{u"value"_s, m_gpus.at(i).id}, {u"text"_s, gpuLabel(i)}});
        }
    }
    if (!m_settings.mainGpu().isEmpty() && r.indexOfId(m_settings.mainGpu()) < 0) {
        options.append(QVariantMap{{u"value"_s, m_settings.mainGpu()}, {u"text"_s, i18nc("@item:inlistbox %1 is a PCI address", "Missing GPU (%1)", m_settings.mainGpu())}});
    }
    return options;
}

QString GraphicsKcm::mainNowText() const
{
    return gpuLabel(m_runningMain);
}

bool GraphicsKcm::mainAppliesLater() const
{
    const Resolver r = resolver();
    return r.mainIndex() != m_runningMain;
}

bool GraphicsKcm::mainSetByHand() const
{
    return m_handSet;
}

QVariantList GraphicsKcm::choiceOptions(const QString &current) const
{
    QVariantList options;
    options.append(QVariantMap{{u"value"_s, u"auto"_s}, {u"text"_s, i18nc("@item:inlistbox", "Automatic")}});
    options.append(QVariantMap{{u"value"_s, u"profile"_s}, {u"text"_s, i18nc("@item:inlistbox", "Follow the power profile")}});
    bool integrated = false;
    bool discrete = false;
    int renderers = 0;
    for (const Gpu &gpu : m_gpus) {
        if (gpu.usable()) {
            ++renderers;
            (gpu.kind == GpuKind::Integrated ? integrated : discrete) = true;
        }
    }
    if (integrated) {
        options.append(QVariantMap{{u"value"_s, u"integrated"_s}, {u"text"_s, i18nc("@item:inlistbox", "Integrated GPU")}});
    }
    if (discrete) {
        options.append(QVariantMap{{u"value"_s, u"discrete"_s}, {u"text"_s, i18nc("@item:inlistbox", "Discrete GPU")}});
    }
    if (renderers > 2) {
        for (int i = 0; i < m_gpus.size(); ++i) {
            if (m_gpus.at(i).usable()) {
                options.append(QVariantMap{{u"value"_s, m_gpus.at(i).id}, {u"text"_s, gpuLabel(i)}});
            }
        }
    }
    const bool listed = std::any_of(options.cbegin(), options.cend(), [&current](const QVariant &option) {
        return option.toMap().value(u"value"_s).toString() == current;
    });
    if (!listed && !current.isEmpty()) {
        options.append(QVariantMap{{u"value"_s, current}, {u"text"_s, i18nc("@item:inlistbox %1 is a PCI address", "Missing GPU (%1)", current)}});
    }
    return options;
}

QVariantList GraphicsKcm::categories() const
{
    const Resolver r = resolver();
    QVariantList list;
    for (Category category : allCategories()) {
        const Resolution resolution = r.resolveCategory(category, m_settings);
        const QString choice = m_settings.renderChoice(category);
        // a program of this kind started in 3D goes elsewhere on Automatic: say where
        const Resolution stereo = r.resolveCategory(category, m_settings, true);
        const QString stereoText = stereo.gpuIndex >= 0 && stereo.gpuIndex != resolution.gpuIndex
            ? i18nc("@info %1 is a GPU name, %2 the reason", "Started in 3D: %1, %2", gpuLabel(stereo.gpuIndex), reasonText(stereo))
            : QString();
        const QString nowText = !resolution.problem.isEmpty()
            ? Problems::message(Problems::fromResolution(categoryKey(category).toLower(), resolution, m_gpus, m_root, m_profile))
            : (resolution.gpuIndex < 0 ? QString() : i18nc("@info %1 is a GPU name, %2 the reason", "Now: %1, %2", gpuLabel(resolution.gpuIndex), reasonText(resolution)));
        list.append(QVariantMap{
            {u"problem"_s, !resolution.problem.isEmpty()},
            {u"stereoText"_s, stereoText},
            {u"key"_s, categoryKey(category)},
            {u"label"_s, categoryLabel(category)},
            {u"choice"_s, choice},
            {u"options"_s, choiceOptions(choice)},
            {u"nowText"_s, nowText},
        });
    }
    return list;
}

void GraphicsKcm::setCategoryChoice(const QString &key, const QString &choice)
{
    for (Category category : allCategories()) {
        if (categoryKey(category) == key && m_settings.renderChoice(category) != choice) {
            m_settings.setRenderChoice(category, choice);
            updateState();
            setNeedsSave(true);
        }
    }
}

QString GraphicsKcm::profile() const
{
    return m_profile.profile ? powerProfileToString(*m_profile.profile) : QString();
}

QString GraphicsKcm::profileText() const
{
    if (!m_profile.profile) {
        // never Balanced in its place: the kinds that follow the profile say they cannot be placed
        return i18nc("@info %1 says why", "The power profile could not be read: %1.", Problems::profileError(m_profile.error, m_profile.detail));
    }
    switch (*m_profile.profile) {
    case PowerProfile::PowerSaver:
        return i18nc("@info", "Power profile: Power Saver. Automatic draws browsers on the integrated GPU. Other programs stay on the GPU that draws the desktop.");
    case PowerProfile::Performance:
        return i18nc("@info", "Power profile: Performance. Automatic draws browsers on the discrete GPU. Other programs stay on the GPU that draws the desktop.");
    case PowerProfile::Balanced:
        break;
    }
    return i18nc("@info", "Power profile: Balanced. Automatic draws browsers on the GPU that draws the desktop. Other programs stay there too.");
}

QString GraphicsKcm::measuredText() const
{
    if (!multiGpu()) {
        return {};
    }
    const Resolver r = resolver();
    const QString gpu = gpuLabel(r.presentingIndex());
    if (r.measuredIndex() < 0 && !m_record.bestGpu.isEmpty()) {
        // the record names a GPU that is not here: said, never taken for "not measured"
        return i18nc("@info %1 is a GPU name, %2 a PCI address or vendor and device ids",
                     "Automatic draws players, games and any program started in 3D on %1 whatever the power profile, on battery too. The GPU this computer "
                     "was measured best on, %2, is not here now, so that is its discrete GPU.",
                     gpu,
                     m_record.bestGpu.startsWith(u"pci-"_s) ? m_record.bestGpu.mid(4) : m_record.bestGpu);
    }
    if (r.measuredIndex() < 0) {
        return i18nc("@info %1 is a GPU name",
                     "Automatic draws players, games and any program started in 3D on %1 whatever the power profile, on battery too. This computer has "
                     "not been measured yet, so that is its discrete GPU.",
                     gpu);
    }
    if (m_record.origin == u"shipped"_s && !m_record.model.isEmpty()) {
        return i18nc("@info %1 is a GPU name, %2 a computer model",
                     "Automatic draws players, games and any program started in 3D on %1 whatever the power profile, on battery too: it was "
                     "measured best for them on the %2.",
                     gpu,
                     m_record.model);
    }
    return i18nc("@info %1 is a GPU name",
                 "Automatic draws players, games and any program started in 3D on %1 whatever the power profile, on battery too: it was measured "
                 "best for them on this computer.",
                 gpu);
}

bool GraphicsKcm::copyBack() const
{
    return m_settings.copyBack().value_or(m_record.copyBack.value_or(false));
}

void GraphicsKcm::setCopyBack(bool copyBack)
{
    // the machine's own setting is not written for the person, so a better record later reaches them too
    const std::optional<bool> value = copyBack == m_record.copyBack.value_or(false) ? std::nullopt : std::optional<bool>(copyBack);
    if (value == m_settings.copyBack()) {
        return;
    }
    m_settings.setCopyBack(value);
    updateState();
    setNeedsSave(true);
}

QString GraphicsKcm::copyBackMachineText() const
{
    if (!m_record.copyBack.has_value()) {
        return i18nc("@info", "This computer has not been measured for it, so it is Off unless you turn it on.");
    }
    return *m_record.copyBack ? i18nc("@info", "This computer's measured setting: On.") : i18nc("@info", "This computer's measured setting: Off.");
}

bool GraphicsKcm::copyBackSetInSession() const
{
    return qEnvironmentVariableIsSet("MEDIA_GPU_ROUTE_COPY_BACK");
}

bool GraphicsKcm::otherGpu() const
{
    return m_settings.otherGpu().value_or(true);
}

void GraphicsKcm::setOtherGpu(bool otherGpu)
{
    // on is the default and is not written, so the key is there only when the person turned it off
    const std::optional<bool> value = otherGpu ? std::nullopt : std::optional<bool>(false);
    if (value == m_settings.otherGpu()) {
        return;
    }
    m_settings.setOtherGpu(value);
    updateState();
    setNeedsSave(true);
}

bool GraphicsKcm::otherGpuSetInSession() const
{
    return qEnvironmentVariableIsSet("MEDIA_GPU_ROUTE_OTHER_GPU");
}

QString GraphicsKcm::appFilter() const
{
    return m_appFilter;
}

void GraphicsKcm::setAppFilter(const QString &filter)
{
    if (filter != m_appFilter) {
        m_appFilter = filter;
        Q_EMIT appsChanged();
    }
}

AppPreference GraphicsKcm::pendingPreference(const AppEntry &entry) const
{
    const auto it = m_appChanges.constFind(entry.id);
    return it == m_appChanges.cend() ? entry.preference : AppPreference(it.value());
}

QVariantList GraphicsKcm::apps() const
{
    const Resolver r = resolver();
    const PaintFacts facts = paintFacts();
    QVariantList list;
    for (const AppEntry &entry : m_apps) {
        if (!m_appFilter.isEmpty() && !entry.name.contains(m_appFilter, Qt::CaseInsensitive) && !entry.id.contains(m_appFilter, Qt::CaseInsensitive)) {
            continue;
        }
        if (list.size() >= s_maxApps) {
            break;
        }
        AppEntry shown = entry;
        shown.preference = pendingPreference(entry);
        const Resolution resolution = r.resolveApp(shown, m_settings);
        const PaintResolution painted = Paint::resolve(entry.category, entry.id, m_paint, m_paintRecord, facts);
        list.append(QVariantMap{
            {u"paint"_s, m_paint.programChoice(entry.id)},
            {u"paintText"_s, wayLabel(painted.way)},
            {u"id"_s, entry.id},
            {u"name"_s, entry.name},
            {u"icon"_s, entry.icon},
            {u"preference"_s, int(shown.preference)},
            {u"nowText"_s,
             !resolution.problem.isEmpty() ? i18nc("@info in place of a GPU name", "its group's GPU cannot be used")
                                           : (resolution.gpuIndex < 0 ? QString() : gpuLabel(resolution.gpuIndex))},
            {u"systemPrefersOther"_s, entry.systemPrefersOther},
        });
    }
    return list;
}

int GraphicsKcm::hiddenApps() const
{
    int matching = 0;
    for (const AppEntry &entry : m_apps) {
        if (m_appFilter.isEmpty() || entry.name.contains(m_appFilter, Qt::CaseInsensitive) || entry.id.contains(m_appFilter, Qt::CaseInsensitive)) {
            ++matching;
        }
    }
    return qMax(0, matching - s_maxApps);
}

QVariantList GraphicsKcm::appOptions() const
{
    return {
        QVariantMap{{u"value"_s, int(AppPreference::Unset)}, {u"text"_s, i18nc("@item:inlistbox", "Same as its group")}},
        QVariantMap{{u"value"_s, int(AppPreference::OtherGpu)}, {u"text"_s, i18nc("@item:inlistbox", "The dedicated GPU")}},
        QVariantMap{{u"value"_s, int(AppPreference::MainGpu)}, {u"text"_s, i18nc("@item:inlistbox", "The main GPU")}},
    };
}

void GraphicsKcm::setAppPreference(const QString &id, int preference)
{
    for (const AppEntry &entry : std::as_const(m_apps)) {
        if (entry.id != id) {
            continue;
        }
        if (preference == int(entry.preference)) {
            m_appChanges.remove(id);
        } else {
            m_appChanges.insert(id, preference);
        }
        Q_EMIT appsChanged();
        setNeedsSave(true);
        return;
    }
}

// Paint windows (ORDER 518). The three ways stay the person's choice (Daniel, 2026-11-12: "keep as a option"); Automatic is
// the way measured for that kind of program on this machine (Daniel, 2026-10-23: "our measured defaults out of the box,
// every choice the user's"), and the processor where nothing was measured, which is how every Qt paints
QString GraphicsKcm::wayLabel(PaintWay way) const
{
    switch (way) {
    case PaintWay::Batched:
        return i18nc("@item:inlistbox way of painting windows", "On the graphics card (batched)");
    case PaintWay::OpenGL:
        return i18nc("@item:inlistbox way of painting windows", "On the graphics card, Qt's OpenGL engine");
    case PaintWay::Processor:
        break;
    }
    return i18nc("@item:inlistbox way of painting windows", "On the processor");
}

PaintFacts GraphicsKcm::paintFacts() const
{
    PaintFacts facts = PaintFacts::read(canPaintOnGpu());
    return facts;
}

bool GraphicsKcm::canPaintOnGpu() const
{
    return !resolver().usableIndices().isEmpty();
}

bool GraphicsKcm::paintSetInSession() const
{
    return !qEnvironmentVariableIsEmpty("QT_WIDGETS_GPU_PAINT");
}

QString GraphicsKcm::paintNowText(const PaintResolution &resolution) const
{
    if (resolution.problem == u"no-gpu"_s) {
        return i18nc("@info", "Now: on the processor, because this computer has no graphics processor that can draw now.");
    }
    QString reason;
    if (resolution.reason == u"measured"_s) {
        reason = m_paintRecord.origin == u"shipped"_s ? i18nc("@info", "measured best for this model") : i18nc("@info", "measured best on this computer");
    } else if (resolution.reason == u"unmeasured"_s) {
        reason = i18nc("@info", "not measured on this computer yet");
    } else {
        reason = i18nc("@info", "your choice");
    }
    return i18nc("@info %1 is a way of painting windows, %2 the reason", "Now: %1, %2", wayLabel(resolution.way), reason);
}

QVariantList GraphicsKcm::paintOptions() const
{
    return {
        QVariantMap{{u"value"_s, u"auto"_s}, {u"text"_s, i18nc("@item:inlistbox", "Automatic")}},
        QVariantMap{{u"value"_s, u"cpu"_s}, {u"text"_s, wayLabel(PaintWay::Processor)}},
        QVariantMap{{u"value"_s, u"batch"_s}, {u"text"_s, wayLabel(PaintWay::Batched)}},
        QVariantMap{{u"value"_s, u"opengl"_s}, {u"text"_s, wayLabel(PaintWay::OpenGL)}},
    };
}

QVariantList GraphicsKcm::paintProgramOptions() const
{
    return {
        QVariantMap{{u"value"_s, QString()}, {u"text"_s, i18nc("@item:inlistbox", "Same as its group")}},
        QVariantMap{{u"value"_s, u"cpu"_s}, {u"text"_s, wayLabel(PaintWay::Processor)}},
        QVariantMap{{u"value"_s, u"batch"_s}, {u"text"_s, wayLabel(PaintWay::Batched)}},
        QVariantMap{{u"value"_s, u"opengl"_s}, {u"text"_s, wayLabel(PaintWay::OpenGL)}},
    };
}

QVariantList GraphicsKcm::paintKinds() const
{
    QVariantList list;
    const PaintFacts facts = paintFacts();
    for (Category category : allCategories()) {
        const PaintResolution resolution = Paint::resolve(category, QString(), m_paint, m_paintRecord, facts);
        list.append(QVariantMap{
            {u"key"_s, categoryKey(category)},
            {u"label"_s, categoryLabel(category)},
            {u"choice"_s, m_paint.kindChoice(category)},
            {u"nowText"_s, paintNowText(resolution)},
            {u"way"_s, paintWayKey(resolution.way)},
        });
    }
    return list;
}

void GraphicsKcm::setPaintKind(const QString &key, const QString &choice)
{
    for (Category category : allCategories()) {
        if (categoryKey(category) == key && m_paint.kindChoice(category) != choice && PaintSettings::validKindChoice(choice)) {
            m_paint.setKindChoice(category, choice);
            updateState();
            setNeedsSave(true);
        }
    }
}

void GraphicsKcm::setPaintProgram(const QString &id, const QString &choice)
{
    if (m_paint.programChoice(id) != choice && PaintSettings::validProgramChoice(choice)) {
        m_paint.setProgramChoice(id, choice);
        updateState();
        setNeedsSave(true);
    }
}

QVariantList GraphicsKcm::powerActions() const
{
    QVariantList list;
    for (const PowerAction &action : m_actions) {
        const auto it = m_actionChanges.constFind(action.name);
        list.append(QVariantMap{{u"name"_s, action.name}, {u"description"_s, action.description}, {u"enabled"_s, it == m_actionChanges.cend() ? action.enabled : it.value()}});
    }
    return list;
}

void GraphicsKcm::setPowerAction(const QString &name, bool enabled)
{
    for (const PowerAction &action : std::as_const(m_actions)) {
        if (action.name == name) {
            if (action.enabled == enabled) {
                m_actionChanges.remove(name);
            } else {
                m_actionChanges.insert(name, enabled);
            }
            Q_EMIT changed();
            setNeedsSave(true);
            return;
        }
    }
}

QString GraphicsKcm::errorText() const
{
    return m_errorText;
}

#include "graphicskcm.moc"
