// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QList>
#include <QString>

// The packings a two-lens camera can deliver in one picture: the stereo layer's input list (Stereo::FileChoiceList),
// with its ids and its words, so a camera is described the way a file is. Cameras have no mark and no frame sequence.
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
