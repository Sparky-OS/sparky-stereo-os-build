/* SPDX-License-Identifier: GPL-3.0-or-later */
/* SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com> */
// OBS's previews of a 3D canvas as 3D areas: the main preview, studio mode's program view, the projectors and every other
// display OBS draws (its OBSQTDisplay widgets) each have a surface of their own; on a 3D canvas that surface is declared
// full side by side, left eye first (libstereo-declare), and the display holds two views (obs_display_set_views()), so
// libobs draws each eye on its half and OBS's overlays (selection, handles, guides, safe areas) land in both eyes at the
// place of what they mark. The window around stays a 2D window. A display that cannot be shown in 3D (OBS on X11, a
// desktop without the stereo protocol, a refused declaration) shows the left eye whole, and the status bar says so.
#include "preview.hpp"

#include <QApplication>
#include <QEvent>
#include <QGuiApplication>
#include <QLabel>
#include <QMainWindow>
#include <QPointer>
#include <QStatusBar>
#include <QWidget>
#include <QWindow>

#include <obs-frontend-api.h>
#include <obs-module.h>
#include <obs-nix-platform.h>

#include <screenmode.h>
// last: it brings Xlib, whose macros (KeyPress, None, Bool) break Qt's headers included after it
#include <stereo-declare.h>

#include <map>

struct wl_display;
struct wl_surface;
extern "C" int wl_display_roundtrip(struct wl_display *display);

namespace SparkyStereo {

namespace {

QString text(const char *key)
{
	return QString::fromUtf8(obs_module_text(key));
}

enum class Shown { Nothing, InThreeD, Flat };

struct Area {
	QPointer<QWidget> widget;
	obs_display_t *display = nullptr;
	wl_surface *declared = nullptr;
	Shown shown = Shown::Nothing;
	QString why; // for a flat display of a 3D canvas
};

std::map<QWidget *, Area> areas;
QPointer<QLabel> statusLabel;
QPointer<Stereo::ScreenMode> previewScreenMode;
bool waylandReady = false;
bool waylandTried = false;
QString loggedWhy;

bool onWayland()
{
	return obs_get_nix_platform() == OBS_NIX_PLATFORM_WAYLAND;
}

// libstereo-declare on Qt's own Wayland connection, once; its global is read after one round trip.
bool initWayland()
{
	if (waylandTried)
		return waylandReady;
	waylandTried = true;
	auto *app = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>();
	wl_display *display = app ? app->display() : nullptr;
	if (!display || stereo_declare_wayland_init(display, nullptr) != 0)
		return false;
	wl_display_roundtrip(display);
	waylandReady = stereo_supported_wayland() != 0;
	return waylandReady;
}

void showStatus()
{
	QString why;
	for (const auto &[key, area] : areas)
		if (area.widget && area.shown == Shown::Flat && !area.why.isEmpty()) {
			why = area.why;
			break;
		}
	if (why.isEmpty() && previewScreenMode && obs_get_video_stereo3d(nullptr) == OBS_STEREO3D_SIDE_BY_SIDE) {
		const Stereo::OutputMode mode = previewScreenMode->mode();
		if (mode != Stereo::OutputMode::Stereo && mode != Stereo::OutputMode::Anaglyph &&
		    mode != Stereo::OutputMode::Unknown)
			why = text("Preview.Flat2DScreen");
	}
	if (why != loggedWhy) {
		if (!why.isEmpty())
			blog(LOG_INFO, "[sparky-stereo-obs] %s", why.toUtf8().constData());
		loggedWhy = why;
	}
	auto *main = static_cast<QMainWindow *>(obs_frontend_get_main_window());
	if (!main)
		return;
	if (!statusLabel) {
		statusLabel = new QLabel(main);
		statusLabel->setObjectName(QStringLiteral("sparkyStereoPreviewNote"));
		main->statusBar()->addPermanentWidget(statusLabel);
	}
	statusLabel->setText(why);
	statusLabel->setVisible(!why.isEmpty());
}

void undeclare(Area &area)
{
	if (area.display)
		obs_display_set_views(area.display, 1);
	if (area.declared) {
		stereo_remove_wayland(area.declared);
		area.declared = nullptr;
	}
}

void apply(QWidget *widget)
{
	auto it = areas.find(widget);
	if (it == areas.end())
		return;
	Area &area = it->second;
	auto *display = reinterpret_cast<obs_display_t *>(widget->property("obsDisplay").value<quintptr>());
	if (display != area.display) {
		area.display = display;
		area.declared = nullptr; // a new display has a new surface; the old one went with Qt's hidden window
	}
	const bool stereo = obs_get_video_stereo3d(nullptr) == OBS_STEREO3D_SIDE_BY_SIDE;
	area.why.clear();
	if (!display) {
		area.shown = Shown::Nothing;
	} else if (!stereo) {
		if (area.declared) {
			obs_display_set_enabled(display, false);
			undeclare(area);
			obs_display_set_enabled(display, true);
		}
		obs_display_set_views(display, 1);
		area.shown = Shown::Nothing;
	} else if (!onWayland()) {
		obs_display_set_views(display, 1);
		area.shown = Shown::Flat;
		area.why = text("Preview.FlatX11");
	} else if (!initWayland()) {
		obs_display_set_views(display, 1);
		area.shown = Shown::Flat;
		area.why = text("Preview.FlatNoDesktop");
	} else if (!area.declared) {
		auto *surface = widget->windowHandle() ? reinterpret_cast<wl_surface *>(widget->windowHandle()->winId())
						       : nullptr;
		// No frame of one view may be committed declared, nor one of two views undeclared: the display draws nothing
		// between the declaration and its two views.
		obs_display_set_enabled(display, false);
		const int rc = surface ? stereo_declare_wayland_format(surface, STEREO_SBS_FULL) : -1;
		if (rc == 0) {
			area.declared = surface;
			obs_display_set_views(display, 2);
			area.shown = Shown::InThreeD;
		} else {
			obs_display_set_views(display, 1);
			area.shown = Shown::Flat;
			area.why = text("Preview.FlatRefused").arg(rc);
			blog(LOG_WARNING, "[sparky-stereo-obs] the desktop refused the 3D area of %s: %d",
			     widget->objectName().toUtf8().constData(), rc);
		}
		obs_display_set_enabled(display, true);
	}
	if (area.shown == Shown::InThreeD)
		blog(LOG_INFO, "[sparky-stereo-obs] %s is a 3D area", widget->objectName().toUtf8().constData());
	showStatus();
}

class Watcher : public QObject {
public:
	using QObject::QObject;

protected:
	bool eventFilter(QObject *object, QEvent *event) override
	{
		auto *widget = qobject_cast<QWidget *>(object);
		if (!widget || !widget->inherits("OBSQTDisplay"))
			return false;
		if (event->type() == QEvent::Show || event->type() == QEvent::DynamicPropertyChange) {
			if (areas.find(widget) == areas.end()) {
				areas[widget].widget = widget;
				QObject::connect(widget, &QObject::destroyed, qApp, [widget] { areas.erase(widget); });
			}
			QMetaObject::invokeMethod(qApp, [widget] { apply(widget); }, Qt::QueuedConnection);
		} else if (event->type() == QEvent::Hide) {
			// Qt destroys a hidden native window's wl_surface: the declaration goes first
			auto it = areas.find(widget);
			if (it != areas.end() && it->second.declared) {
				undeclare(it->second);
				it->second.shown = Shown::Nothing;
			}
		}
		return false;
	}
};

QPointer<Watcher> watcher;

} // namespace

void watchPreviews()
{
	if (watcher)
		return;
	watcher = new Watcher(qApp);
	qApp->installEventFilter(watcher);
	for (QWidget *widget : QApplication::allWidgets())
		if (widget->inherits("OBSQTDisplay") && widget->isVisible()) {
			areas[widget].widget = widget;
			QObject::connect(widget, &QObject::destroyed, qApp, [widget] { areas.erase(widget); });
		}
	if (auto *main = static_cast<QWidget *>(obs_frontend_get_main_window())) {
		previewScreenMode = new Stereo::ScreenMode(qApp);
		auto follow = [main] {
			if (main->windowHandle())
				previewScreenMode->setScreen(main->windowHandle()->screen());
		};
		follow();
		if (main->windowHandle())
			QObject::connect(main->windowHandle(), &QWindow::screenChanged, qApp, follow);
		QObject::connect(previewScreenMode, &Stereo::ScreenMode::modeChanged, qApp, [] { showStatus(); });
	}
	updatePreviews();
}

void updatePreviews()
{
	for (auto &[widget, area] : areas)
		if (area.widget)
			apply(widget);
	showStatus();
}

} // namespace SparkyStereo
