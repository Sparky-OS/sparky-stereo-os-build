// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QByteArray>
#include <QPoint>

class QQuickWindow;
class QWindow;

/* A proof aid, off unless SPARKY_SAVER_TEXT_REPORT names a file: every text the
 * page draws, as JSON, with its box in the window's own pixels, the colour and
 * opacity it asks for and whether it is enabled. A capture of the screen is
 * measured against it (contrast of each text on its background). */
namespace TextReport
{
QByteArray json(QQuickWindow *page, const QWindow *host, const QPoint &offset, int serial);
}
