// SPDX-License-Identifier: GPL-2.0-or-later
#include "preview.h"
#include <QPainter>
#include <QMouseEvent>
Preview::Preview() { setFixedSize(256, 256); backend = makePreviewBackend(this); }
Preview::~Preview() = default;
void Preview::setViews(const QImage &a, const QImage &b, bool stereo)
{
    left = a;
    setFixedSize(256, qMax(1, qRound(256.0 * a.height() / a.width())));
    backend->setViews(a, b, stereo); update();
}
void Preview::paintEvent(QPaintEvent *)
{
    QPainter painter(this); painter.fillRect(rect(), Qt::black); backend->paint(&painter);
}
void Preview::mousePressEvent(QMouseEvent *event)
{
    if (event->button() == Qt::LeftButton && picked) { picked(event->position()); event->accept(); }
    else QWidget::mousePressEvent(event);
}
