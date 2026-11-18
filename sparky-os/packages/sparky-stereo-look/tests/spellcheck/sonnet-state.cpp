// Created by Daniel Ramos (Capitain Jack) 2026/11/18
// Copyright 2026 under the GNU GPL3 License
#include <QApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QTextStream>
#include <Sonnet/ConfigView>
#include <Sonnet/Settings>
#include <Sonnet/Speller>

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    Sonnet::Settings settings;
    Sonnet::Speller speller;
    Sonnet::ConfigView page;
    page.setLanguage(settings.defaultLanguage());
    QJsonObject dictionaries;
    const auto available = speller.availableDictionaries();
    for (auto i = available.cbegin(); i != available.cend(); ++i) {
        dictionaries.insert(i.key(), i.value());
    }
    const QJsonObject state{
        {QStringLiteral("systemLocale"), QLocale::system().name()},
        {QStringLiteral("pageSelectedLanguage"), page.language()},
        {QStringLiteral("defaultLanguage"), settings.defaultLanguage()},
        {QStringLiteral("defaultClient"), settings.defaultClient()},
        {QStringLiteral("clients"), QJsonArray::fromStringList(settings.clients())},
        {QStringLiteral("availableLanguages"), QJsonArray::fromStringList(speller.availableLanguages())},
        {QStringLiteral("dictionaries"), dictionaries},
        {QStringLiteral("checkerEnabledByDefault"), settings.checkerEnabledByDefault()},
        {QStringLiteral("backgroundCheckerEnabled"), settings.backgroundCheckerEnabled()},
        {QStringLiteral("autodetectLanguage"), settings.autodetectLanguage()},
        {QStringLiteral("spellerLanguage"), speller.language()},
        {QStringLiteral("spellerValid"), speller.isValid()},
    };
    QTextStream(stdout) << QJsonDocument(state).toJson();
    return 0;
}
