// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QString>
#include <QStringList>

#include <optional>

namespace SparkyGraphics
{

enum class Category {
    Players,
    Games,
    Browsers,
    Other,
    // ORDER 70: the card the edition's partners (local AI engines) compute on; not a kind of program that draws, so it is
    // not in allCategories()
    Partners,
};

QString categoryKey(Category category);
// The kinds of programs that draw (players, games, browsers, other): menu entries, painting
QList<Category> allCategories();
// Every [Render] choice of the page: the kinds of programs and the partners' card
QList<Category> renderCategories();

// ~/.config/sparky-stereo-graphicsrc. A key that was never written, or that Defaults removed, is the edition's default.
class GraphicsSettings
{
public:
    GraphicsSettings();

    // "" is Automatic, otherwise a GPU id
    QString mainGpu() const;
    void setMainGpu(const QString &id);

    // "auto", "profile" (follow the power profile), "integrated", "discrete" or a GPU id; for Partners also "cpu" (the
    // processor only)
    QString renderChoice(Category category) const;
    void setRenderChoice(Category category, const QString &choice);

    // [Decoding] CopyBack, the key libmedia-gpu-route reads: empty when the person never chose,
    // so the machine's measured record (or software decoding) decides
    std::optional<bool> copyBack() const;
    void setCopyBack(std::optional<bool> value);

    // [Decoding] OtherGpu, which libmedia-gpu-route reads: whether a player that copies its pictures back may decode on
    // another GPU when the GPU players use cannot decode a video; empty when the person never chose (then not)
    std::optional<bool> otherGpu() const;
    void setOtherGpu(std::optional<bool> value);

    bool isDefault() const;
    void resetToDefaults();

    // Writes the file; a value equal to the default is not written.
    bool save();

    static QString configName();
    static bool validChoice(const QString &choice);
    // The same, for one kind: the partners' card may also be "cpu"
    static bool validChoice(const QString &choice, Category category);
    // true, on, yes, 1 / false, off, no, 0 in any case; anything else is no value
    static std::optional<bool> parseBool(const QString &text);

private:
    QString m_mainGpu;
    QStringList m_choices;
    std::optional<bool> m_copyBack;
    std::optional<bool> m_otherGpu;
};

}
