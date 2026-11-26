// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include "readabletext.h"

#include <algorithm>
#include <cmath>

namespace
{
const int STEPS = 64;

double linear(int channel)
{
    const double v = channel / 255.0;
    return v <= 0.04045 ? v / 12.92 : std::pow((v + 0.055) / 1.055, 2.4);
}

QColor mixed(const QColor &from, const QColor &to, double share)
{
    return QColor(qRound(from.red() + (to.red() - from.red()) * share), qRound(from.green() + (to.green() - from.green()) * share),
                  qRound(from.blue() + (to.blue() - from.blue()) * share));
}

/* A translucent colour as it is seen: laid over the background. */
QColor seen(const QColor &colour, const QColor &background)
{
    return colour.alpha() == 255 ? colour : mixed(background, QColor(colour.red(), colour.green(), colour.blue()), colour.alphaF());
}

/* The first colour on the way from one to the other that reaches the contrast; invalid when none does. */
QColor firstReadable(const QColor &from, const QColor &to, const QColor &background, double least)
{
    for (int step = 0; step <= STEPS; ++step) {
        const QColor candidate = mixed(from, to, double(step) / STEPS);
        if (ReadableText::contrast(candidate, background) >= least) {
            return candidate;
        }
    }
    return {};
}
}

double ReadableText::luminance(const QColor &colour)
{
    return 0.2126 * linear(colour.red()) + 0.7152 * linear(colour.green()) + 0.0722 * linear(colour.blue());
}

double ReadableText::contrast(const QColor &one, const QColor &other)
{
    const double a = luminance(one), b = luminance(other);
    return (std::max(a, b) + 0.05) / (std::min(a, b) + 0.05);
}

QColor ReadableText::colour(const QColor &wanted, const QColor &text, const QColor &background, double least)
{
    if (!wanted.isValid() || !text.isValid() || !background.isValid()) {
        return text.isValid() ? text : wanted;
    }
    const QColor ground(background.red(), background.green(), background.blue());
    const QColor quiet = seen(wanted, ground), normal = seen(text, ground);
    QColor found = firstReadable(quiet, normal, ground, least);
    if (!found.isValid()) {
        // the scheme's own text is short of it on this background: on towards the end that is farther from the background
        const QColor black(0, 0, 0), white(255, 255, 255);
        const QColor end = contrast(black, ground) >= contrast(white, ground) ? black : white;
        found = firstReadable(normal, end, ground, std::min(least, contrast(end, ground)));
    }
    return found.isValid() ? found : normal;
}
