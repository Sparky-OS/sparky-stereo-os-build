// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include <QObject>
#include <QPointer>
#include <QQuickWindow>
#include <memory>
class FrameClient;

class StereoBackground : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
public:
    StereoBackground(QQuickWindow *window, FrameClient *client);
    ~StereoBackground() override;
    bool active() const { return m_active; }
Q_SIGNALS:
    void activeChanged();
protected:
    bool eventFilter(QObject *object, QEvent *event) override;
private:
    void update();
    void reset();
    struct Private;
    std::unique_ptr<Private> d;
    QPointer<QQuickWindow> m_window;
    FrameClient *m_client;
    QColor m_color;
    bool m_active = false;
};
