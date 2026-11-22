// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QList>
#include <QString>

// Every entry comes from the shared input list, including temporal inputs.
// An input without a preview mapping stays in the list and uses the visible preview refusal.
namespace Sparky::Camera
{
struct Packing {
    QString id; // the layer's id; "mono" is a camera with one lens
    QString text; // the layer's words, translated
    QString videoOutput; // the name of QtMultimedia VideoOutput.StereoInput that shows it; empty when the preview cannot
    bool swapEyes = false; // right eye first
    QString group; // "", "interleaved", "anaglyph", "depth": the menu's grouping
};

QList<Packing> packings();
Packing packingById(const QString &id);
}
