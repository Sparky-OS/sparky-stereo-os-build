// A Qt window with a declared two-view child, hidden and shown again many times (row 830): OBS's preview without OBS.
//
// qt-declared-child-hideshow PACK CYCLES
//   The child is a native QWidget (WA_NativeWindow, WA_PaintOnScreen) as OBSQTDisplay is. Its "display", a heap block
//   with a mutex and the number of views as libobs's obs_display has, is made when the child's window is shown and
//   freed at its visibleChanged(false), when the property "display" goes to 0, as OBSQTDisplay does. A graphics thread
//   draws every display through an EGL display opened on Qt's own wl_display, as libobs does: a window surface on the
//   child's wl_surface, twice a view wide once the display holds two views (left view red, right view blue).
//   An application event filter does what OBS's stereo pack does: on a shown display it declares the child's surface
//   full side by side (libstereo-declare) and sets two views. PACK says how it takes them back:
//     old    on the widget's Hide event, after Qt dropped the surface and OBS freed the display: it sets one view on the
//            display it still holds (a write into freed memory) and withdraws the declaration (the pack before its
//            repair, sparky-stereo-obs at 78c8205c5);
//     late   the same moment, but the freed display is not touched: only the declaration is withdrawn, after the
//            surface it named was destroyed (the order a client may take with a declared two-view surface);
//     fixed  on the child window's own Hide event, before Qt drops the surface (the pack's repair, f1d231908).
//   CYCLES hide and show cycles of the child, 40 ms apart. Exit 0 with "DONE" when all ran.
#include <QApplication>
#include <QGuiApplication>
#include <QtGui/qguiapplication_platform.h>
#include <QMainWindow>
#include <QTimer>
#include <QVBoxLayout>
#include <QWidget>
#include <QWindow>
#include <QEvent>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GL/gl.h>
#include <wayland-client.h>
#include <wayland-egl.h>
#include <stereo-declare.h>
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <pthread.h>
#include <thread>
#include <vector>

namespace {

void require(bool ok, const char *what)
{
	if (!ok) {
		fprintf(stderr, "FAIL %s (egl 0x%x)\n", what, eglGetError());
		exit(1);
	}
}

// libobs's obs_display, reduced to what the stereo pack touches: a mutex, the views asked for, the swap chain.
struct Display {
	pthread_mutex_t draw_info_mutex;
	uint32_t views = 1, next_views = 1;
	bool enabled = true;
	bool interval_set = false;
	wl_surface *surface = nullptr;
	wl_egl_window *native = nullptr;
	EGLSurface egl = EGL_NO_SURFACE;
	int cx = 320, cy = 240;
	char padding[96]; // obs_display carries callbacks, colours and sizes after these
};

std::mutex graphics; // obs_enter_graphics()
std::vector<Display *> displays;
EGLDisplay eglDisplay = EGL_NO_DISPLAY;
EGLConfig eglConfig;
EGLContext eglContext = EGL_NO_CONTEXT;
std::atomic<bool> quitting{false};

void set_views(Display *d, uint32_t views) // obs_display_set_views()
{
	pthread_mutex_lock(&d->draw_info_mutex);
	d->next_views = views == 2 ? 2 : 1;
	pthread_mutex_unlock(&d->draw_info_mutex);
}

Display *create_display(wl_surface *surface, int cx, int cy) // obs_display_create() on the graphics thread's context
{
	std::lock_guard<std::mutex> lock(graphics);
	auto *d = new Display;
	pthread_mutex_init(&d->draw_info_mutex, nullptr);
	d->surface = surface;
	d->cx = cx;
	d->cy = cy;
	d->native = wl_egl_window_create(surface, cx, cy);
	require(d->native, "wl_egl_window");
	d->egl = eglCreateWindowSurface(eglDisplay, eglConfig, (EGLNativeWindowType)d->native, nullptr);
	require(d->egl != EGL_NO_SURFACE, "EGL window surface");
	displays.push_back(d);
	return d;
}

void destroy_display(Display *d) // obs_display_destroy()
{
	std::lock_guard<std::mutex> lock(graphics);
	for (auto it = displays.begin(); it != displays.end(); ++it)
		if (*it == d) {
			displays.erase(it);
			break;
		}
	eglMakeCurrent(eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
	require(eglDestroySurface(eglDisplay, d->egl), "destroy EGL surface");
	wl_egl_window_destroy(d->native);
	pthread_mutex_destroy(&d->draw_info_mutex);
	delete d;
}

void graphics_thread()
{
	for (int frame = 0; !quitting.load(); frame++) {
		{
			std::lock_guard<std::mutex> lock(graphics);
			for (Display *d : displays) {
				pthread_mutex_lock(&d->draw_info_mutex);
				const uint32_t views = d->next_views;
				const bool enabled = d->enabled;
				pthread_mutex_unlock(&d->draw_info_mutex);
				if (!enabled)
					continue;
				require(eglMakeCurrent(eglDisplay, d->egl, d->egl, eglContext), "make current");
				if (!d->interval_set) { // libobs draws its displays without waiting for the compositor's frame
					require(eglSwapInterval(eglDisplay, 0), "swap interval");
					d->interval_set = true;
				}
				if (views != d->views) {
					wl_egl_window_resize(d->native, d->cx * (int)views, d->cy, 0, 0);
					d->views = views;
				}
				const float g = (float)(frame % 32) / 64.0f;
				glViewport(0, 0, d->cx * (int)views, d->cy);
				glEnable(GL_SCISSOR_TEST);
				for (uint32_t v = 0; v < views; v++) {
					glScissor(d->cx * (int)v, 0, d->cx, d->cy);
					glClearColor(v ? 0.f : 1.f, g, v ? 1.f : 0.f, 1.f);
					glClear(GL_COLOR_BUFFER_BIT);
				}
				glDisable(GL_SCISSOR_TEST);
				require(eglSwapBuffers(eglDisplay, d->egl), "swap");
			}
			eglMakeCurrent(eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
		}
		std::this_thread::sleep_for(std::chrono::milliseconds(8));
	}
}

// OBSQTDisplay: a native child that makes its display when its window is shown and frees it when it is hidden.
class DisplayWidget : public QWidget {
public:
	explicit DisplayWidget(QWidget *parent) : QWidget(parent)
	{
		setAttribute(Qt::WA_PaintOnScreen);
		setAttribute(Qt::WA_StaticContents);
		setAttribute(Qt::WA_NoSystemBackground);
		setAttribute(Qt::WA_OpaquePaintEvent);
		setAttribute(Qt::WA_DontCreateNativeAncestors);
		setAttribute(Qt::WA_NativeWindow);
		setMinimumSize(320, 240);
		(void)winId(); // the native window exists from here, as OBSQTDisplay's does
		require(windowHandle() != nullptr, "native child window");
		connect(windowHandle(), &QWindow::visibleChanged, this, [this](bool visible) {
			if (!visible && display) {
				destroy_display(display);
				display = nullptr;
				setProperty("display", QVariant::fromValue<quintptr>(0));
			}
			if (visible && !display) {
				auto *surface = reinterpret_cast<wl_surface *>(windowHandle()->winId());
				require(surface != nullptr, "child wl_surface");
				display = create_display(surface, 320, 240);
				setProperty("display", QVariant::fromValue<quintptr>(reinterpret_cast<quintptr>(display)));
			}
		});
	}
	QPaintEngine *paintEngine() const override { return nullptr; }
	Display *display = nullptr;
};

enum class Pack { Old, Late, Fixed };
Pack pack;

struct Area {
	QWidget *widget = nullptr;
	Display *display = nullptr;
	wl_surface *declared = nullptr;
};
std::map<QWidget *, Area> areas;
int declarations = 0, withdrawals = 0, freedWrites = 0;

void undeclare(Area &area, bool touchDisplay)
{
	if (touchDisplay && area.display) {
		set_views(area.display, 1);
		if (pack == Pack::Old)
			freedWrites++;
	}
	if (area.declared) {
		stereo_remove_wayland(area.declared);
		area.declared = nullptr;
		withdrawals++;
	}
}

void apply(QWidget *widget)
{
	auto it = areas.find(widget);
	if (it == areas.end())
		return;
	Area &area = it->second;
	auto *display = reinterpret_cast<Display *>(widget->property("display").value<quintptr>());
	if (display != area.display) {
		area.display = display;
		area.declared = nullptr;
	}
	if (display && !area.declared) {
		auto *surface = reinterpret_cast<wl_surface *>(widget->windowHandle()->winId());
		pthread_mutex_lock(&display->draw_info_mutex);
		display->enabled = false;
		pthread_mutex_unlock(&display->draw_info_mutex);
		require(stereo_declare_wayland_format(surface, STEREO_SBS_FULL) == 0, "declare");
		declarations++;
		area.declared = surface;
		set_views(display, 2);
		pthread_mutex_lock(&display->draw_info_mutex);
		display->enabled = true;
		pthread_mutex_unlock(&display->draw_info_mutex);
	}
}

class Watcher : public QObject {
protected:
	bool eventFilter(QObject *object, QEvent *event) override
	{
		if (pack == Pack::Fixed && event->type() == QEvent::Hide && object->isWindowType()) {
			for (auto &[key, area] : areas)
				if (area.widget && area.declared && area.widget->windowHandle() == object)
					undeclare(area, true);
			return false;
		}
		auto *widget = dynamic_cast<DisplayWidget *>(object);
		if (!widget)
			return false;
		if (event->type() == QEvent::Show || event->type() == QEvent::DynamicPropertyChange) {
			areas[widget].widget = widget;
			if (pack == Pack::Fixed && event->type() == QEvent::DynamicPropertyChange) {
				Area &area = areas[widget];
				auto *now = reinterpret_cast<Display *>(widget->property("display").value<quintptr>());
				if (now != area.display) {
					if (area.declared)
						undeclare(area, false);
					area.display = now;
				}
			}
			QMetaObject::invokeMethod(qApp, [widget] { apply(widget); }, Qt::QueuedConnection);
		} else if (event->type() == QEvent::Hide && pack != Pack::Fixed) {
			auto it = areas.find(widget);
			if (it != areas.end() && it->second.declared)
				undeclare(it->second, pack == Pack::Old);
		}
		return false;
	}
};

} // namespace

int main(int argc, char **argv)
{
	setenv("QT_QPA_PLATFORM", "wayland", 1);
	QApplication app(argc, argv);
	require(argc == 3, "usage: qt-declared-child-hideshow old|late|fixed CYCLES");
	pack = !strcmp(argv[1], "old") ? Pack::Old : !strcmp(argv[1], "late") ? Pack::Late : Pack::Fixed;
	require(pack != Pack::Fixed || !strcmp(argv[1], "fixed"), "pack");
	const int cycles = atoi(argv[2]);
	require(cycles > 0, "cycles");

	auto *waylandApp = app.nativeInterface<QNativeInterface::QWaylandApplication>();
	require(waylandApp && waylandApp->display(), "Qt on Wayland");
	wl_display *wl = waylandApp->display();
	require(stereo_declare_wayland_init(wl, nullptr) == 0, "stereo_declare_wayland_init");
	eglDisplay = eglGetPlatformDisplay(EGL_PLATFORM_WAYLAND_KHR, wl, nullptr);
	require(eglDisplay != EGL_NO_DISPLAY && eglInitialize(eglDisplay, nullptr, nullptr), "EGL display");
	require(eglBindAPI(EGL_OPENGL_API), "OpenGL API");
	const EGLint attrs[] = {EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8,
				EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT, EGL_NONE};
	EGLint count = 0;
	require(eglChooseConfig(eglDisplay, attrs, &eglConfig, 1, &count) && count == 1, "config");
	eglContext = eglCreateContext(eglDisplay, eglConfig, EGL_NO_CONTEXT, nullptr);
	require(eglContext != EGL_NO_CONTEXT, "context");
	require(eglMakeCurrent(eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, eglContext), "surfaceless current");
	printf("GL_RENDERER %s\nPACK %s cycles=%d\n", glGetString(GL_RENDERER), argv[1], cycles);
	eglMakeCurrent(eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);

	app.installEventFilter(new Watcher);
	QMainWindow window;
	auto *central = new QWidget(&window);
	auto *layout = new QVBoxLayout(central);
	auto *child = new DisplayWidget(central);
	layout->addWidget(child);
	window.setCentralWidget(central);
	window.resize(800, 600);
	window.show();
	std::thread thread(graphics_thread);

	int done = 0;
	QTimer timer;
	QObject::connect(&timer, &QTimer::timeout, [&] {
		if (child->isVisible()) {
			child->hide();
			return;
		}
		child->show();
		// a program's own allocations between cycles, of many sizes, so that glibc walks its chunks
		std::vector<void *> blocks;
		for (int i = 0; i < 512; i++)
			blocks.push_back(realloc(malloc(16 + (i * 37) % 600), 32 + (i * 53) % 900));
		for (void *b : blocks)
			free(b);
		printf("CYCLE %d done\n", ++done);
		fflush(stdout);
		if (done == cycles) {
			timer.stop();
			QTimer::singleShot(200, &app, [&] { app.quit(); });
		}
	});
	QTimer::singleShot(500, &app, [&] { timer.start(40); });
	const int rc = app.exec();
	quitting = true;
	thread.join();
	printf("DONE cycles=%d declarations=%d withdrawals=%d freed-writes=%d rc=%d\n", done, declarations, withdrawals,
	       freedWrites, rc);
	return rc;
}
