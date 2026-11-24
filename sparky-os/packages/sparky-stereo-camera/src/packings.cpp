// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "packings.h"
#include <KLocalizedString>
#include <stereo-policy.h>

using namespace Sparky::Camera;

namespace
{
QString previewInput(const stereo_policy_input_format &format)
{
    if (format.view == STEREO_POLICY_VIEW_MONO)
        return QStringLiteral("StereoNone");
    if (format.anaglyph == STEREO_POLICY_ANAGLYPH_RED_CYAN)
        return QStringLiteral("StereoAnaglyphCyanRed");
    if (format.anaglyph == STEREO_POLICY_ANAGLYPH_GREEN_MAGENTA)
        return QStringLiteral("StereoAnaglyphGreenMagenta");
    if (format.anaglyph != STEREO_POLICY_ANAGLYPH_NONE)
        return {};
    switch (format.layout) {
    case STEREO_POLICY_LAYOUT_NONE: return QStringLiteral("StereoAutomatic");
    case STEREO_POLICY_LAYOUT_SIDE_BY_SIDE: return QStringLiteral("StereoSideBySide");
    case STEREO_POLICY_LAYOUT_TOP_AND_BOTTOM: return QStringLiteral("StereoTopBottom");
    case STEREO_POLICY_LAYOUT_ROWS: return QStringLiteral("StereoRowInterleaved");
    case STEREO_POLICY_LAYOUT_COLUMNS: return QStringLiteral("StereoColumnInterleaved");
    case STEREO_POLICY_LAYOUT_CHECKERBOARD: return QStringLiteral("StereoCheckerboard");
    case STEREO_POLICY_LAYOUT_SIDE_BY_SIDE_QUINCUNX: return QStringLiteral("StereoSideBySideQuincunx");
    case STEREO_POLICY_LAYOUT_FRAME_SEQUENTIAL: return {}; // PreviewSource does not preserve the source frame ordinal.
    case STEREO_POLICY_LAYOUT_DEPTH_SIDE_BY_SIDE:
        return format.order == STEREO_POLICY_DEPTH_FIRST ? QStringLiteral("StereoDepthSideBySideDepthFirst") : QStringLiteral("StereoDepthSideBySide");
    case STEREO_POLICY_LAYOUT_DEPTH_TOP_AND_BOTTOM:
        return format.order == STEREO_POLICY_DEPTH_FIRST ? QStringLiteral("StereoDepthTopBottomDepthFirst") : QStringLiteral("StereoDepthTopBottom");
    case STEREO_POLICY_LAYOUT_DEPTH_GRAPHICS: return QStringLiteral("StereoDepthGraphics");
    case STEREO_POLICY_LAYOUT_DEPTH_BACKGROUND: return QStringLiteral("StereoDepthBackground");
    default: return {}; // The existing preview refusal remains visible for an unsupported input.
    }
}
}

QList<Packing> Sparky::Camera::packings()
{
    QList<Packing> result;
    for (size_t i = 0; i < stereo_policy_input_format_count(); ++i) {
        const auto *format = stereo_policy_input_format_at(i);
        const QString group = format->group == 2 ? QStringLiteral("interleaved")
            : format->group == 3 ? QStringLiteral("sequence")
            : format->group == 4 ? QStringLiteral("anaglyph")
            : format->group == 5 ? QStringLiteral("depth") : QString();
        result.append({QString::fromLatin1(format->id), i18n(format->text), previewInput(*format),
                       !stereo_policy_is_depth_layout(format->layout) && format->order == STEREO_POLICY_RIGHT_FIRST, group});
    }
    return result;
}

Packing Sparky::Camera::packingById(const QString &id)
{
    for (const Packing &p : packings()) {
        if (p.id == id)
            return p;
    }
    return {}; // An unknown saved value must not silently become Automatic or Not 3D.
}
