// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QImage>
#include <QObject>
#include <QPointer>
#include <QRect>
#include <QWindow>
#include <memory>

/* A saver's pair as a surface of its own over a rectangle of a window: a
 * sub-surface of the window's surface, the two views side by side in one
 * buffer, declared full side by side once, sized by wp_viewport. The window
 * draws nothing over the rectangle, so the surface lies above it and no hole
 * is needed (System Settings hosts a page in a QQuickWidget, which has no
 * surface of its own to lay anything under). Adapted from the stereo show's
 * StereoBackground (gl-stereo, plasma/stereobackground.cpp). */
class PairSurface : public QObject
{
    Q_OBJECT
public:
    explicit PairSurface(QObject *parent = nullptr);
    ~PairSurface() override;

    /* Whether the compositor takes a declared pair at all. */
    static bool supported();
    /* Why the last show() failed; empty when it did not. Not translated: a log word. */
    QString failure() const { return m_failure; }
    bool active() const { return m_active; }

    /* The rectangle in the window's own pixels. Makes the surface when needed. False when it cannot be made. */
    bool place(QWindow *host, const QRect &rect);
    /* One picture, two views wide (RGBA8888). False when the pair cannot be shown. */
    bool show(const QImage &pair);
    void hide();

    /* The person's limits as Stereo KWin resolves them for this surface's
     * screen, converted to the buffer of one view BUFFER wide that is shown
     * SHOWN device pixels wide on a screen OUTPUT device pixels wide. */
    bool limits(double output, double buffer, double shown, double *sunk, double *popped) const;

Q_SIGNALS:
    void limitsChanged();

protected:
    bool eventFilter(QObject *object, QEvent *event) override;

private:
    struct Private;
    std::unique_ptr<Private> d;
    QPointer<QWindow> m_host;
    QRect m_rect;
    QString m_failure;
    bool m_active = false;
};
