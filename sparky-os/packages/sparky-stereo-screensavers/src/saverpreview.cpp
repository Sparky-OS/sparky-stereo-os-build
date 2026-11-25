// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include "saverpreview.h"

#include <QGuiApplication>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QTouchEvent>
#include <QWheelEvent>
#include <QLoggingCategory>
#include <QPainter>
#include <QQuickRenderControl>
#include <QQuickWindow>
#include <QScreen>

#include <cmath>

Q_DECLARE_LOGGING_CATEGORY(pairLog)

namespace
{
const int HAND_REST = 10; // XScreenSaver's own pointer hysteresis, in pixels

double screenWidth(const QWindow *window)
{
    const QScreen *screen = window ? window->screen() : nullptr;
    return screen ? screen->size().width() * screen->devicePixelRatio() : 0;
}
}

double SaverPreview::shareFor(double sunkInBuffer, double bufferWidth)
{
    if (bufferWidth <= 0 || sunkInBuffer < 0) {
        return -1;
    }
    return qBound(0.0, 100.0 * sunkInBuffer / bufferWidth, 10.0);
}

SaverPreview::SaverPreview(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setFillColor(Qt::black);
    m_restart.setSingleShot(true);
    m_restart.setInterval(300);
    connect(&m_restart, &QTimer::timeout, this, &SaverPreview::begin);
    m_follow.setInterval(150);
    connect(&m_follow, &QTimer::timeout, this, &SaverPreview::follow);
    connect(&m_runner, &SaverRunner::frameChanged, this, &SaverPreview::onFrame);
    connect(&m_surface, &PairSurface::limitsChanged, this, [this] {
        if (m_waited && !m_runner.running()) {
            m_restart.stop();
            begin();
        } else if (m_runner.running() && m_stereo) {
            restart(); // the person changed the depth limits: the saver is drawn again with them
        }
    });
    connect(&m_runner, &SaverRunner::failed, this, [this](SaverRunner::Failure failure, const QString &detail) {
        m_surface.hide();
        m_failure = failure;
        m_failureDetail = detail;
        update();
        Q_EMIT stateChanged();
    });
}

SaverPreview::~SaverPreview()
{
    delete m_full;
}

void SaverPreview::setSaver(const QString &saver)
{
    if (saver == m_saver) {
        return;
    }
    m_saver = saver;
    Q_EMIT saverChanged();
    restart();
}

void SaverPreview::setStereo(bool stereo)
{
    if (stereo == m_stereo) {
        return;
    }
    m_stereo = stereo;
    Q_EMIT saverChanged();
    restart();
}

void SaverPreview::setActive(bool active)
{
    if (active == m_active) {
        return;
    }
    m_active = active;
    Q_EMIT activeChanged();
    restart();
}

void SaverPreview::retry()
{
    restart();
}

void SaverPreview::itemChange(ItemChange change, const ItemChangeData &value)
{
    QQuickPaintedItem::itemChange(change, value);
    if (change == ItemVisibleHasChanged || change == ItemSceneChange) {
        restart();
    }
}

void SaverPreview::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickPaintedItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size()) {
        restart();
    }
}

QWindow *SaverPreview::host(QPoint *offset) const
{
    QQuickWindow *quick = window();
    if (!quick) {
        return nullptr;
    }
    // System Settings draws a page into a QQuickWidget: the window on screen is the one the page is rendered for
    if (QWindow *real = QQuickRenderControl::renderWindowFor(quick, offset)) {
        return real;
    }
    *offset = QPoint();
    return quick;
}

QRect SaverPreview::place(QWindow **hostOut) const
{
    QPoint offset;
    QWindow *real = host(&offset);
    *hostOut = real;
    if (!real || !isVisible() || width() < 72 || height() < 72) {
        return {};
    }
    // whole device pixels at 100, 125, 150 and 175 %: corners on multiples of 4, the width on a multiple of 8
    const QPointF corner = mapToScene(QPointF(0, 0)) + offset;
    const int x = int(std::ceil(corner.x() / 4.0)) * 4;
    const int y = int(std::ceil(corner.y() / 4.0)) * 4;
    const int w = int(std::floor((corner.x() + width() - x) / 8.0)) * 8;
    const int h = int(std::floor((corner.y() + height() - y) / 4.0)) * 4;
    const QRect rect(x, y, w, h);
    const QRect page(offset, window()->size());
    if (w < 64 || h < 64 || !QRect(QPoint(0, 0), real->size()).contains(rect) || !page.contains(rect)) {
        qCDebug(pairLog) << "preview place" << rect << "is not inside the window" << real->size() << "or the page" << page;
        return {};
    }
    // an ancestor that clips (a scrolled column) cuts the picture: the surface cannot be cut with it
    for (const QQuickItem *ancestor = parentItem(); ancestor; ancestor = ancestor->parentItem()) {
        if (ancestor->clip()) {
            const QRectF shown = ancestor->mapRectToScene(QRectF(0, 0, ancestor->width(), ancestor->height())).translated(offset).adjusted(-0.5, -0.5, 0.5, 0.5);
            if (!shown.contains(QRectF(rect))) {
                qCDebug(pairLog) << "preview place" << rect << "is cut by" << ancestor << shown;
                return {};
            }
        }
    }
    return rect;
}

void SaverPreview::restart()
{
    m_waited = false;
    m_runner.stop();
    m_surface.hide();
    m_follow.stop();
    m_failure = 0;
    m_failureDetail.clear();
    m_pairNote.clear();
    update();
    Q_EMIT stateChanged();
    if (m_active && !m_saver.isEmpty() && isVisible() && window() && !m_full) {
        m_restart.start();
    } else {
        m_restart.stop();
    }
}

void SaverPreview::begin()
{
    if (!m_active || m_saver.isEmpty() || !isVisible() || !window() || m_full) {
        return;
    }
    QWindow *real = nullptr;
    m_rect = place(&real);
    const double ratio = real ? real->devicePixelRatio() : 1.0;
    // one view is drawn at the size it is shown: the rectangle's own device pixels, never resized by the page
    QSize view(qRound(m_rect.width() * ratio), qRound(m_rect.height() * ratio));
    if (m_rect.isEmpty()) {
        view = QSize(int(width() / 8) * 8, int(height() / 4) * 4);
    }
    view = QSize(qBound(64, view.width() & ~1, 1280), qBound(64, view.height(), 720));
    m_separation = -1;
    m_ownDepth = false;
    m_pairNote.clear();
    if (m_stereo) {
        if (m_rect.isEmpty()) {
            m_pairNote = QStringLiteral("cut");
        } else {
            const bool placed = m_surface.place(real, m_rect);
            // the compositor's answers (that it takes pairs, the person's limits) come a moment after the first request
            if (!m_waited && (placed ? !m_surface.hasLimits() : m_surface.failure() == QLatin1String("no-stereo-compositor"))) {
                m_waited = true;
                m_restart.start(700);
                return;
            }
            double sunk = 0, popped = 0;
            if (!placed) {
                m_pairNote = m_surface.failure();
            } else if (qEnvironmentVariableIsSet("SPARKY_SAVER_OWN_SEPARATION")) {
                // a test's control: the saver's own share of its view, as the catalogue has it
            } else if (m_surface.limits(screenWidth(real), view.width(), view.width(), &sunk, &popped)) {
                m_separation = shareFor(sunk, view.width());
            } else {
                m_ownDepth = true;
                qCWarning(pairLog) << "the compositor gave no depth limits for the preview: the saver keeps its own separation";
            }
        }
    }
    m_waited = false;
    qCDebug(pairLog).nospace() << "preview " << m_saver << (m_stereo ? " pair" : " one view") << " place " << m_rect << " scale " << ratio << " view " << view
                               << " screen " << screenWidth(real) << " share " << m_separation << " note " << m_pairNote;
    m_runner.start(m_saver, view, m_separation);
    m_follow.start();
    Q_EMIT stateChanged();
}

void SaverPreview::follow()
{
    if (!m_runner.running()) {
        return;
    }
    QWindow *real = nullptr;
    const QRect now = place(&real);
    if (now.size() != m_rect.size() || (now.isEmpty() != m_rect.isEmpty())) {
        restart(); // another size is another picture: the saver is drawn again at it
        return;
    }
    if (now != m_rect && m_stereo && !now.isEmpty()) {
        m_rect = now;
        m_surface.place(real, m_rect);
    }
}

void SaverPreview::onFrame()
{
    const QImage &frame = m_runner.frame();
    if (frame.isNull()) {
        m_surface.hide();
    } else if (m_stereo && m_pairNote.isEmpty() && !m_rect.isEmpty()) {
        const bool was = m_surface.active();
        if (!m_surface.show(frame)) {
            m_pairNote = QStringLiteral("no-surface");
            m_surface.hide();
        }
        if (was != m_surface.active()) {
            Q_EMIT stateChanged();
        }
    }
    update();
    if (m_wasShowing != !frame.isNull()) {
        m_wasShowing = !frame.isNull();
        Q_EMIT stateChanged();
    }
}

void SaverPreview::paint(QPainter *painter)
{
    const QImage &frame = m_runner.frame();
    if (frame.isNull() || m_surface.active()) {
        return; // black: the pair's own surface lies over the rectangle
    }
    // one view: a 2D saver's picture, or the left view of a pair that cannot be shown as one
    const QRect source = m_stereo ? QRect(0, 0, frame.width() / 2, frame.height()) : frame.rect();
    QSizeF size = QSizeF(source.size()).scaled(QSizeF(width(), height()), Qt::KeepAspectRatio);
    const QRectF target((width() - size.width()) / 2, (height() - size.height()) / 2, size.width(), size.height());
    painter->setRenderHint(QPainter::SmoothPixmapTransform);
    painter->drawImage(target, frame, source);
}

void SaverPreview::fullScreen()
{
    if (m_full || m_saver.isEmpty() || !window()) {
        return;
    }
    QPoint offset;
    QWindow *real = host(&offset);
    m_runner.stop();
    m_surface.hide();
    m_restart.stop();
    m_failure = 0;
    m_full = new FullScreenPreview(m_saver, m_stereo, real ? real->screen() : QGuiApplication::primaryScreen());
    connect(m_full, &FullScreenPreview::ended, this, [this](int failure, const QString &detail) {
        m_full->deleteLater();
        m_full = nullptr;
        Q_EMIT fullScreenChanged();
        if (failure) {
            m_failure = failure;
            m_failureDetail = detail;
            update();
            Q_EMIT stateChanged();
        } else {
            restart();
        }
    });
    Q_EMIT fullScreenChanged();
    Q_EMIT stateChanged();
    m_full->begin();
}

FullScreenPreview::FullScreenPreview(const QString &saver, bool stereo, QScreen *screen)
    : m_saver(saver)
    , m_stereo(stereo)
{
    setScreen(screen);
    setFlags(Qt::Window | Qt::FramelessWindowHint);
    setCursor(Qt::BlankCursor);
    setTitle(QStringLiteral("Screensaver preview"));
    connect(&m_runner, &SaverRunner::frameChanged, this, [this] {
        const QImage &frame = m_runner.frame();
        if (!frame.isNull() && m_stereo && m_surface.failure().isEmpty()) {
            m_surface.show(frame);
        }
        update();
    });
    connect(&m_runner, &SaverRunner::failed, this, [this](SaverRunner::Failure failure, const QString &detail) {
        end(failure, detail);
    });
    connect(&m_surface, &PairSurface::limitsChanged, this, &FullScreenPreview::start);
}

FullScreenPreview::~FullScreenPreview()
{
    m_runner.stop();
}

void FullScreenPreview::begin()
{
    showFullScreen();
}

void FullScreenPreview::exposeEvent(QExposeEvent *event)
{
    QRasterWindow::exposeEvent(event);
    if (isExposed() && !m_started && !m_ended) {
        m_started = true;
        start();
    }
}

void FullScreenPreview::start()
{
    if (m_ended || m_runner.running()) {
        return;
    }
    // the show's own size for one view (640 wide), at the screen's shape; Stereo KWin resizes once
    const int high = qBound(64, (qRound(640.0 * height() / qMax(1, width())) / 2) * 2, 720);
    const QSize view(640, high);
    double share = -1;
    if (m_stereo) {
        const bool placed = m_surface.place(this, QRect(QPoint(0, 0), size()));
        if (!m_waited && (placed ? !m_surface.hasLimits() : m_surface.failure() == QLatin1String("no-stereo-compositor"))) {
            m_waited = true;
            QTimer::singleShot(700, this, &FullScreenPreview::start);
            return;
        }
        double sunk = 0, popped = 0;
        const double shown = width() * devicePixelRatio();
        if (!placed || qEnvironmentVariableIsSet("SPARKY_SAVER_OWN_SEPARATION")) {
            // one view, or a test's control
        } else if (m_surface.limits(screenWidth(this), view.width(), shown, &sunk, &popped)) {
            share = SaverPreview::shareFor(sunk, view.width());
        } else {
            qCWarning(pairLog) << "the compositor gave no depth limits for the full-screen preview: the saver keeps its own separation";
        }
    }
    qCDebug(pairLog).nospace() << "full screen " << m_saver << (m_stereo ? " pair" : " one view") << " window " << size() << " scale " << devicePixelRatio()
                               << " view " << view << " screen " << screenWidth(this) << " share " << share << " note " << m_surface.failure();
    m_runner.start(m_saver, view, share);
}

void FullScreenPreview::paintEvent(QPaintEvent *)
{
    QPainter painter(this);
    painter.fillRect(QRect(QPoint(0, 0), size()), Qt::black);
    const QImage &frame = m_runner.frame();
    if (frame.isNull() || m_surface.active()) {
        return;
    }
    const QRect source = m_stereo ? QRect(0, 0, frame.width() / 2, frame.height()) : frame.rect();
    painter.setRenderHint(QPainter::SmoothPixmapTransform);
    painter.drawImage(QRect(QPoint(0, 0), size()), frame, source);
}

void FullScreenPreview::end(int failure, const QString &detail)
{
    if (m_ended) {
        return;
    }
    qCDebug(pairLog) << "full screen ended" << failure << detail;
    m_ended = true;
    m_runner.stop();
    m_surface.hide();
    hide();
    Q_EMIT ended(failure, detail);
}

void FullScreenPreview::keyPressEvent(QKeyEvent *)
{
    end();
}

void FullScreenPreview::mousePressEvent(QMouseEvent *)
{
    end();
}

void FullScreenPreview::wheelEvent(QWheelEvent *)
{
    end();
}

void FullScreenPreview::touchEvent(QTouchEvent *)
{
    end();
}

void FullScreenPreview::mouseMoveEvent(QMouseEvent *event)
{
    if (!m_haveFirst) {
        m_first = event->globalPosition();
        m_haveFirst = true;
    } else if ((event->globalPosition() - m_first).manhattanLength() > HAND_REST) {
        end();
    }
}
