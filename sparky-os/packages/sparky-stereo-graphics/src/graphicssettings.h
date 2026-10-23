// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QString>
#include <QStringList>

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

    // "auto", "integrated", "discrete" or a GPU id
    QString renderChoice(Category category) const;
    void setRenderChoice(Category category, const QString &choice);

    bool isDefault() const;
    void resetToDefaults();

    // Writes the file; a value equal to the default is not written.
    bool save();

    static QString configName();
    static bool validChoice(const QString &choice);

private:
    QString m_mainGpu;
    QStringList m_choices;
};

}
