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
};

QString categoryKey(Category category);
QList<Category> allCategories();

// ~/.config/sparky-stereo-graphicsrc. A key that was never written, or that Defaults removed, is the edition's default.
class GraphicsSettings
{
public:
    GraphicsSettings();

    // "" is Automatic, otherwise a GPU id
    QString mainGpu() const;
    void setMainGpu(const QString &id);

    // "auto", "profile" (follow the power profile), "integrated", "discrete" or a GPU id
    QString renderChoice(Category category) const;
    void setRenderChoice(Category category, const QString &choice);

    // [Decoding] CopyBack, the key libmedia-gpu-route reads: empty when the person never chose,
    // so the machine's measured record (or software decoding) decides
    std::optional<bool> copyBack() const;
    void setCopyBack(std::optional<bool> value);

    bool isDefault() const;
    void resetToDefaults();

    // Writes the file; a value equal to the default is not written.
    bool save();

    static QString configName();
    static bool validChoice(const QString &choice);
    // true, on, yes, 1 / false, off, no, 0 in any case; anything else is no value
    static std::optional<bool> parseBool(const QString &text);

private:
    QString m_mainGpu;
    QStringList m_choices;
    std::optional<bool> m_copyBack;
};

}
