// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <QObject>
#include <QPointer>
#include <QQuickWindow>
#include <QRectF>
#include <QStringList>
#include <QUrl>
#include <memory>

class F3DWorker;

// What the window shows and asks: the model, the animation, the three 3D options (Enable 3D, the resolution of one eye, the
// shortcut to Display Settings) and the sentences that say why something is not shown.
class Viewer : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString fileName READ fileName NOTIFY fileChanged)
    Q_PROPERTY(bool hasModel READ hasModel NOTIFY fileChanged)
    Q_PROPERTY(bool hasAnimation READ hasAnimation NOTIFY fileChanged)
    Q_PROPERTY(bool playing READ playing NOTIFY playingChanged)
    Q_PROPERTY(bool stereo READ stereo WRITE setStereo NOTIFY stereoChanged)
    Q_PROPERTY(int resolution READ resolution WRITE setResolution NOTIFY resolutionChanged)
    Q_PROPERTY(QString notice READ notice NOTIFY noticeChanged)
    Q_PROPERTY(QString problem READ problem NOTIFY problemChanged)
    Q_PROPERTY(QStringList recent READ recent NOTIFY recentChanged)
    Q_PROPERTY(QStringList nameFilters READ nameFilters CONSTANT)
public:
    explicit Viewer(QObject *parent = nullptr);
    ~Viewer() override;

    QString fileName() const { return m_fileName; }
    bool hasModel() const { return !m_path.isEmpty(); }
    bool hasAnimation() const { return m_hasAnimation; }
    bool playing() const { return m_playing; }
    bool stereo() const { return m_stereo; }
    void setStereo(bool on);
    int resolution() const { return m_resolution; }
    void setResolution(int percent);
    QString notice() const { return m_notice; }
    QString problem() const { return m_problem; }
    QStringList recent() const { return m_recent; }
    QStringList nameFilters() const;

    Q_INVOKABLE void open(const QUrl &url);
    Q_INVOKABLE void openPath(const QString &path);
    Q_INVOKABLE void reset();
    Q_INVOKABLE void togglePlay();
    Q_INVOKABLE void showDisplaySettings();
    Q_INVOKABLE void clearRecent();
    // the place of the 3D area in the window, in the window's logical pixels
    Q_INVOKABLE void place(QQuickWindow *window, qreal x, qreal y, qreal width, qreal height);

Q_SIGNALS:
    void fileChanged();
    void playingChanged();
    void stereoChanged();
    void resolutionChanged();
    void noticeChanged();
    void problemChanged();
    void recentChanged();

private:
    void depthState(int state);
    void remember(const QString &path);
    void sendPlace();

    std::unique_ptr<F3DWorker> m_worker;
    QString m_path;
    QString m_fileName;
    QString m_notice;
    QString m_problem;
    QStringList m_recent;
    bool m_hasAnimation = false;
    bool m_playing = false;
    bool m_stereo = true;
    int m_resolution = 100;
    QPointer<QQuickWindow> m_window;
    QRectF m_area;
    bool m_attached = false;
};
