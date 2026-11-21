/* SPDX-License-Identifier: GPL-3.0-or-later */
/* SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com> */
// Sparky Stereo OS's module for OBS Studio. A program's 3D options are only: enable 3D, the render resolution per eye
// and a shortcut to Display Settings (the edition's contract). Here "Enable 3D" makes the canvas full side by side, left
// eye first, each eye at the chosen resolution; the encoders that can write the frame packing message do while they
// encode, and the person is told before a start what will go unmarked and why. Off, the canvas the person had returns.
#include "layer-words.hpp"
#include "marks.hpp"

#include <obs-frontend-api.h>
#include <obs-module.h>
#include <util/config-file.h>
#include <util/platform.h>

#include <screenmode.h>

#include <QCheckBox>
#include <QCoreApplication>
#include <QDialog>
#include <QDialogButtonBox>
#include <QFormLayout>
#include <QGuiApplication>
#include <QScreen>
#include <QTimer>
#include <QHBoxLayout>
#include <QLabel>
#include <QMainWindow>
#include <QMessageBox>
#include <QPointer>
#include <QProcess>
#include <QPushButton>
#include <QSet>
#include <QSpinBox>
#include <QVBoxLayout>

OBS_DECLARE_MODULE()
OBS_MODULE_USE_DEFAULT_LOCALE("sparky-stereo-obs", "en-US")

extern struct obs_source_info sparky_stereo_input_info;

MODULE_EXPORT const char *obs_module_name(void)
{
	return "Sparky Stereo";
}

MODULE_EXPORT const char *obs_module_description(void)
{
	return obs_module_text("Description");
}

namespace SparkyStereo {

namespace {

// Daniel, 2026-10-01: "Default 1920x1080 per eye for 3D TVs" (the render resolution, a program's one stereo setting)
constexpr uint32_t kDefaultEyeWidth = 1920;
constexpr uint32_t kDefaultEyeHeight = 1080;

struct State {
	bool enabled = false;
	uint32_t eyeWidth = kDefaultEyeWidth;
	uint32_t eyeHeight = kDefaultEyeHeight;
	// the canvas the person had before 3D, given back when 3D goes off
	uint32_t baseWidth = 0, baseHeight = 0, outputWidth = 0, outputHeight = 0;
	// the person's own choice in the dialog: "" none yet, "on", "off"; kept over the default from then on
	QString choice;
	// 3D set by the default (3D active on the desktop), not by the person
	bool automatic = false;
	// told once that 3D is active and this profile's scenes kept their canvas
	bool toldScenes = false;
};

State state;
QString profileName;
QSet<QString> toldThisSession;

QString text(const char *key)
{
	return QString::fromUtf8(obs_module_text(key));
}

// The module's state is its own, per profile (the canvas belongs to the profile): never written into OBS's files
// other than the canvas size the person asked for.
QString statePath()
{
	char *path = obs_module_config_path("profiles.json");
	QString result = QString::fromUtf8(path);
	bfree(path);
	return result;
}

void loadState()
{
	char *name = obs_frontend_get_current_profile();
	profileName = QString::fromUtf8(name ? name : "");
	bfree(name);
	state = State();
	obs_data_t *all = obs_data_create_from_json_file_safe(statePath().toUtf8().constData(), "bak");
	if (!all)
		return;
	obs_data_t *profiles = obs_data_get_obj(all, "profiles");
	obs_data_t *mine = profiles ? obs_data_get_obj(profiles, profileName.toUtf8().constData()) : nullptr;
	if (mine) {
		state.enabled = obs_data_get_bool(mine, "enabled");
		state.eyeWidth = (uint32_t)obs_data_get_int(mine, "eye_width");
		state.eyeHeight = (uint32_t)obs_data_get_int(mine, "eye_height");
		state.baseWidth = (uint32_t)obs_data_get_int(mine, "base_width");
		state.baseHeight = (uint32_t)obs_data_get_int(mine, "base_height");
		state.outputWidth = (uint32_t)obs_data_get_int(mine, "output_width");
		state.outputHeight = (uint32_t)obs_data_get_int(mine, "output_height");
		state.choice = QString::fromUtf8(obs_data_get_string(mine, "choice"));
		state.automatic = obs_data_get_bool(mine, "automatic");
		state.toldScenes = obs_data_get_bool(mine, "told_scenes");
		if (!state.eyeWidth || !state.eyeHeight) {
			state.eyeWidth = kDefaultEyeWidth;
			state.eyeHeight = kDefaultEyeHeight;
		}
	}
	obs_data_release(mine);
	obs_data_release(profiles);
	obs_data_release(all);
}

bool saveState()
{
	char *folder = obs_module_config_path("");
	os_mkdirs(folder);
	bfree(folder);
	const QByteArray path = statePath().toUtf8();
	obs_data_t *all = obs_data_create_from_json_file_safe(path.constData(), "bak");
	if (!all)
		all = obs_data_create();
	obs_data_t *profiles = obs_data_get_obj(all, "profiles");
	if (!profiles)
		profiles = obs_data_create();
	obs_data_t *mine = obs_data_create();
	obs_data_set_bool(mine, "enabled", state.enabled);
	obs_data_set_int(mine, "eye_width", state.eyeWidth);
	obs_data_set_int(mine, "eye_height", state.eyeHeight);
	obs_data_set_int(mine, "base_width", state.baseWidth);
	obs_data_set_int(mine, "base_height", state.baseHeight);
	obs_data_set_int(mine, "output_width", state.outputWidth);
	obs_data_set_int(mine, "output_height", state.outputHeight);
	obs_data_set_string(mine, "choice", state.choice.toUtf8().constData());
	obs_data_set_bool(mine, "automatic", state.automatic);
	obs_data_set_bool(mine, "told_scenes", state.toldScenes);
	obs_data_set_obj(profiles, profileName.toUtf8().constData(), mine);
	obs_data_set_obj(all, "profiles", profiles);
	const bool saved = obs_data_save_json_safe(all, path.constData(), "tmp", "bak");
	obs_data_release(mine);
	obs_data_release(profiles);
	obs_data_release(all);
	if (!saved)
		blog(LOG_ERROR, "[sparky-stereo-obs] could not write %s", path.constData());
	return saved;
}

// The canvas is stereo while 3D is on and the base resolution is still two eyes side by side: a canvas the person
// resized in Settings, Video is told, never marked as something it may not be.
bool canvasIsStereo(QString *why = nullptr)
{
	if (!state.enabled)
		return false;
	struct obs_video_info video = {};
	if (!obs_get_video_info(&video))
		return false;
	if (video.base_width != 2 * state.eyeWidth || video.base_height != state.eyeHeight) {
		if (why)
			*why = text("Notice.CanvasChanged")
				       .arg(video.base_width)
				       .arg(video.base_height)
				       .arg(2 * state.eyeWidth)
				       .arg(state.eyeHeight);
		return false;
	}
	return true;
}

QMainWindow *mainWindow()
{
	return static_cast<QMainWindow *>(obs_frontend_get_main_window());
}

bool outputsBusy()
{
	return obs_frontend_streaming_active() || obs_frontend_recording_active() ||
	       obs_frontend_replay_buffer_active() || obs_frontend_virtualcam_active();
}

// Sets the canvas (Settings, Video: base and output resolution) and resets OBS's video. Returns false and says why when
// it cannot.
bool applyCanvas(bool enable, uint32_t eyeWidth, uint32_t eyeHeight, QWidget *parent)
{
	if (outputsBusy()) {
		QMessageBox::warning(parent, text("DialogTitle"), text("Notice.OutputsBusy"));
		return false;
	}
	config_t *config = obs_frontend_get_profile_config();
	if (enable) {
		if (!state.enabled) {
			state.baseWidth = (uint32_t)config_get_uint(config, "Video", "BaseCX");
			state.baseHeight = (uint32_t)config_get_uint(config, "Video", "BaseCY");
			state.outputWidth = (uint32_t)config_get_uint(config, "Video", "OutputCX");
			state.outputHeight = (uint32_t)config_get_uint(config, "Video", "OutputCY");
		}
		config_set_uint(config, "Video", "BaseCX", 2 * eyeWidth);
		config_set_uint(config, "Video", "BaseCY", eyeHeight);
		config_set_uint(config, "Video", "OutputCX", 2 * eyeWidth);
		config_set_uint(config, "Video", "OutputCY", eyeHeight);
	} else if (state.enabled && state.baseWidth && state.baseHeight) {
		config_set_uint(config, "Video", "BaseCX", state.baseWidth);
		config_set_uint(config, "Video", "BaseCY", state.baseHeight);
		config_set_uint(config, "Video", "OutputCX", state.outputWidth ? state.outputWidth : state.baseWidth);
		config_set_uint(config, "Video", "OutputCY", state.outputHeight ? state.outputHeight : state.baseHeight);
	}
	if (config_save_safe(config, "tmp", nullptr) != 0)
		blog(LOG_ERROR, "[sparky-stereo-obs] the profile's video settings could not be saved");
	obs_frontend_reset_video();
	state.enabled = enable;
	state.eyeWidth = eyeWidth;
	state.eyeHeight = eyeHeight;
	saveState();
	struct obs_video_info video = {};
	if (enable && (!obs_get_video_info(&video) || video.base_width != 2 * eyeWidth || video.base_height != eyeHeight)) {
		QMessageBox::warning(parent, text("DialogTitle"),
				     text("Notice.CanvasNotSet").arg(2 * eyeWidth).arg(eyeHeight));
		return false;
	}
	blog(LOG_INFO, "[sparky-stereo-obs] 3D %s, canvas %ux%u", enable ? "on" : "off", video.base_width,
	     video.base_height);
	setCanvasLayout(enable);
	return true;
}

QString planText(OutputKind kind, const QString &title)
{
	const MarkPlan plan = planFor(kind);
	QStringList lines;
	lines << QStringLiteral("<b>%1</b>").arg(title.toHtmlEscaped());
	if (plan.streamMarked)
		lines << text("Status.Marked").toHtmlEscaped();
	for (const QString &sentence : plan.missing)
		lines << sentence.toHtmlEscaped();
	return lines.join(QStringLiteral("<br>"));
}

void openDisplaySettings(QWidget *parent)
{
	// the shortcut every program of the edition offers: Display Configuration, where the outputs and their 3D modes live
	if (!QProcess::startDetached(QStringLiteral("kcmshell6"), {QStringLiteral("kcm_kscreen")}))
		QMessageBox::warning(parent, text("DialogTitle"), text("Notice.DisplaySettingsFailed"));
}

void showDialog()
{
	QWidget *parent = mainWindow();
	QDialog dialog(parent);
	dialog.setWindowTitle(text("DialogTitle"));
	auto *layout = new QVBoxLayout(&dialog);

	auto *enable = new QCheckBox(layerWord("Enable 3D"), &dialog);
	enable->setChecked(state.enabled);
	layout->addWidget(enable);

	auto *form = new QFormLayout;
	auto *size = new QHBoxLayout;
	auto *width = new QSpinBox(&dialog);
	auto *height = new QSpinBox(&dialog);
	for (QSpinBox *box : {width, height}) {
		box->setRange(16, 8192);
		box->setSuffix(QStringLiteral(" px"));
	}
	width->setValue((int)state.eyeWidth);
	height->setValue((int)state.eyeHeight);
	size->addWidget(width);
	size->addWidget(new QLabel(QStringLiteral("×"), &dialog));
	size->addWidget(height);
	form->addRow(text("EyeResolution"), size);
	layout->addLayout(form);

	auto *canvas = new QLabel(&dialog);
	auto updateCanvas = [&] {
		canvas->setText(text("CanvasWillBe").arg(2 * width->value()).arg(height->value()));
	};
	updateCanvas();
	QObject::connect(width, &QSpinBox::valueChanged, &dialog, updateCanvas);
	QObject::connect(height, &QSpinBox::valueChanged, &dialog, updateCanvas);
	layout->addWidget(canvas);

	auto *status = new QLabel(&dialog);
	status->setWordWrap(true);
	status->setTextFormat(Qt::RichText);
	status->setText(planText(OutputKind::Record, text("Status.Recording")) + QStringLiteral("<br><br>") +
			planText(OutputKind::Stream, text("Status.Streaming")));
	layout->addWidget(status);

	auto *buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, &dialog);
	QPushButton *display = buttons->addButton(layerWord("Display Settings…"), QDialogButtonBox::ActionRole);
	QObject::connect(display, &QPushButton::clicked, &dialog, [&] { openDisplaySettings(&dialog); });
	QObject::connect(buttons, &QDialogButtonBox::accepted, &dialog, &QDialog::accept);
	QObject::connect(buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);
	layout->addWidget(buttons);

	if (dialog.exec() != QDialog::Accepted)
		return;
	const bool on = enable->isChecked();
	const uint32_t w = (uint32_t)width->value(), h = (uint32_t)height->value();
	if (on == state.enabled && (!on || (w == state.eyeWidth && h == state.eyeHeight))) {
		// the person confirmed what the default chose: from now on it is their choice
		if (state.choice != (on ? QStringLiteral("on") : QStringLiteral("off"))) {
			state.choice = on ? QStringLiteral("on") : QStringLiteral("off");
			state.automatic = false;
			saveState();
		}
		return;
	}
	if (applyCanvas(on, w, h, parent)) {
		state.choice = on ? QStringLiteral("on") : QStringLiteral("off");
		state.automatic = false;
		saveState();
	}
}

// Whether 3D is active on the desktop: any screen in a 3D mode or an anaglyph mode, read by the stereo layer's
// Stereo::ScreenMode as Spectacle reads it (ImagePlatformKWin::updateStereoOutputs()). A 2D screen copied to a 3D target
// counts through the target, which is a screen of its own.
std::vector<QPointer<Stereo::ScreenMode>> screenModes;
bool defaultPending = false;

void evaluateDefault(bool timedOut);

void watchScreens()
{
	for (QScreen *screen : qGuiApp->screens()) {
		bool known = false;
		for (const auto &mode : screenModes)
			known = known || (mode && mode->screen() == screen);
		if (known)
			continue;
		auto *mode = new Stereo::ScreenMode(qApp);
		mode->setScreen(screen);
		QObject::connect(mode, &Stereo::ScreenMode::modeChanged, qApp, [] { evaluateDefault(false); });
		screenModes.emplace_back(mode);
	}
}

bool desktopIn3D(bool *settled)
{
	bool active = false;
	*settled = true;
	for (const auto &mode : screenModes) {
		if (!mode)
			continue;
		switch (mode->mode()) {
		case Stereo::OutputMode::Stereo:
		case Stereo::OutputMode::Anaglyph:
			active = true;
			break;
		case Stereo::OutputMode::Unknown:
			*settled = false;
			break;
		default:
			break;
		}
	}
	return active;
}

// A scene collection with no item in any scene: a fresh profile, whose canvas the default may set.
bool collectionEmpty()
{
	struct obs_frontend_source_list scenes = {};
	obs_frontend_get_scenes(&scenes);
	bool empty = true;
	for (size_t i = 0; i < scenes.sources.num && empty; i++) {
		obs_scene_t *scene = obs_scene_from_source(scenes.sources.array[i]);
		if (scene)
			obs_scene_enum_items(
				scene,
				[](obs_scene_t *, obs_sceneitem_t *, void *param) {
					*static_cast<bool *>(param) = false;
					return false;
				},
				&empty);
	}
	obs_frontend_source_list_free(&scenes);
	return empty;
}

void offerEnable()
{
	blog(LOG_INFO, "[sparky-stereo-obs] %s", text("Notice.ScenesExist").arg(2 * state.eyeWidth).arg(state.eyeHeight).toUtf8().constData());
	auto *box = new QMessageBox(QMessageBox::Information, text("DialogTitle"),
				    text("Notice.ScenesExist").arg(2 * state.eyeWidth).arg(state.eyeHeight), QMessageBox::Close,
				    mainWindow());
	QPushButton *enable = box->addButton(layerWord("Enable 3D"), QMessageBox::AcceptRole);
	box->setAttribute(Qt::WA_DeleteOnClose);
	box->setModal(false);
	QObject::connect(enable, &QPushButton::clicked, box, [] {
		if (applyCanvas(true, state.eyeWidth, state.eyeHeight, mainWindow())) {
			state.choice = QStringLiteral("on");
			state.automatic = false;
			saveState();
		}
	});
	box->show();
}

// Daniel, 2026-11-19, for the edition's capture programs: "the default mode is 3D when 3D is active"; "in 2d only, the
// default is also a 2D picture". Decided once per start (and per profile change), never over the person's own choice,
// and never resizing a canvas that already holds the person's scenes: that is told once, with the action.
void evaluateDefault(bool timedOut)
{
	if (!defaultPending)
		return;
	bool settled = false;
	const bool in3D = desktopIn3D(&settled);
	if (!settled && !timedOut)
		return;
	defaultPending = false;
	for (const auto &mode : screenModes) {
		if (mode)
			blog(LOG_INFO, "[sparky-stereo-obs] screen %s: %s",
			     mode->screen() ? mode->screen()->name().toUtf8().constData() : "?",
			     mode->mode() == Stereo::OutputMode::Stereo     ? "3D"
			     : mode->mode() == Stereo::OutputMode::Anaglyph ? "anaglyph"
			     : mode->mode() == Stereo::OutputMode::Mono     ? "2D"
									    : "not read");
	}
	if (!settled) {
		tell(text("Notice.ModeUnknown"));
		return;
	}
	blog(LOG_INFO, "[sparky-stereo-obs] the desktop is in %s; the person's choice: %s", in3D ? "3D" : "2D",
	     state.choice.isEmpty() ? "none yet" : state.choice.toUtf8().constData());
	if (!state.choice.isEmpty())
		return;
	const bool empty = collectionEmpty();
	if (in3D && !state.enabled) {
		if (empty) {
			if (applyCanvas(true, state.eyeWidth, state.eyeHeight, mainWindow())) {
				state.automatic = true;
				saveState();
				blog(LOG_INFO, "[sparky-stereo-obs] 3D is active on the desktop: 3D on for this new profile");
			}
		} else if (!state.toldScenes) {
			state.toldScenes = true;
			saveState();
			offerEnable();
		}
	} else if (!in3D && state.enabled && state.automatic && empty) {
		if (applyCanvas(false, state.eyeWidth, state.eyeHeight, mainWindow())) {
			state.automatic = false;
			saveState();
			blog(LOG_INFO, "[sparky-stereo-obs] the desktop is in 2D: the canvas the profile had is back");
		}
	}
}

void startDefault()
{
	watchScreens();
	defaultPending = true;
	QTimer::singleShot(5000, qApp, [] { evaluateDefault(true); });
	evaluateDefault(false);
}

OutputKind kindOf(enum obs_frontend_event event)
{
	switch (event) {
	case OBS_FRONTEND_EVENT_STREAMING_STARTING:
	case OBS_FRONTEND_EVENT_STREAMING_STOPPED:
		return OutputKind::Stream;
	case OBS_FRONTEND_EVENT_REPLAY_BUFFER_STARTING:
	case OBS_FRONTEND_EVENT_REPLAY_BUFFER_STOPPED:
		return OutputKind::Replay;
	default:
		return OutputKind::Record;
	}
}

void starting(OutputKind kind)
{
	QString why;
	const bool stereo = canvasIsStereo(&why);
	if (state.enabled && !stereo && !why.isEmpty())
		tell(why);
	setCanvasLayout(stereo);
	if (!stereo)
		return; // a 2D canvas: the layout is 2D, nothing is read
	struct obs_video_info video = {};
	if (obs_get_video_info(&video) &&
	    (uint64_t)video.output_width * video.base_height != (uint64_t)video.output_height * video.base_width)
		tell(text("Notice.Squeezed").arg(video.output_width).arg(video.output_height));
	const MarkPlan plan = planFor(kind);
	for (const QString &sentence : plan.missing)
		tell(sentence);
	watchOutput(kind);
}

void onEvent(enum obs_frontend_event event, void *)
{
	switch (event) {
	case OBS_FRONTEND_EVENT_FINISHED_LOADING:
	case OBS_FRONTEND_EVENT_PROFILE_CHANGED:
		loadState();
		setCanvasLayout(canvasIsStereo());
		startDefault();
		break;
	case OBS_FRONTEND_EVENT_STREAMING_STARTING:
	case OBS_FRONTEND_EVENT_RECORDING_STARTING:
	case OBS_FRONTEND_EVENT_REPLAY_BUFFER_STARTING:
		starting(kindOf(event));
		break;
	case OBS_FRONTEND_EVENT_STREAMING_STOPPED:
	case OBS_FRONTEND_EVENT_RECORDING_STOPPED:
	case OBS_FRONTEND_EVENT_REPLAY_BUFFER_STOPPED:
		unwatchOutput(kindOf(event));
		break;
	case OBS_FRONTEND_EVENT_EXIT:
		for (OutputKind kind : {OutputKind::Stream, OutputKind::Record, OutputKind::Replay})
			unwatchOutput(kind);
		break;
	default:
		break;
	}
}

} // namespace

void tell(const QString &sentence)
{
	blog(LOG_WARNING, "[sparky-stereo-obs] %s", sentence.toUtf8().constData());
	// the window: once a session for each sentence, without stopping the start it is about
	QMetaObject::invokeMethod(
		qApp,
		[sentence] {
			if (toldThisSession.contains(sentence))
				return;
			toldThisSession.insert(sentence);
			auto *box = new QMessageBox(QMessageBox::Information, text("DialogTitle"), sentence, QMessageBox::Ok,
						    mainWindow());
			box->setAttribute(Qt::WA_DeleteOnClose);
			box->setModal(false);
			box->show();
		},
		Qt::QueuedConnection);
}

} // namespace SparkyStereo

bool obs_module_load(void)
{
	obs_register_source(&sparky_stereo_input_info);
	obs_frontend_add_event_callback(SparkyStereo::onEvent, nullptr);
	obs_frontend_add_tools_menu_item(obs_module_text("Menu"), [](void *) { SparkyStereo::showDialog(); }, nullptr);
	blog(LOG_INFO, "[sparky-stereo-obs] loaded, version %s", PROJECT_VERSION);
	return true;
}

void obs_module_unload(void)
{
	obs_frontend_remove_event_callback(SparkyStereo::onEvent, nullptr);
}
