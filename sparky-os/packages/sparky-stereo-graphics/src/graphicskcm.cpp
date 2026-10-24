// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "graphicskcm.h"

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
    if (resolution.missing) {
        return i18nc("@info", "the chosen GPU is not installed, so the main GPU");
    }
    if (resolution.reason == u"only-gpu"_s) {
        return i18nc("@info", "the only GPU");
    }
    if (resolution.reason == u"profile:power-saver"_s) {
        return i18nc("@info", "power saver profile");
    }
    if (resolution.reason == u"profile:performance"_s) {
        return i18nc("@info", "performance profile");
    }
    if (resolution.reason == u"profile:balanced"_s) {
        return i18nc("@info", "balanced profile");
    }
    if (resolution.reason == u"app"_s) {
        return i18nc("@info", "the program's own setting");
    }
    if (resolution.reason == u"measured"_s) {
        return m_record.origin == u"shipped"_s ? i18nc("@info", "measured best for this model") : i18nc("@info", "measured best on this computer");
    }
    if (resolution.reason == u"unmeasured"_s) {
        return i18nc("@info", "not measured on this computer yet");
    }
    return i18nc("@info", "your choice");
}

void GraphicsKcm::load()
{
    m_gpus = GpuInventory::read(m_root);
    m_settings = GraphicsSettings();
    m_record = MachineRecord::read();
    m_profile = PowerProfiles::active();
    m_actions = PowerProfiles::gpuActions();
    m_appChanges.clear();
    m_actionChanges.clear();
    m_errorText.clear();

    AppEntries entries = AppEntries::fromEnvironment();
    entries.refreshCopies();
    m_apps = entries.list();
    std::sort(m_apps.begin(), m_apps.end(), [](const AppEntry &a, const AppEntry &b) {
        const bool aSet = a.preference != AppPreference::Unset || a.fromUserCopy;
        const bool bSet = b.preference != AppPreference::Unset || b.fromUserCopy;
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
    updateState();
    setNeedsSave(false);
    setRepresentsDefaults(m_settings.isDefault());
}

void GraphicsKcm::save()
{
    m_errorText.clear();
    if (!m_settings.save()) {
        m_errorText = i18nc("@info", "The graphics settings could not be saved.");
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
    const QString error = m_errorText;
    load();
    m_errorText = error;
    Q_EMIT changed();
}

void GraphicsKcm::defaults()
{
    m_settings.resetToDefaults();
    updateState();
    setNeedsSave(true);
}

void GraphicsKcm::updateState()
{
    Q_EMIT changed();
    Q_EMIT appsChanged();
    setRepresentsDefaults(m_settings.isDefault());
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
        list.append(QVariantMap{
            {u"stereoText"_s, stereoText},
            {u"key"_s, categoryKey(category)},
            {u"label"_s, categoryLabel(category)},
            {u"choice"_s, choice},
            {u"options"_s, choiceOptions(choice)},
            {u"nowText"_s,
             resolution.gpuIndex < 0 ? QString() : i18nc("@info %1 is a GPU name, %2 the reason", "Now: %1, %2", gpuLabel(resolution.gpuIndex), reasonText(resolution))},
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
    return powerProfileToString(m_profile);
}

QString GraphicsKcm::profileText() const
{
    switch (m_profile) {
    case PowerProfile::PowerSaver:
        return i18nc("@info", "Power profile: Power Saver. Automatic draws games, browsers and other programs on the integrated GPU.");
    case PowerProfile::Performance:
        return i18nc("@info", "Power profile: Performance. Automatic draws games, browsers and other programs on the discrete GPU.");
    case PowerProfile::Balanced:
        break;
    }
    return i18nc("@info", "Power profile: Balanced. Automatic draws games, browsers and other programs on the GPU that draws the desktop.");
}

QString GraphicsKcm::measuredText() const
{
    if (!multiGpu()) {
        return {};
    }
    const Resolver r = resolver();
    const QString gpu = gpuLabel(r.presentingIndex());
    if (r.measuredIndex() < 0) {
        return i18nc("@info %1 is a GPU name",
                     "Automatic draws players, and any program started in 3D, on %1 whatever the power profile, on battery too. This computer has not "
                     "been measured yet, so that is its discrete GPU.",
                     gpu);
    }
    if (m_record.origin == u"shipped"_s && !m_record.model.isEmpty()) {
        return i18nc("@info %1 is a GPU name, %2 a computer model",
                     "Automatic draws players, and any program started in 3D, on %1 whatever the power profile, on battery too: it was measured "
                     "best for them on the %2.",
                     gpu,
                     m_record.model);
    }
    return i18nc("@info %1 is a GPU name",
                 "Automatic draws players, and any program started in 3D, on %1 whatever the power profile, on battery too: it was measured best "
                 "for them on this computer.",
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
        list.append(QVariantMap{
            {u"id"_s, entry.id},
            {u"name"_s, entry.name},
            {u"icon"_s, entry.icon},
            {u"preference"_s, int(shown.preference)},
            {u"nowText"_s, resolution.gpuIndex < 0 ? QString() : gpuLabel(resolution.gpuIndex)},
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
