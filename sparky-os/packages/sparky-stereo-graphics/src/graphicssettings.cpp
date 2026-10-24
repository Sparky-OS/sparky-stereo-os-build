// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "graphicssettings.h"

#include <KConfig>
#include <KConfigGroup>

#include <QRegularExpression>

using namespace Qt::StringLiterals;

namespace SparkyGraphics
{

static const QStringList s_keys = {u"Players"_s, u"Games"_s, u"Browsers"_s, u"Other"_s};

QString categoryKey(Category category)
{
    return s_keys.at(int(category));
}

QList<Category> allCategories()
{
    return {Category::Players, Category::Games, Category::Browsers, Category::Other};
}

QString GraphicsSettings::configName()
{
    return u"sparky-stereo-graphicsrc"_s;
}

static bool validGpuId(const QString &id)
{
    static const QRegularExpression pattern(QStringLiteral(R"(^pci-[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]$)"));
    return pattern.match(id).hasMatch();
}

bool GraphicsSettings::validChoice(const QString &choice)
{
    return choice == u"auto"_s || choice == u"profile"_s || choice == u"integrated"_s || choice == u"discrete"_s || validGpuId(choice);
}

std::optional<bool> GraphicsSettings::parseBool(const QString &text)
{
    // the forms libmedia-gpu-route reads, so the page and the players agree on every hand-written value
    const QString value = text.trimmed().toLower();
    if (value == u"true"_s || value == u"on"_s || value == u"yes"_s || value == u"1"_s) {
        return true;
    }
    if (value == u"false"_s || value == u"off"_s || value == u"no"_s || value == u"0"_s) {
        return false;
    }
    return std::nullopt;
}

GraphicsSettings::GraphicsSettings()
    : m_choices(s_keys.size(), u"auto"_s)
{
    // Only the person's own file: a value that equals the default is not stored, so there is nothing to merge.
    KConfig config(configName(), KConfig::SimpleConfig);
    const QString main = config.group(u"General"_s).readEntry("MainGpu", QString());
    if (validGpuId(main)) {
        m_mainGpu = main;
    }
    const KConfigGroup render = config.group(u"Render"_s);
    for (int i = 0; i < s_keys.size(); ++i) {
        const QString choice = render.readEntry(s_keys.at(i), QString());
        if (validChoice(choice)) {
            m_choices[i] = choice;
        }
    }
    m_copyBack = parseBool(config.group(u"Decoding"_s).readEntry("CopyBack", QString()));
}

std::optional<bool> GraphicsSettings::copyBack() const
{
    return m_copyBack;
}

void GraphicsSettings::setCopyBack(std::optional<bool> value)
{
    m_copyBack = value;
}

QString GraphicsSettings::mainGpu() const
{
    return m_mainGpu;
}

void GraphicsSettings::setMainGpu(const QString &id)
{
    if (id.isEmpty() || validGpuId(id)) {
        m_mainGpu = id;
    }
}

QString GraphicsSettings::renderChoice(Category category) const
{
    return m_choices.at(int(category));
}

void GraphicsSettings::setRenderChoice(Category category, const QString &choice)
{
    if (validChoice(choice)) {
        m_choices[int(category)] = choice;
    }
}

bool GraphicsSettings::isDefault() const
{
    return m_mainGpu.isEmpty() && m_choices == QStringList(s_keys.size(), u"auto"_s) && !m_copyBack.has_value();
}

void GraphicsSettings::resetToDefaults()
{
    m_mainGpu.clear();
    m_choices = QStringList(s_keys.size(), u"auto"_s);
    m_copyBack.reset();
}

bool GraphicsSettings::save()
{
    KConfig config(configName(), KConfig::SimpleConfig);
    KConfigGroup general = config.group(u"General"_s);
    if (m_mainGpu.isEmpty()) {
        general.deleteEntry("MainGpu");
    } else {
        general.writeEntry("MainGpu", m_mainGpu);
    }
    KConfigGroup render = config.group(u"Render"_s);
    for (int i = 0; i < s_keys.size(); ++i) {
        if (m_choices.at(i) == u"auto"_s) {
            render.deleteEntry(s_keys.at(i));
        } else {
            render.writeEntry(s_keys.at(i), m_choices.at(i));
        }
    }
    KConfigGroup decoding = config.group(u"Decoding"_s);
    if (m_copyBack.has_value()) {
        decoding.writeEntry("CopyBack", *m_copyBack);
    } else {
        decoding.deleteEntry("CopyBack");
    }
    return config.sync();
}

}
