// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "pairsurface.h"
#include "saverrunner.h"

#include <QQuickPaintedItem>
#include <QRasterWindow>
#include <QTimer>

class FullScreenPreview;

/* The page's preview: the selected saver, running, in the item's rectangle.
 * A catalogue saver's pair is a declared surface over the rectangle; a 2D
 * saver, and a pair that cannot be shown as one, is an ordinary picture. */
class SaverPreview : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(QString saver READ saver WRITE setSaver NOTIFY saverChanged)
    Q_PROPERTY(bool stereo READ stereo WRITE setStereo NOTIFY saverChanged)
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(bool showing READ showing NOTIFY stateChanged)
    Q_PROPERTY(bool pairShown READ pairShown NOTIFY stateChanged)
    Q_PROPERTY(QString pairNote READ pairNote NOTIFY stateChanged)
    Q_PROPERTY(int failure READ failure NOTIFY stateChanged)
    Q_PROPERTY(QString failureDetail READ failureDetail NOTIFY stateChanged)
    Q_PROPERTY(bool fullScreenOpen READ fullScreenOpen NOTIFY fullScreenChanged)
    Q_PROPERTY(double separation READ separation NOTIFY stateChanged)

public:
    explicit SaverPreview(QQuickItem *parent = nullptr);
    ~SaverPreview() override;

    QString saver() const { return m_saver; }
    void setSaver(const QString &saver);
    bool stereo() const { return m_stereo; }
    void setStereo(bool stereo);
    bool active() const { return m_active; }
    void setActive(bool active);
    bool showing() const { return !m_runner.frame().isNull(); }
    bool pairShown() const { return m_surface.active(); }
    QString pairNote() const { return m_pairNote; }
    int failure() const { return m_failure; }
    QString failureDetail() const { return m_failureDetail; }
    bool fullScreenOpen() const { return m_full != nullptr; }
    double separation() const { return m_separation; }

    void paint(QPainter *painter) override;
    Q_INVOKABLE void fullScreen();
    Q_INVOKABLE void retry();

    /* The share of one view's width that puts the person's sunk limit on the screen at the size the pair is shown. */
    static double shareFor(double sunkInBuffer, double bufferWidth);

Q_SIGNALS:
    void saverChanged();
    void activeChanged();
    void stateChanged();
    void fullScreenChanged();

protected:
    void itemChange(ItemChange change, const ItemChangeData &value) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

private:
    void restart();
    void begin();
    void follow();
    void onFrame();
    QWindow *host(QPoint *offset) const;
    QRect place(QWindow **hostOut) const;
    SaverRunner m_runner;
    PairSurface m_surface;
    QTimer m_restart;
    QTimer m_follow;
    QString m_saver;
    QString m_pairNote;
    QString m_failureDetail;
    QRect m_rect;
    FullScreenPreview *m_full = nullptr;
    int m_failure = 0;
    double m_separation = -1;
    bool m_stereo = false;
    bool m_active = false;
    bool m_wasShowing = false;
};

/* The selected saver over the whole screen. It ends as a saver does: a key, a
 * button, a touch, or the pointer moved more than a hand's rest. */
class FullScreenPreview : public QRasterWindow
{
    Q_OBJECT
public:
    FullScreenPreview(const QString &saver, bool stereo, QScreen *screen);
    ~FullScreenPreview() override;
    void begin();

Q_SIGNALS:
    void ended(int failure, const QString &detail);

protected:
    void paintEvent(QPaintEvent *event) override;
    void keyPressEvent(QKeyEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void touchEvent(QTouchEvent *event) override;
    void exposeEvent(QExposeEvent *event) override;

private:
    void end(int failure = 0, const QString &detail = {});
    SaverRunner m_runner;
    PairSurface m_surface;
    QString m_saver;
    QPointF m_first;
    bool m_stereo;
    bool m_haveFirst = false;
    bool m_started = false;
    bool m_ended = false;
};
