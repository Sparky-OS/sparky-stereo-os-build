// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "packings.h"

#include <KLocalizedString>

using namespace Sparky::Camera;

// The ids and the English words are the layer's (src/picture/filechoicelist.cpp, context Stereo::FileChoiceMenu): the
// catalogues here hold the same sentence with the layer's own translation, so one camera and one file read alike.
QList<Packing> Sparky::Camera::packings()
{
    return {
        {QStringLiteral("mono"), i18n("Not 3D"), QStringLiteral("StereoNone"), false, QString()},
        {QStringLiteral("sideBySideLeftFirst"), i18n("Side by side, left eye first"), QStringLiteral("StereoSideBySide"), false, QString()},
        {QStringLiteral("sideBySideRightFirst"), i18n("Side by side, right eye first"), QStringLiteral("StereoSideBySide"), true, QString()},
        {QStringLiteral("topBottomLeftFirst"), i18n("Top and bottom, left eye first"), QStringLiteral("StereoTopBottom"), false, QString()},
        {QStringLiteral("topBottomRightFirst"), i18n("Top and bottom, right eye first"), QStringLiteral("StereoTopBottom"), true, QString()},
        {QStringLiteral("rowInterleavedLeftFirst"), i18n("Rows, left eye first"), QStringLiteral("StereoRowInterleaved"), false, QStringLiteral("interleaved")},
        {QStringLiteral("rowInterleavedRightFirst"), i18n("Rows, right eye first"), QStringLiteral("StereoRowInterleaved"), true, QStringLiteral("interleaved")},
        {QStringLiteral("columnInterleavedLeftFirst"), i18n("Columns, left eye first"), QStringLiteral("StereoColumnInterleaved"), false, QStringLiteral("interleaved")},
        {QStringLiteral("columnInterleavedRightFirst"), i18n("Columns, right eye first"), QStringLiteral("StereoColumnInterleaved"), true, QStringLiteral("interleaved")},
        {QStringLiteral("checkerboardLeftFirst"), i18n("Checkerboard, left eye first"), QStringLiteral("StereoCheckerboard"), false, QStringLiteral("interleaved")},
        {QStringLiteral("checkerboardRightFirst"), i18n("Checkerboard, right eye first"), QStringLiteral("StereoCheckerboard"), true, QStringLiteral("interleaved")},
        {QStringLiteral("sideBySideQuincunxLeftFirst"), i18n("Side by side quincunx, left eye first"), QStringLiteral("StereoSideBySideQuincunx"), false, QStringLiteral("interleaved")},
        {QStringLiteral("sideBySideQuincunxRightFirst"), i18n("Side by side quincunx, right eye first"), QStringLiteral("StereoSideBySideQuincunx"), true, QStringLiteral("interleaved")},
        {QStringLiteral("anaglyphCyanRed"), i18n("Red/cyan"), QStringLiteral("StereoAnaglyphCyanRed"), false, QStringLiteral("anaglyph")},
        {QStringLiteral("anaglyphGreenMagenta"), i18n("Green/magenta"), QStringLiteral("StereoAnaglyphGreenMagenta"), false, QStringLiteral("anaglyph")},
        {QStringLiteral("anaglyphAmberBlue"), i18n("Amber/blue"), QString(), false, QStringLiteral("anaglyph")},
        {QStringLiteral("depthSideBySidePictureFirst"), i18n("Side by side, picture first"), QStringLiteral("StereoDepthSideBySide"), false, QStringLiteral("depth")},
        {QStringLiteral("depthSideBySideDepthFirst"), i18n("Side by side, depth first"), QStringLiteral("StereoDepthSideBySideDepthFirst"), false, QStringLiteral("depth")},
        {QStringLiteral("depthTopBottomPictureFirst"), i18n("Top and bottom, picture first"), QStringLiteral("StereoDepthTopBottom"), false, QStringLiteral("depth")},
        {QStringLiteral("depthTopBottomDepthFirst"), i18n("Top and bottom, depth first"), QStringLiteral("StereoDepthTopBottomDepthFirst"), false, QStringLiteral("depth")},
        {QStringLiteral("depthGraphicsTopBottom"), i18n("Four rows: picture, depth, graphics, graphics depth"), QStringLiteral("StereoDepthGraphics"), false, QStringLiteral("depth")},
        {QStringLiteral("depthBackgroundQuarters"), i18n("Four quarters: picture, depth, background, background depth"), QStringLiteral("StereoDepthBackground"), false, QStringLiteral("depth")},
    };
}

Packing Sparky::Camera::packingById(const QString &id)
{
    for (const Packing &p : packings()) {
        if (p.id == id) {
            return p;
        }
    }
    return packings().first();
}
