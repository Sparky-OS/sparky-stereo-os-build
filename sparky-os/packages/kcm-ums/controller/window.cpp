// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#include "window.h"
#include "mpris.h"
#include <KLocalizedString>
#include <QCryptographicHash>
#include <QDBusConnection>
#include <QFormLayout>
#include <QInputDialog>
#include <QLineEdit>
#include <QProcess>
#include <QScopedValueRollback>
#include <QTimer>
#include <QVBoxLayout>

Window::Window(const QUrl &server)
    : backend(server, this)
    , mprisObject(nullptr)
{
    setWindowTitle(i18n("Media Devices"));
    resize(620, 400);
    auto layout = new QVBoxLayout(this);
    devices = new QComboBox(this);
    devices->setObjectName(QStringLiteral("devices"));
    layout->addWidget(new QLabel(i18n("Device:"), this));
    layout->addWidget(devices);
    auto refreshButton = new QPushButton(i18n("Refresh Devices"), this);
    refreshButton->setObjectName(QStringLiteral("refresh"));
    layout->addWidget(refreshButton);
    file = new QLabel(this);
    file->setWordWrap(true);
    layout->addWidget(file);
    send = new QPushButton(i18n("Play Selected File"), this);
    send->setObjectName(QStringLiteral("send"));
    layout->addWidget(send);
    status = new QLabel(this);
    status->setObjectName(QStringLiteral("status"));
    layout->addWidget(status);
    auto controls = new QHBoxLayout;
    auto button = [&](const QString &text, const QString &name) {
        auto b = new QPushButton(text, this);
        b->setObjectName(name);
        controls->addWidget(b);
        return b;
    };
    back = button(i18n("Back 10 s"), QStringLiteral("back"));
    play = button(i18n("Play"), QStringLiteral("play"));
    pause = button(i18n("Pause"), QStringLiteral("pause"));
    stop = button(i18n("Stop"), QStringLiteral("stop"));
    forward = button(i18n("Forward 10 s"), QStringLiteral("forward"));
    layout->addLayout(controls);
    auto form = new QFormLayout;
    volume = new QSlider(Qt::Horizontal, this);
    volume->setObjectName(QStringLiteral("volume"));
    volume->setRange(0, 100);
    form->addRow(i18n("Volume:"), volume);
    layout->addLayout(form);
    brightnessRow = new QWidget(this);
    auto brightnessForm = new QFormLayout(brightnessRow);
    brightness = new QSlider(Qt::Horizontal, this);
    brightness->setRange(0, 100);
    brightnessForm->addRow(i18n("Brightness:"), brightness);
    layout->addWidget(brightnessRow);
    error = new QLabel(this);
    error->setWordWrap(true);
    error->setObjectName(QStringLiteral("error"));
    layout->addWidget(error);
    auto signIn = new QPushButton(i18n("Sign in to UMS"), this);
    layout->addWidget(signIn);
    auto settings = new QPushButton(i18n("Media Server Settings"), this);
    layout->addWidget(settings);
    connect(settings, &QPushButton::clicked, this, [] {
        QProcess::startDetached(QStringLiteral("systemsettings"), {QStringLiteral("kcm_ums")});
    });
    connect(signIn, &QPushButton::clicked, this, [this] {
        bool ok = false;
        const auto username = QInputDialog::getText(this, i18n("Sign in to UMS"), i18n("Username:"), QLineEdit::Normal, {}, &ok);
        if (!ok)
            return;
        const auto password = QInputDialog::getText(this, i18n("Sign in to UMS"), i18n("Password:"), QLineEdit::Password, {}, &ok);
        if (ok)
            execute([&] {
                backend.login(username, password);
                refresh();
            });
    });
    connect(refreshButton, &QPushButton::clicked, this, [this] {
        execute([this] {
            refresh();
        });
    });
    connect(devices, &QComboBox::activated, this, [this] {
        selected();
    });
    connect(send, &QPushButton::clicked, this, [this] {
        execute([this] {
            backend.sendFile(source);
        });
    });
    connect(play, &QPushButton::clicked, this, [this] {
        execute([this] {
            backend.transport(QStringLiteral("Play"));
        });
    });
    connect(pause, &QPushButton::clicked, this, [this] {
        execute([this] {
            backend.transport(QStringLiteral("Pause"));
        });
    });
    connect(stop, &QPushButton::clicked, this, [this] {
        execute([this] {
            backend.transport(QStringLiteral("Stop"));
        });
    });
    connect(back, &QPushButton::clicked, this, [this] {
        execute([this] {
            backend.seek(qMax<qint64>(0, backend.position - 10000000));
        });
    });
    connect(forward, &QPushButton::clicked, this, [this] {
        execute([this] {
            backend.seek(backend.position + 10000000);
        });
    });
    connect(volume, &QSlider::sliderReleased, this, [this] {
        execute([this] {
            backend.setVolume(volume->value() / 100.0);
        });
    });
    connect(brightness, &QSlider::sliderReleased, this, [this] {
        execute([this] {
            backend.setBrightness(brightness->value());
        });
    });
    mprisObject = new PlayerAdaptor(this, &backend, [this](std::function<void()> action) {
        return execute(std::move(action));
    }, [this] { return busy; });
    new RootAdaptor(mprisObject, &backend, [this] {
        show();
        raise();
        activateWindow();
    });
    connect(&backend, &Backend::changed, this, [this] {
        status->setText(backend.status == QLatin1String("Playing")      ? i18n("Playing")
                            : backend.status == QLatin1String("Paused") ? i18n("Paused")
                                                                        : i18n("Stopped"));
        play->setEnabled(backend.connected && backend.supports(QStringLiteral("AVTransport"), QStringLiteral("Play")));
        pause->setEnabled(backend.connected && backend.supports(QStringLiteral("AVTransport"), QStringLiteral("Pause")));
        stop->setEnabled(backend.connected && backend.supports(QStringLiteral("AVTransport"), QStringLiteral("Stop")));
        const bool seeking = backend.connected && backend.supports(QStringLiteral("AVTransport"), QStringLiteral("Seek"))
            && backend.supports(QStringLiteral("AVTransport"), QStringLiteral("GetPositionInfo"));
        back->setEnabled(seeking);
        forward->setEnabled(seeking);
        volume->setEnabled(backend.connected && backend.supports(QStringLiteral("RenderingControl"), QStringLiteral("SetVolume")));
        if (!volume->isSliderDown())
            volume->setValue(qRound(backend.volume * 100));
        brightnessRow->setVisible(backend.supports(QStringLiteral("RenderingControl"), QStringLiteral("SetBrightness")));
        send->setEnabled(backend.connected && !source.isEmpty());
    });
    auto timer = new QTimer(this);
    connect(timer, &QTimer::timeout, this, [this] {
        if (!busy && !mprisName.isEmpty())
            execute(
                [this] {
                    backend.poll();
                },
                false);
    });
    timer->start(2000);
    play->setEnabled(false);
    pause->setEnabled(false);
    stop->setEnabled(false);
    back->setEnabled(false);
    forward->setEnabled(false);
    volume->setEnabled(false);
    send->setEnabled(false);
    brightnessRow->hide();
}
QString Window::execute(std::function<void()> action, bool clearOnSuccess)
{
    if (busy)
        return i18n("A device request is still running. Try again shortly.");
    QScopedValueRollback<bool> guard(busy, true);
    try {
        action();
        if (clearOnSuccess)
            error->clear();
        return {};
    } catch (const std::exception &e) {
        const auto message = QString::fromUtf8(e.what());
        error->setText(message);
        return message;
    }
}
void Window::Open(const QString &target, const QString &url)
{
    openWhenReady(target, url, 200);
}
void Window::openWhenReady(const QString &target, const QString &url, int attempts)
{
    if (busy) {
        if (attempts > 0)
            QTimer::singleShot(50, this, [this, target, url, attempts] { openWhenReady(target, url, attempts - 1); });
        else {
            error->setText(i18n("A device request is still running. Try again shortly."));
            show();
        }
        return;
    }
    kind = target;
    source = QUrl(url);
    file->setText(source.isEmpty() ? i18n("Select a device to control it.") : source.toDisplayString(QUrl::PreferLocalFile));
    show();
    raise();
    activateWindow();
    execute([this] {
        refresh();
    });
}
void Window::refresh()
{
    auto bus = QDBusConnection::sessionBus();
    if (!mprisName.isEmpty()) {
        bus.unregisterService(mprisName);
        bus.unregisterObject(QStringLiteral("/org/mpris/MediaPlayer2"));
        mprisName.clear();
    }
    backend.clear();
    devices->clear();
    for (const auto &entry : backend.renderers()) {
        const auto renderer = entry.toObject();
        const auto name = renderer.value(QStringLiteral("name")).toString();
        const bool headset =
            name.contains(QStringLiteral("Flat Headset"), Qt::CaseInsensitive) || name.contains(QStringLiteral("StereoDroid"), Qt::CaseInsensitive);
        if ((kind == QLatin1String("headset") && !headset) || (kind == QLatin1String("tv") && headset))
            continue;
        if (!renderer.value(QStringLiteral("isActive")).toBool() || !renderer.value(QStringLiteral("isAllowed")).toBool())
            continue;
        devices->addItem(name, renderer);
    }
    if (devices->count() == 0)
        throw std::runtime_error(i18n("No matching device is available. Turn it on, allow it in UMS and refresh.").toUtf8().constData());
    // Selection is explicit; do not send a file just because discovery found a device.
    devices->setCurrentIndex(-1);
}
void Window::selected()
{
    auto bus = QDBusConnection::sessionBus();
    if (!mprisName.isEmpty()) {
        bus.unregisterService(mprisName);
        bus.unregisterObject(QStringLiteral("/org/mpris/MediaPlayer2"));
        mprisName.clear();
    }
    const auto failure = execute([this] {
        backend.select(devices->currentData().toJsonObject());
    });
    if (!failure.isEmpty())
        return;
    mprisName = QStringLiteral("org.mpris.MediaPlayer2.ums_renderer_")
        + QString::fromLatin1(QCryptographicHash::hash(backend.uuid.toUtf8(), QCryptographicHash::Sha256).toHex().left(16));
    if (!bus.registerService(mprisName)
        || !bus.registerObject(QStringLiteral("/org/mpris/MediaPlayer2"),
                               mprisObject,
                               QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllProperties | QDBusConnection::ExportAllSignals
                                   | QDBusConnection::ExportAdaptors)) {
        error->setText(i18n("Media controls could not connect to the session bus."));
        mprisName.clear();
    }
}

Window::~Window()
{
    if (!mprisName.isEmpty()) {
        auto bus = QDBusConnection::sessionBus();
        bus.unregisterService(mprisName);
        bus.unregisterObject(QStringLiteral("/org/mpris/MediaPlayer2"));
    }
}
