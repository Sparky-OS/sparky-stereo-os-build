// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QColor>

/* A quieter text of the page (a count, a mark, a credit) keeps the colour the
 * person's colour scheme gives it only when that colour can be read on its
 * background: WCAG 2.2, 1.4.3, a contrast of 4.5:1. Below that it is moved
 * towards the scheme's normal text colour by the smallest step that reaches
 * 4.5:1, and past it towards black or white when the normal text is short too. */
namespace ReadableText
{
constexpr double LEAST = 4.5;

/* WCAG 2.2 relative luminance of an opaque sRGB colour. */
double luminance(const QColor &colour);
/* WCAG 2.2 contrast ratio, 1 to 21. */
double contrast(const QColor &one, const QColor &other);
QColor colour(const QColor &wanted, const QColor &text, const QColor &background, double least = LEAST);
}
