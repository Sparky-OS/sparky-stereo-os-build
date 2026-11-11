// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#include "mpris.h"
#include <KLocalizedString>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <limits>
#include <QTimer>

PlayerAdaptor::PlayerAdaptor(QObject *object, Backend *backend, std::function<QString(std::function<void()>)> handler, std::function<bool()> isBusy)
    : QObject(object)
    , busy(std::move(isBusy))
    , b(backend)
    , execute(std::move(handler))
{
    connect(b, &Backend::seeked, this, &PlayerAdaptor::Seeked);
    connect(b, &Backend::changed, this, [this] {
        QVariantMap properties{{QStringLiteral("PlaybackStatus"), playbackStatus()},
                               {QStringLiteral("Metadata"), metadata()},
                               {QStringLiteral("Volume"), volume()},
                               {QStringLiteral("CanControl"), canControl()},
                               {QStringLiteral("CanPlay"), canPlay()},
                               {QStringLiteral("CanPause"), canPause()},
                               {QStringLiteral("CanSeek"), canSeek()}};
        auto signal = QDBusMessage::createSignal(QStringLiteral("/org/mpris/MediaPlayer2"),
                                                 QStringLiteral("org.freedesktop.DBus.Properties"),
                                                 QStringLiteral("PropertiesChanged"));
        signal << QStringLiteral("org.mpris.MediaPlayer2.Player") << properties << QStringList{};
        QDBusConnection::sessionBus().send(signal);
    });
}
QVariantMap PlayerAdaptor::metadata() const
{
    if (b->track.isEmpty())
        return {};
    return {{QStringLiteral("mpris:trackid"), QVariant::fromValue(QDBusObjectPath(b->track))},
            {QStringLiteral("mpris:length"), b->duration},
            {QStringLiteral("xesam:title"), b->title}};
}
void PlayerAdaptor::run(std::function<void()> action)
{
    if (calledFromDBus()) {
        const auto request = message();
        request.setDelayedReply(true);
        runDbus(std::move(action), request, 200);
    } else {
        execute(std::move(action));
    }
}
void PlayerAdaptor::runDbus(std::function<void()> action, const QDBusMessage &request, int attempts)
{
    if (busy() && attempts > 0) {
        QTimer::singleShot(50, this, [this, action, request, attempts] { runDbus(action, request, attempts - 1); });
        return;
    }
    const auto error = execute(std::move(action));
    QDBusConnection::sessionBus().send(error.isEmpty() ? request.createReply() : request.createErrorReply(QStringLiteral("org.mpris.MediaPlayer2.Error.Failed"), error));
}

void PlayerAdaptor::Play()
{
    if (canPlay())
        run([this] {
            b->transport(QStringLiteral("Play"));
        });
}
void PlayerAdaptor::Pause()
{
    if (canPause())
        run([this] {
            b->transport(QStringLiteral("Pause"));
        });
}
void PlayerAdaptor::PlayPause()
{
    run([this] {
        b->transport(b->status == QLatin1String("Playing") ? QStringLiteral("Pause") : QStringLiteral("Play"));
    });
}
void PlayerAdaptor::Stop()
{
    run([this] {
        b->transport(QStringLiteral("Stop"));
    });
}
void PlayerAdaptor::setVolume(double value)
{
    run([this, value] {
        b->setVolume(value);
    });
}
void PlayerAdaptor::Seek(qlonglong offset)
{
    if (!canSeek())
        return;
    if (offset > 0 && offset > std::numeric_limits<qint64>::max() - b->position)
        return;
    if (offset < 0 && offset < -b->position)
        offset = -b->position;
    const auto target = b->position + offset;
    if (b->duration > 0 && target > b->duration)
        return; // No next track.
    run([this, target] {
        b->seek(target);
    });
}
void PlayerAdaptor::SetPosition(const QDBusObjectPath &track, qlonglong position)
{
    if (!canSeek() || b->track.isEmpty() || track.path() != b->track || position < 0 || (b->duration > 0 && position > b->duration))
        return;
    run([this, position] {
        b->seek(position);
    });
}
void PlayerAdaptor::OpenUri(const QString &)
{
    if (calledFromDBus())
        sendErrorReply(QStringLiteral("org.mpris.MediaPlayer2.Error.NotSupported"), i18n("Choose a shared file with Play on TV or Play on the headset."));
}
RootAdaptor::RootAdaptor(QObject *object, Backend *backend, std::function<void()> raise)
    : QDBusAbstractAdaptor(object)
    , b(backend)
    , show(std::move(raise))
{
}
QString RootAdaptor::identity() const
{
    return b->name;
}
void RootAdaptor::Raise()
{
    show();
}
void RootAdaptor::Quit()
{
    QCoreApplication::quit();
}
