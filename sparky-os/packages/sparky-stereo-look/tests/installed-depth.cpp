// SPDX-License-Identifier: GPL-2.0-or-later
// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
#include <stereodepth.h>
#include <QGuiApplication>
#include <QQuickItem>
#include <iostream>

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    QQuickItem item;
    Stereo::DepthAttached depth(&item);
    if (depth.artworkDepthMultiple() != 1)
        return 1;
    depth.setDepth(2);
    if (depth.depth() != 1 || Stereo::Depth::parallaxFor(2, 4, 10, 1920) != 4)
        return 2;
    depth.setArtworkDepthMultiple(2);
    if (depth.artworkDepthMultiple() != 2 || depth.parallax() != 0 || depth.shown())
        return 3;
    if (Stereo::Depth::parallaxFor(1, 4, 10, 1920, 2) != 8
        || Stereo::Depth::parallaxFor(1, 8, 20, 1920, 2) != 16
        || Stereo::Depth::parallaxFor(1, 4, 10, 1600, 2) != 7
        || Stereo::Depth::parallaxFor(1, 0, 0, 1920, 2) != 0)
        return 4;
    std::cout << "installed C++ API: ordinary clamp, explicit multiple, rounding and flat controls passed\n";
}
