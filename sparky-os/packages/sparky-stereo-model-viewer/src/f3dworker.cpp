// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#include "f3dworker.h"

#include <f3d/camera.h>
#include <f3d/engine.h>
#include <f3d/interactor.h>
#include <f3d/log.h>
#include <f3d/options.h>
#include <f3d/scene.h>
#include <f3d/window.h>

#include <QByteArray>
#include <QMutexLocker>
#include <QtGlobal>

#include <X11/Xatom.h>
#include <X11/Xlib.h>

#include <algorithm>
#include <filesystem>

void F3DWorker::post(const Command &command)
{
    {
        QMutexLocker lock(&m_mutex);
        m_commands.push_back(command);
    }
}

namespace
{
// The size one view is shown at, in display pixels: Stereo KWin reads it from the child (declaration support 6 and later),
// so a 3D area rendered at another resolution than its place is scaled once, at the output
void declareShownSize(Display *display, unsigned long window, const QSize &shown)
{
    if (!display || !window) {
        return;
    }
    const unsigned long size[2] = {static_cast<unsigned long>(shown.width()), static_cast<unsigned long>(shown.height())};
    XChangeProperty(display, window, XInternAtom(display, "_KDE_NET_WM_STEREO_CONTENT_ONE_VIEW_SIZE", False), XA_CARDINAL, 32, PropModeReplace,
                    reinterpret_cast<const unsigned char *>(size), 2);
    XFlush(display);
}
}

// A file dropped over the 3D area goes to the program's window like a file dropped anywhere else: libf3d's own window would add
// the file to the scene without the program knowing (no title, no recent files, no said failure). XDND (version 5): the child is
// not a drop target and names its window as its proxy; the proxy names itself (the drag source checks both).
static void dropsGoToTheWindow(Display *display, unsigned long child, unsigned long parent)
{
    if (!display || !child || !parent) {
        return;
    }
    const Atom aware = XInternAtom(display, "XdndAware", False);
    const Atom proxy = XInternAtom(display, "XdndProxy", False);
    XDeleteProperty(display, child, aware);
    XChangeProperty(display, child, proxy, XA_WINDOW, 32, PropModeReplace, reinterpret_cast<const unsigned char *>(&parent), 1);
    XChangeProperty(display, parent, proxy, XA_WINDOW, 32, PropModeReplace, reinterpret_cast<const unsigned char *>(&parent), 1);
    XFlush(display);
}

void F3DWorker::run()
{
    f3d::log::setVerboseLevel(qEnvironmentVariableIsSet("STEREO_MODEL_VIEWER_LOG") ? f3d::log::VerboseLevel::DEBUG : f3d::log::VerboseLevel::WARN);
    f3d::engine::autoloadPlugins();
    f3d::engine engine = f3d::engine::createGLX();
    f3d::window &window = engine.getWindow();
    f3d::scene &scene = engine.getScene();
    f3d::interactor &interactor = engine.getInteractor();
    f3d::options &options = engine.getOptions();
    Display *display = XOpenDisplay(nullptr);

    options.set("render.stereo", true);
    options.set("ui.filename", false);
    options.set("ui.fps", false);

    bool quit = false;
    bool attached = false;
    bool stereo = true;
    bool announcedNative = false;
    bool noStereoSaid = false;
    int lastState = -1;
    double lastSunk = -1;
    double lastPopped = -1;
    bool wasPlaying = false;
    QRect lastRect;
    int rerender = 0;
    int lastPercent = 0;

    Command lastPlace;
    auto place = [&](const Command &c) {
        if (!c.parent) {
            return;
        }
        lastPlace = c;
        if (!attached) {
            window.setParentWindowId(static_cast<unsigned long>(c.parent));
            attached = true;
        }
        const int percent = c.percent > 0 ? c.percent : 100;
        if (attached && c.rect == lastRect && percent == lastPercent) {
            return;
        }
        lastPercent = percent;
        const int width = std::max(16, c.rect.width() * percent / 100);
        const int height = std::max(16, c.rect.height() * percent / 100);
        window.setPosition(c.rect.x(), c.rect.y());
        // a declared stereo child is one eye wide (declaration version 4): the X window is the eye's size
        window.setSize(width, height);
        lastRect = c.rect;
        if (const quint64 native = window.getNativeWindowId()) {
            declareShownSize(display, native, c.rect.size());
        }
        // libf3d draws only when asked: draw again after a resize
        rerender = 6;
        interactor.requestRender();
    };

    auto handle = [&](const Command &c) {
        switch (c.kind) {
        case Command::Place:
            place(c);
            break;
        case Command::Load: {
            const std::filesystem::path path(c.path.toStdString());
            try {
                if (!scene.supports(path)) {
                    Q_EMIT loadFailed(c.path, QStringLiteral("no reader"));
                    break;
                }
                scene.clear();
                scene.add(path);
                window.getCamera().resetToBounds();
                Q_EMIT loaded(c.path, scene.availableAnimations() > 0);
            } catch (const std::exception &e) {
                Q_EMIT loadFailed(c.path, QString::fromUtf8(e.what()));
            }
            interactor.requestRender();
            break;
        }
        case Command::Reset:
            window.getCamera().resetToBounds();
            interactor.requestRender();
            break;
        case Command::TogglePlay:
            interactor.toggleAnimation();
            if (qEnvironmentVariableIsSet("STEREO_MODEL_VIEWER_LOG")) {
                qWarning("toggle animation: playing %d", interactor.isPlayingAnimation() ? 1 : 0);
            }
            break;
        case Command::Stereo:
            stereo = c.flag;
            options.set("render.stereo", stereo);
            interactor.requestRender();
            break;
        case Command::Quit:
            quit = true;
            interactor.requestStop();
            break;
        }
    };

    auto drain = [&]() {
        for (;;) {
            Command command;
            {
                QMutexLocker lock(&m_mutex);
                if (m_commands.empty()) {
                    break;
                }
                command = m_commands.front();
                m_commands.pop_front();
            }
            handle(command);
        }
    };

    auto tick = [&]() {
        drain();
        if (rerender > 0) {
            // libf3d draws only when asked: draw again after a resize
            --rerender;
            interactor.requestRender();
        }
        if (!announcedNative) {
            if (const quint64 native = window.getNativeWindowId()) {
                announcedNative = true;
                m_native = native;
                dropsGoToTheWindow(display, native, lastPlace.parent);
                if (lastRect.isValid()) {
                    declareShownSize(display, native, lastRect.size());
                }
            }
        }
        if (announcedNative && stereo && !noStereoSaid && !window.isStereo()) {
            noStereoSaid = true;
            Q_EMIT stereoFailed();
        }
        bool changed = false;
        const auto state = window.pollStereoDepth(changed);
        if (changed || lastState < 0) {
            int code = 0;
            switch (state) {
            case f3d::window::stereo_depth_state::UNUSED:
                code = 0;
                break;
            case f3d::window::stereo_depth_state::DELIVERED:
                code = 1;
                break;
            case f3d::window::stereo_depth_state::NOT_OFFERED:
                code = 2;
                break;
            case f3d::window::stereo_depth_state::NOT_DELIVERED:
                code = 3;
                break;
            default:
                code = 4;
                break;
            }
            if (code != lastState) {
                lastState = code;
                if (qEnvironmentVariableIsSet("STEREO_MODEL_VIEWER_LOG")) {
                    qWarning("depth state %d", code);
                }
                Q_EMIT depthState(code, lastSunk, lastPopped);
            }
        }
        const bool playing = interactor.isPlayingAnimation();
        if (playing != wasPlaying) {
            wasPlaying = playing;
            Q_EMIT playingChanged(playing);
        }
    };

    // Nothing is created before the program's own window says where the 3D area is: the first Place command comes first
    // (a file asked for earlier waits for the loop)
    while (!quit && !attached) {
        drain();
        if (!attached) {
            msleep(20);
        }
    }
    // F3D's own key bindings can stop the loop (Escape): the viewer's life is the program's, not the loop's
    while (!quit) {
        interactor.start(1.0 / 30.0, tick);
    }
    if (display) {
        XCloseDisplay(display);
    }
}
