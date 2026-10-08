// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#include "dpms-server.h"
#include <QCoreApplication>
#include <QFile>
#include <QSocketNotifier>
#include <QStringList>
#include <cstdio>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <wayland-server.h>

struct Output
{
    QByteArray name;
    QList<wl_resource *> power;
    uint32_t mode = 0;
};

static void release(wl_client *, wl_resource *resource)
{
    wl_resource_destroy(resource);
}

static void ignoredSet(wl_client *, wl_resource *, uint32_t)
{
    qFatal("CEC observer must never request DPMS changes");
}

static const struct org_kde_kwin_dpms_interface powerImplementation = {ignoredSet, release};

static void getPower(wl_client *client, wl_resource *, uint32_t id, wl_resource *outputResource)
{
    auto output = static_cast<Output *>(wl_resource_get_user_data(outputResource));
    auto resource = wl_resource_create(client, &org_kde_kwin_dpms_interface, 1, id);
    wl_resource_set_implementation(resource, &powerImplementation, output, [](wl_resource *resource) {
        static_cast<Output *>(wl_resource_get_user_data(resource))->power.removeAll(resource);
    });
    output->power.append(resource);
    org_kde_kwin_dpms_send_supported(resource, 1);
    org_kde_kwin_dpms_send_mode(resource, output->mode);
    org_kde_kwin_dpms_send_done(resource);
}

static const struct org_kde_kwin_dpms_manager_interface managerImplementation = {getPower};

static void bindPower(wl_client *client, void *, uint32_t, uint32_t id)
{
    auto resource = wl_resource_create(client, &org_kde_kwin_dpms_manager_interface, 1, id);
    wl_resource_set_implementation(resource, &managerImplementation, nullptr, nullptr);
}

static const struct wl_output_interface outputImplementation = {release};

static void unexpectedSurface(wl_client *, wl_resource *, uint32_t)
{
    qFatal("CEC observer must not create a surface");
}

static void unexpectedShellSurface(wl_client *, wl_resource *, uint32_t, wl_resource *)
{
    qFatal("CEC observer must not create a shell surface");
}

static const struct wl_compositor_interface compositorImplementation = {unexpectedSurface, unexpectedSurface};
static const struct wl_shell_interface shellImplementation = {unexpectedShellSurface};

static void bindCompositor(wl_client *client, void *, uint32_t version, uint32_t id)
{
    auto resource = wl_resource_create(client, &wl_compositor_interface, qMin(version, 4U), id);
    wl_resource_set_implementation(resource, &compositorImplementation, nullptr, nullptr);
}

static void bindShell(wl_client *client, void *, uint32_t, uint32_t id)
{
    auto resource = wl_resource_create(client, &wl_shell_interface, 1, id);
    wl_resource_set_implementation(resource, &shellImplementation, nullptr, nullptr);
}

static void bindOutput(wl_client *client, void *data, uint32_t version, uint32_t id)
{
    auto output = static_cast<Output *>(data);
    auto resource = wl_resource_create(client, &wl_output_interface, qMin(version, 4U), id);
    wl_resource_set_implementation(resource, &outputImplementation, output, nullptr);
    wl_output_send_geometry(resource, 0, 0, 600, 340, WL_OUTPUT_SUBPIXEL_UNKNOWN, "Test", "Headless", WL_OUTPUT_TRANSFORM_NORMAL);
    wl_output_send_mode(resource, WL_OUTPUT_MODE_CURRENT | WL_OUTPUT_MODE_PREFERRED, 1920, 1080, 60000);
    if (version >= 2) {
        wl_output_send_scale(resource, 1);
    }
    if (version >= 4) {
        wl_output_send_name(resource, output->name.constData());
        wl_output_send_description(resource, output->name.constData());
    }
    if (version >= 2) {
        wl_output_send_done(resource);
    }
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    auto display = wl_display_create();
    if (wl_display_add_socket(display, "cec-test") < 0) {
        return 1;
    }
    wl_display_init_shm(display);
    wl_global_create(display, &wl_compositor_interface, 4, nullptr, bindCompositor);
    wl_global_create(display, &wl_shell_interface, 1, nullptr, bindShell);
    Output first{QByteArrayLiteral("HDMI-A-1")};
    Output second{QByteArrayLiteral("HDMI-A-2")};
    wl_global_create(display, &wl_output_interface, 4, &first, bindOutput);
    wl_global_create(display, &wl_output_interface, 4, &second, bindOutput);
    wl_global_create(display, &org_kde_kwin_dpms_manager_interface, 1, nullptr, bindPower);
    auto loop = wl_display_get_event_loop(display);
    QSocketNotifier wayland(wl_event_loop_get_fd(loop), QSocketNotifier::Read);
    QObject::connect(&wayland, &QSocketNotifier::activated, &app, [&] {
        wl_event_loop_dispatch(loop, 0);
        wl_display_flush_clients(display);
    });
    const auto fifoPath = QByteArray(argv[1]);
    if (mkfifo(fifoPath.constData(), 0600) < 0) {
        return 1;
    }
    const int fifo = open(fifoPath.constData(), O_RDWR | O_NONBLOCK | O_CLOEXEC);
    if (fifo < 0) {
        return 1;
    }
    QSocketNotifier control(fifo, QSocketNotifier::Read);
    QByteArray commands;
    QObject::connect(&control, &QSocketNotifier::activated, &app, [&] {
        char buffer[256];
        const auto size = read(fifo, buffer, sizeof(buffer));
        if (size > 0) {
            commands.append(buffer, size);
        }
        while (commands.contains('\n')) {
            const auto line = commands.first(commands.indexOf('\n'));
            commands.remove(0, commands.indexOf('\n') + 1);
            const auto words = line.split(' ');
            if (words.size() != 2) {
                continue;
            }
            auto output = words[0] == first.name ? &first : words[0] == second.name ? &second
                                                                                    : nullptr;
            if (!output) {
                continue;
            }
            output->mode = words[1] == "on" ? 0 : words[1] == "standby" ? 1
                : words[1] == "suspend"                                 ? 2
                                                                        : 3;
            for (auto resource : output->power) {
                org_kde_kwin_dpms_send_mode(resource, output->mode);
                org_kde_kwin_dpms_send_done(resource);
            }
        }
        wl_display_flush_clients(display);
    });
    return app.exec();
}
