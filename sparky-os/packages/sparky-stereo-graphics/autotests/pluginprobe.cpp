// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

// pluginprobe: loads the INSTALLED page the way System Settings does and prints what it shows, in the language
// of LANGUAGE (the installed catalog), to prove the package: its plugin, its QML and its translations.
#include <KLocalizedString>
#include <KPluginMetaData>
#include <KQuickConfigModule>
#include <KQuickConfigModuleLoader>

#include <QCoreApplication>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QQuickItem>
#include <QTextStream>

using namespace Qt::StringLiterals;

static void collectTexts(QQuickItem *item, QStringList &texts)
{
    const QVariant text = item->property("text");
    if (text.typeId() == QMetaType::QString && !text.toString().isEmpty() && texts.size() < 40) {
        texts << text.toString();
    }
    for (QQuickItem *child : item->childItems()) {
        collectTexts(child, texts);
    }
}

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    QTextStream out(stdout);
    // the languages of the person's session; without a locale installed in the container, say them directly
    if (qEnvironmentVariableIsSet("PROBE_LANGUAGES")) {
        KLocalizedString::setLanguages(qEnvironmentVariable("PROBE_LANGUAGES").split(u':'));
    }
    const KPluginMetaData metaData = KPluginMetaData::findPluginById(u"plasma/kcms/systemsettings"_s, u"kcm_sparkystereo_graphics"_s);
    if (!metaData.isValid()) {
        out << "no installed page found\n";
        return 1;
    }
    out << "plugin: " << metaData.fileName() << "\nname: " << metaData.name() << " category: " << metaData.value(u"X-KDE-System-Settings-Parent-Category"_s) << "\n";
    auto result = KQuickConfigModuleLoader::loadModule(metaData, nullptr);
    if (!result) {
        out << "could not load the page: " << result.errorString << "\n";
        return 1;
    }
    KQuickConfigModule *module = result.plugin;
    module->load();
    QQuickItem *ui = module->mainUi();
    out << "main UI: " << (ui ? "loaded" : "FAILED") << (module->errorString().isEmpty() ? QString() : u" "_s + module->errorString()) << "\n";
    for (int i = 0; i < 100; ++i) {
        QCoreApplication::processEvents();
    }
    QStringList texts;
    if (ui) {
        collectTexts(ui, texts);
    }
    out << "page texts (QML): " << texts.mid(0, 4).join(u" | "_s) << "\n";
    out << "gpuCount=" << module->property("gpuCount").toInt() << "\n";
    for (const QVariant &v : module->property("gpus").toList()) {
        const QVariantMap g = v.toMap();
        out << g.value(u"name"_s).toString() << " | " << g.value(u"kindText"_s).toString() << " | " << g.value(u"driverText"_s).toString() << " | " << g.value(u"screensText"_s).toString() << "\n";
    }
    out << module->property("profileText").toString() << "\n";
    for (const QVariant &v : module->property("categories").toList()) {
        out << v.toMap().value(u"label"_s).toString() << ": " << v.toMap().value(u"nowText"_s).toString() << "\n";
    }
    return ui ? 0 : 1;
}
