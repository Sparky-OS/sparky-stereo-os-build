// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include "backend.h"
#include <QDBusAbstractAdaptor>
#include <QDBusContext>
#include <QDBusObjectPath>
#include <QVariantMap>
#include <functional>

class PlayerAdaptor : public QDBusAbstractAdaptor, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2.Player")
    Q_PROPERTY(QString PlaybackStatus READ playbackStatus)
    Q_PROPERTY(double Rate READ rate WRITE setRate)
    Q_PROPERTY(QVariantMap Metadata READ metadata)
    Q_PROPERTY(double Volume READ volume WRITE setVolume)
    Q_PROPERTY(qlonglong Position READ position)
    Q_PROPERTY(double MinimumRate READ rate)
    Q_PROPERTY(double MaximumRate READ rate)
    Q_PROPERTY(bool CanGoNext READ no)
    Q_PROPERTY(bool CanGoPrevious READ no)
    Q_PROPERTY(bool CanPlay READ canPlay)
    Q_PROPERTY(bool CanPause READ canPause)
    Q_PROPERTY(bool CanSeek READ canSeek)
    Q_PROPERTY(bool CanControl READ canControl)
public:
    PlayerAdaptor(QObject *object, Backend *backend, std::function<QString(std::function<void()>)> execute);
    QString playbackStatus() const { return b->status; }
    double rate() const { return 1; }
    void setRate(double) {}
    bool no() const { return false; }
    double volume() const { return b->volume; }
    qlonglong position() const { return b->position; }
    bool canControl() const { return b->connected; }
    bool canPlay() const { return b->connected && b->supports(QStringLiteral("AVTransport"), QStringLiteral("Play")); }
    bool canPause() const { return b->connected && b->supports(QStringLiteral("AVTransport"), QStringLiteral("Pause")); }
    bool canSeek() const { return b->connected && b->supports(QStringLiteral("AVTransport"), QStringLiteral("Seek")) && b->supports(QStringLiteral("AVTransport"), QStringLiteral("GetPositionInfo")); }
    QVariantMap metadata() const;
    void setVolume(double value);
public Q_SLOTS:
    void Next() {}
    void Previous() {}
    void Play();
    void Pause();
    void PlayPause();
    void Stop();
    void Seek(qlonglong offset);
    void SetPosition(const QDBusObjectPath &track, qlonglong position);
    void OpenUri(const QString &uri);
Q_SIGNALS:
    void Seeked(qlonglong position);
private:
    void run(std::function<void()> action);
    Backend *b;
    std::function<QString(std::function<void()>)> execute;
};

class RootAdaptor : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2")
    Q_PROPERTY(bool CanQuit READ yes)
    Q_PROPERTY(bool CanRaise READ yes)
    Q_PROPERTY(bool HasTrackList READ no)
    Q_PROPERTY(QString Identity READ identity)
    Q_PROPERTY(QString DesktopEntry READ desktopEntry)
    Q_PROPERTY(QStringList SupportedUriSchemes READ empty)
    Q_PROPERTY(QStringList SupportedMimeTypes READ empty)
public:
    RootAdaptor(QObject *object, Backend *backend, std::function<void()> raise);
    bool yes() const { return true; }
    bool no() const { return false; }
    QString identity() const;
    QString desktopEntry() const { return QStringLiteral("ums-renderer"); }
    QStringList empty() const { return {}; }
public Q_SLOTS:
    void Raise();
    void Quit();
private:
    Backend *b;
    std::function<void()> show;
};
