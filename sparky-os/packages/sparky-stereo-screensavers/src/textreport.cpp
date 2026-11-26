// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include "textreport.h"

#include <QColor>
#include <QFont>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQuickItem>
#include <QQuickWindow>

#include <algorithm>

namespace
{
double number(const QQuickItem *item, const char *name, double otherwise)
{
    const QVariant value = item->property(name);
    return value.isValid() ? value.toDouble() : otherwise;
}

/* Where the glyphs are inside a text item: its content size, placed by its alignment and padding. */
QRectF glyphBox(const QQuickItem *item)
{
    const double w = item->width(), h = item->height();
    const double cw = std::min(number(item, "contentWidth", w), w), ch = std::min(number(item, "contentHeight", h), h);
    const double left = number(item, "leftPadding", 0), right = number(item, "rightPadding", 0), top = number(item, "topPadding", 0), bottom = number(item, "bottomPadding", 0);
    QVariant align = item->property("effectiveHorizontalAlignment");
    if (!align.isValid()) {
        align = item->property("horizontalAlignment");
    }
    const int horizontal = align.toInt(), vertical = item->property("verticalAlignment").toInt();
    double x = left, y = top;
    if (horizontal & Qt::AlignRight) {
        x = w - right - cw;
    } else if (horizontal & Qt::AlignHCenter) {
        x = left + (w - left - right - cw) / 2;
    }
    if (vertical & Qt::AlignBottom) {
        y = h - bottom - ch;
    } else if (vertical & Qt::AlignVCenter) {
        y = top + (h - top - bottom - ch) / 2;
    }
    return QRectF(x, y, cw, ch) & QRectF(0, 0, w, h);
}

void collect(const QQuickItem *item, QRectF shown, double opacity, const QPoint &offset, QJsonArray &texts)
{
    if (!item->isVisible()) {
        return;
    }
    opacity *= item->opacity();
    if (opacity <= 0) {
        return;
    }
    if (item->clip()) {
        shown &= item->mapRectToScene(QRectF(0, 0, item->width(), item->height())).translated(offset);
    }
    const bool input = item->inherits("QQuickTextInput") || item->inherits("QQuickTextEdit");
    if (input || item->inherits("QQuickText")) {
        QString text = item->property(input ? "displayText" : "text").toString();
        if (text.isEmpty()) {
            text = item->property("text").toString();
        }
        const QRectF box = item->mapRectToScene(glyphBox(item)).translated(offset) & shown;
        const QColor colour = item->property("color").value<QColor>();
        if (!text.trimmed().isEmpty() && box.width() >= 3 && box.height() >= 3) {
            texts.append(QJsonObject{{QStringLiteral("text"), text.left(80)},
                                     {QStringLiteral("box"), QJsonArray{box.x(), box.y(), box.width(), box.height()}},
                                     {QStringLiteral("colour"), QJsonArray{colour.red(), colour.green(), colour.blue(), colour.alpha()}},
                                     {QStringLiteral("opacity"), opacity},
                                     {QStringLiteral("enabled"), item->isEnabled()},
                                     {QStringLiteral("pixelSize"), item->property("font").value<QFont>().pixelSize()},
                                     {QStringLiteral("pointSize"), item->property("font").value<QFont>().pointSizeF()},
                                     {QStringLiteral("kind"), QString::fromLatin1(item->metaObject()->className())}});
        }
    }
    const int before = texts.size();
    const QList<QQuickItem *> children = item->childItems();
    for (const QQuickItem *child : children) {
        collect(child, shown, opacity, offset, texts);
    }
    // A button whose caption no text item draws: the desktop style has the widget style paint it. Its colour is not
    // known here; the caption stands right of the icon, so the right half of the button holds glyphs of it and no icon.
    const QString caption = item->inherits("QQuickAbstractButton") ? item->property("text").toString() : QString();
    if (!caption.trimmed().isEmpty() && item->property("display").toInt() != 0 /* IconOnly */ && texts.size() == before) {
        const QRectF half(item->width() / 2, 5, item->width() / 2 - 7, item->height() - 10);
        const QRectF box = item->mapRectToScene(half).translated(offset) & shown;
        if (box.width() >= 6 && box.height() >= 6) {
            texts.append(QJsonObject{{QStringLiteral("text"), caption.left(80)},
                                     {QStringLiteral("box"), QJsonArray{box.x(), box.y(), box.width(), box.height()}},
                                     {QStringLiteral("opacity"), opacity},
                                     {QStringLiteral("enabled"), item->isEnabled()},
                                     {QStringLiteral("kind"), QStringLiteral("button caption drawn by the widget style")}});
        }
    }
}
}

QByteArray TextReport::json(QQuickWindow *page, const QWindow *host, const QPoint &offset, int serial)
{
    QJsonArray texts;
    if (page && page->contentItem()) {
        collect(page->contentItem(), QRectF(offset, QSizeF(page->size())), 1.0, offset, texts);
    }
    const QJsonObject report{{QStringLiteral("serial"), serial},
                             {QStringLiteral("scale"), host ? host->devicePixelRatio() : 1.0},
                             {QStringLiteral("window"), host ? QJsonArray{host->width(), host->height()} : QJsonArray{}},
                             {QStringLiteral("active"), host ? host->isActive() : false},
                             {QStringLiteral("texts"), texts}};
    return QJsonDocument(report).toJson(QJsonDocument::Compact);
}
