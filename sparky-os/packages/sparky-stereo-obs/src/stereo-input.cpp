/* SPDX-License-Identifier: GPL-3.0-or-later */
/* SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com> */
// "Stereo input": a source filter that takes the source's packing, chosen from the stereo layer's own input list
// (stereo_policy_input_format_at(), the list every program of the edition offers) or read from the source's own 3D mark,
// to full side by side, left eye first, each eye at the resolution it has. Per source, as OBS keeps a source's settings
// in the scene collection: the input packing and "Swap left and right eyes", since a declaration can be wrong.
//
// "Automatic" is the source's own mark and nothing else, never the picture's shape:
// - a media source: the mark FFmpeg reads in OBS's media playback, the frame packing arrangement SEI (H.264 D.2.26,
//   Table D-9 of V16; H.265 D.2.16 and D.3.16) before the container's (Matroska StereoMode, RFC 9559 5.1.4.1.28.3;
//   MP4 st3d), handed on by the source's get_stereo3d procedure; frames in turn and two views (MV-HEVC) are paired
//   there, in the decoder, into one side by side picture;
// - an image source: the stereo layer's reader (Stereo::Picture::load(): JPS, MPO, PNG sTER, the layer's per-file
//   choice), whose pair is drawn as the layer made it;
// - no mark: the source is shown flat, the same picture in both eyes, and the packing is offered.
// A picture with its depth map in one frame gives its views through the stereo layer's depth library (libstereo-dibr,
// on the GPU) with the library's one default, as every program of the edition draws them.
#include "layer-words.hpp"

#include <graphics/vec4.h>
#include <obs-module.h>
#include <stereo-dibr-gl.h>
#include <stereo-dibr.h>
#include <stereo-policy.h>
#include <picture.h>

#include <EGL/egl.h>
#include <libavutil/stereo3d.h>

#include <QByteArray>
#include <QImage>
#include <QString>

#include <cmath>
#include <cstring>
#include <string>

namespace {

enum Mode { SideBySide = 0, TopBottom = 1, Rows = 2, Columns = 3, Checkerboard = 4, OnePicture = 5, Anaglyph = 6 };
// what the filter draws from: the source as the chain hands it, the stereo layer's pair of a picture file, or the views
// the depth library drew
enum Draw { FromSource, FromLayerPair, FromDepth };

// Picture::anaglyphTransform() of the layer (src/picture/anaglyph.cpp, src/gtk/stereo-gtk-unpack.c): for red/cyan,
// green/magenta and amber/blue, for the left eye's view and the right eye's, three weights per channel, then the
// three divisors.
constexpr int kAnaglyph[3][2][12] = {
	{{1, 0, 0, 1, 1, 0, 1, 0, 1, 1, 2, 2}, {1, 1, 0, 0, 1, 0, 0, 0, 1, 2, 1, 1}},
	{{1, 1, 0, 0, 1, 0, 0, 1, 1, 2, 1, 2}, {1, 0, 0, 1, 1, 1, 0, 0, 1, 1, 3, 1}},
	{{1, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 2}, {1, 0, 1, 0, 1, 1, 0, 0, 1, 2, 2, 1}},
};

struct Mark {
	int layout = STEREO_POLICY_LAYOUT_NONE;
	int order = STEREO_POLICY_LEFT_FIRST;
	int anaglyph = STEREO_POLICY_ANAGLYPH_NONE;
	int paired = 0; // the media source's decoder made one side by side picture of frames in turn (1) or two views (2)
	bool operator==(const Mark &o) const
	{
		return layout == o.layout && order == o.order && anaglyph == o.anaglyph && paired == o.paired;
	}
};

struct Filter {
	obs_source_t *context = nullptr;
	gs_effect_t *effect = nullptr;
	gs_eparam_t *mode = nullptr, *phase = nullptr, *viewSize = nullptr, *sourceSize = nullptr, *onlyEye = nullptr;
	gs_eparam_t *regionOffset = nullptr, *regionSize = nullptr, *image = nullptr;
	gs_eparam_t *weights[6] = {};
	std::string input = "automatic";
	bool swap = false;
	// decided at each tick from the source's size and mark
	int decidedMode = OnePicture;
	int decidedPhase = 0;
	int anaglyphPair = 0;
	Draw draw = FromSource;
	uint32_t sourceWidth = 0, sourceHeight = 0, viewWidth = 0, viewHeight = 0;
	std::string toldUnsupported;
	// the source's own mark
	Mark mark;
	bool markFound = false;
	// the source was asked for its mark and answered (a picture read by the layer, a media source's get_stereo3d);
	// false for a source the filter cannot ask (a transition's video, a source without the procedure)
	bool markAsked = false;
	long pairingAsked = -1;
	// an image source's file and the stereo layer's pair of it
	std::string imageFile;
	gs_texture_t *layerPair = nullptr;
	QImage layerPairPixels; // made into layerPair at the next draw, in the render
	uint32_t layerPairWidth = 0, layerPairHeight = 0;
	// a picture and its depth map: the parts cut from the source, the views drawn by libstereo-dibr
	int depthLayout = STEREO_POLICY_LAYOUT_NONE, depthFirst = 0;
	stereo_dibr_gl *dibr = nullptr;
	bool dibrFailed = false;
	std::string depthError;
	gs_texrender_t *frameTr = nullptr, *pictureTr = nullptr, *depthTr = nullptr, *layerTr = nullptr,
		       *layerDepthTr = nullptr;
	gs_texture_t *views = nullptr;
	bool viewsDrawn = false; // in this tick: both eye passes draw from the same views
};

const stereo_policy_input_format *formatById(const std::string &id)
{
	for (size_t i = 0; i < stereo_policy_input_format_count(); ++i) {
		const stereo_policy_input_format *format = stereo_policy_input_format_at(i);
		if (id == format->id)
			return format;
	}
	return stereo_policy_input_format_at(0); // "automatic"
}

// A 3D canvas lays its scenes out in one eye's space and draws them once per eye (libobs, obs_get_video_eye_size()):
// the filter is then one view wide and gives each eye pass its own view, the left one outside an eye pass, as a 2D
// screen shows a pair. On a 2D canvas it gives both views side by side.
bool canvasIsThreeD()
{
	return obs_get_video_eye_size(nullptr, nullptr);
}

bool isDepth(int layout)
{
	return stereo_policy_is_depth_layout(layout) && layout != STEREO_POLICY_LAYOUT_DEPTH_SEPARATE;
}

bool pairedByDecoder(int layout)
{
	return layout == STEREO_POLICY_LAYOUT_FRAME_SEQUENTIAL || layout == STEREO_POLICY_LAYOUT_BLOCK_LACED;
}

obs_source_t *parentOf(Filter *f)
{
	return obs_filter_get_parent(f->context);
}

bool isMediaSource(obs_source_t *source)
{
	const char *id = source ? obs_source_get_unversioned_id(source) : nullptr;
	return id && !strcmp(id, "ffmpeg_source");
}

bool isImageSource(obs_source_t *source)
{
	const char *id = source ? obs_source_get_unversioned_id(source) : nullptr;
	return id && !strcmp(id, "image_source");
}

// FFmpeg's AVStereo3DType as the layer's layout (the values libstereo-av's stereo-content.c and stereo-mark.c read);
// Matroska's two anaglyph StereoMode values reach FFmpeg only as the stream's tag (the names of that same reader).
Mark markOfMedia(long long type, long long flags, long long paired, const char *tag)
{
	Mark m;
	if (paired) {
		m.layout = STEREO_POLICY_LAYOUT_SIDE_BY_SIDE;
		m.paired = (int)paired;
		return m;
	}
	switch (type) {
	case AV_STEREO3D_SIDEBYSIDE:
		m.layout = STEREO_POLICY_LAYOUT_SIDE_BY_SIDE;
		break;
	case AV_STEREO3D_TOPBOTTOM:
		m.layout = STEREO_POLICY_LAYOUT_TOP_AND_BOTTOM;
		break;
	case AV_STEREO3D_FRAMESEQUENCE:
		m.layout = STEREO_POLICY_LAYOUT_FRAME_SEQUENTIAL;
		break;
	case AV_STEREO3D_CHECKERBOARD:
		m.layout = STEREO_POLICY_LAYOUT_CHECKERBOARD;
		break;
	case AV_STEREO3D_SIDEBYSIDE_QUINCUNX:
		m.layout = STEREO_POLICY_LAYOUT_SIDE_BY_SIDE_QUINCUNX;
		break;
	case AV_STEREO3D_LINES:
		m.layout = STEREO_POLICY_LAYOUT_ROWS;
		break;
	case AV_STEREO3D_COLUMNS:
		m.layout = STEREO_POLICY_LAYOUT_COLUMNS;
		break;
	default:
		break;
	}
	m.order = (flags & AV_STEREO3D_FLAG_INVERT) ? STEREO_POLICY_RIGHT_FIRST : STEREO_POLICY_LEFT_FIRST;
	if (m.layout == STEREO_POLICY_LAYOUT_NONE && tag) {
		if (!strcmp(tag, "anaglyph_cyan_red"))
			m.anaglyph = STEREO_POLICY_ANAGLYPH_RED_CYAN;
		else if (!strcmp(tag, "anaglyph_green_magenta"))
			m.anaglyph = STEREO_POLICY_ANAGLYPH_GREEN_MAGENTA;
	}
	return m;
}

// What the person asks the media source's decoder to pair: what the stream marks (Automatic), frames in turn of the
// chosen order, or nothing; nothing too while the filter is off, so the source shows what it shows without it.
void askPairing(Filter *f)
{
	obs_source_t *parent = parentOf(f);
	if (!isMediaSource(parent))
		return;
	const stereo_policy_input_format *format = formatById(f->input);
	long ask = 0;
	if (obs_source_enabled(f->context)) {
		if (f->input == "automatic")
			ask = 1;
		else if (pairedByDecoder(format->layout))
			ask = 2 | (format->order == STEREO_POLICY_RIGHT_FIRST ? 4 : 0);
	}
	if (ask == f->pairingAsked)
		return;
	f->pairingAsked = ask;
	calldata_t cd;
	calldata_init(&cd);
	calldata_set_int(&cd, "mode", ask & 3);
	calldata_set_bool(&cd, "right_first", (ask & 4) != 0);
	proc_handler_call(obs_source_get_proc_handler(parent), "set_stereo3d_pairing", &cd);
	calldata_free(&cd);
}

void dropLayerPair(Filter *f)
{
	f->layerPairPixels = QImage();
	f->layerPairWidth = f->layerPairHeight = 0;
	if (!f->layerPair)
		return;
	obs_enter_graphics();
	gs_texture_destroy(f->layerPair);
	obs_leave_graphics();
	f->layerPair = nullptr;
}

// An image source's file read by the stereo layer: its own mark (JPS, MPO, PNG sTER, a depth picture's mark, or the
// person's per-file choice kept by the layer), never the shape or the content. The pair is kept as the layer made it.
void readImageMark(Filter *f, const std::string &path)
{
	f->imageFile = path;
	dropLayerPair(f);
	f->mark = Mark();
	f->markFound = false;
	f->markAsked = true;
	if (path.empty())
		return;
	const Stereo::Picture picture =
		Stereo::Picture::load(QString::fromStdString(path), Stereo::Picture::Options(), Stereo::OutputMode::Stereo);
	const bool own = picture.source == Stereo::Picture::Source::FileMark ||
			 picture.source == Stereo::Picture::Source::Format ||
			 picture.source == Stereo::Picture::Source::User;
	if (!own || !picture.isStereo())
		return;
	const QImage pair = picture.sideBySide().convertToFormat(QImage::Format_RGBA8888);
	if (pair.isNull() || pair.width() < 2)
		return;
	f->layerPairPixels = pair;
	f->layerPairWidth = (uint32_t)pair.width();
	f->layerPairHeight = (uint32_t)pair.height();
	f->mark.layout = STEREO_POLICY_LAYOUT_SIDE_BY_SIDE;
	f->markFound = true;
	blog(LOG_INFO, "[sparky-stereo-obs] \"%s\": the stereo layer reads %s as a pair, %ux%u per eye",
	     obs_source_get_name(f->context), path.c_str(), f->layerPairWidth / 2, f->layerPairHeight);
}

// The source's own mark, read again at each tick (a stream's mark can change); true when it changed.
bool readMark(Filter *f)
{
	obs_source_t *parent = parentOf(f);
	if (isImageSource(parent)) {
		obs_data_t *settings = obs_source_get_settings(parent);
		const std::string path = settings ? obs_data_get_string(settings, "file") : "";
		obs_data_release(settings);
		if (path == f->imageFile)
			return false;
		readImageMark(f, path);
		return true;
	}
	Mark m;
	bool found = false, asked = false;
	if (isMediaSource(parent)) {
		calldata_t cd;
		calldata_init(&cd);
		if (proc_handler_call(obs_source_get_proc_handler(parent), "get_stereo3d", &cd)) {
			asked = true;
			m = markOfMedia(calldata_int(&cd, "type"), calldata_int(&cd, "flags"), calldata_int(&cd, "paired"),
					calldata_string(&cd, "stereo_mode"));
			found = m.layout != STEREO_POLICY_LAYOUT_NONE || m.anaglyph != STEREO_POLICY_ANAGLYPH_NONE;
		}
		calldata_free(&cd);
	}
	if (m == f->mark && found == f->markFound && asked == f->markAsked)
		return false;
	f->mark = m;
	f->markFound = found;
	f->markAsked = asked;
	return true;
}

void setViews(Filter *f, int layout, uint32_t w, uint32_t h)
{
	switch (layout) {
	case STEREO_POLICY_LAYOUT_SIDE_BY_SIDE:
	case STEREO_POLICY_LAYOUT_SIDE_BY_SIDE_QUINCUNX:
		f->decidedMode = SideBySide;
		f->viewWidth = w / 2;
		break;
	case STEREO_POLICY_LAYOUT_TOP_AND_BOTTOM:
		f->decidedMode = TopBottom;
		f->viewHeight = h / 2;
		break;
	case STEREO_POLICY_LAYOUT_ROWS:
		f->decidedMode = Rows;
		f->viewHeight = h / 2;
		break;
	case STEREO_POLICY_LAYOUT_COLUMNS:
		f->decidedMode = Columns;
		f->viewWidth = w / 2;
		break;
	case STEREO_POLICY_LAYOUT_CHECKERBOARD:
		f->decidedMode = Checkerboard;
		f->viewWidth = w / 2;
		break;
	default:
		f->decidedMode = OnePicture;
		break;
	}
}

// The parts of a picture with its depth map in one frame, cut as libstereo-gtk's depth_packed() and the Qt layer's
// unpackWithDepth() cut them: the order says where the picture is; the views are drawn, so they are never swapped.
struct Region {
	uint32_t x, y, w, h;
};
bool depthRegions(int layout, int depthFirst, uint32_t w, uint32_t h, Region *pic, Region *dep, Region *lay,
		  Region *layDep)
{
	*lay = *layDep = Region{0, 0, 0, 0};
	if (layout == STEREO_POLICY_LAYOUT_DEPTH_SIDE_BY_SIDE && w >= 2 && w % 2 == 0) {
		const Region a{0, 0, w / 2, h}, b{w / 2, 0, w / 2, h};
		*pic = depthFirst ? b : a;
		*dep = depthFirst ? a : b;
		return true;
	}
	if (layout == STEREO_POLICY_LAYOUT_DEPTH_TOP_AND_BOTTOM && h >= 2 && h % 2 == 0) {
		const Region a{0, 0, w, h / 2}, b{0, h / 2, w, h / 2};
		*pic = depthFirst ? b : a;
		*dep = depthFirst ? a : b;
		return true;
	}
	if (layout == STEREO_POLICY_LAYOUT_DEPTH_GRAPHICS && h >= 4 && h % 4 == 0) {
		const uint32_t q = h / 4;
		*pic = Region{0, 0, w, q};
		*dep = Region{0, q, w, q};
		*lay = Region{0, 2 * q, w, q};
		*layDep = Region{0, 3 * q, w, q};
		return true;
	}
	if (layout == STEREO_POLICY_LAYOUT_DEPTH_BACKGROUND && w >= 2 && h >= 2 && w % 2 == 0 && h % 2 == 0) {
		const uint32_t hw = w / 2, hh = h / 2;
		*pic = Region{0, 0, hw, hh};
		*dep = Region{hw, 0, hw, hh};
		*lay = Region{0, hh, hw, hh};
		*layDep = Region{hw, hh, hw, hh};
		return true;
	}
	return false;
}

void tellOnce(Filter *f, const char *what)
{
	if (f->toldUnsupported == f->input + what)
		return;
	f->toldUnsupported = f->input + what;
	blog(LOG_WARNING, "[sparky-stereo-obs] \"%s\": %s; the source is shown as one picture in both eyes",
	     obs_source_get_name(f->context), what);
}

void decide(Filter *f)
{
	obs_source_t *target = obs_filter_get_target(f->context);
	const uint32_t w = target ? obs_source_get_base_width(target) : 0;
	const uint32_t h = target ? obs_source_get_base_height(target) : 0;
	f->sourceWidth = w;
	f->sourceHeight = h;
	f->decidedMode = OnePicture;
	f->decidedPhase = 0;
	f->anaglyphPair = 0;
	f->draw = FromSource;
	f->depthLayout = STEREO_POLICY_LAYOUT_NONE;
	f->viewWidth = w;
	f->viewHeight = h;
	if (!w || !h)
		return;
	const stereo_policy_input_format *format = formatById(f->input);
	const int swap = f->swap ? 1 : 0;

	if (f->input == "automatic") {
		if (!f->markFound)
			return; // no mark: flat, the packing offered
		if (f->layerPairWidth) {
			f->draw = FromLayerPair;
			f->decidedMode = SideBySide;
			f->viewWidth = f->layerPairWidth / 2;
			f->viewHeight = f->layerPairHeight;
			f->decidedPhase = swap;
			return;
		}
		if (f->mark.anaglyph) {
			f->decidedMode = Anaglyph;
			f->anaglyphPair = f->mark.anaglyph;
			f->decidedPhase = swap;
			return;
		}
		if (pairedByDecoder(f->mark.layout)) {
			tellOnce(f, "the decoder has not paired these frames in turn yet");
			return;
		}
		setViews(f, f->mark.layout, w, h);
		f->decidedPhase = (f->mark.order == STEREO_POLICY_RIGHT_FIRST ? 1 : 0) ^ swap;
		return;
	}
	if (format->view == 3)
		return; // Not 3D
	if (format->anaglyph) {
		f->decidedMode = Anaglyph;
		f->anaglyphPair = format->anaglyph;
		f->decidedPhase = swap;
		return;
	}
	if (pairedByDecoder(format->layout)) {
		// paired in the media source's decoder in the chosen order: the source is then left-first side by side
		if (f->mark.paired == 1) {
			setViews(f, STEREO_POLICY_LAYOUT_SIDE_BY_SIDE, w, h);
			f->decidedPhase = swap;
		} else if (!isMediaSource(parentOf(f))) {
			tellOnce(f, "frames in turn are paired by a media source's decoder, and this source has none");
		}
		return;
	}
	if (isDepth(format->layout)) {
		Region pic, dep, lay, layDep;
		if (!depthRegions(format->layout, format->order, w, h, &pic, &dep, &lay, &layDep)) {
			tellOnce(f, "the frame cannot be cut into a picture and its depth map");
			return;
		}
		f->draw = FromDepth;
		f->depthLayout = format->layout;
		f->depthFirst = format->order;
		f->decidedMode = SideBySide;
		f->viewWidth = pic.w;
		f->viewHeight = pic.h;
		return;
	}
	setViews(f, format->layout, w, h);
	f->decidedPhase = (format->order == STEREO_POLICY_RIGHT_FIRST ? 1 : 0) ^ swap;
	if (!f->viewWidth || !f->viewHeight) {
		f->decidedMode = OnePicture;
		f->viewWidth = w;
		f->viewHeight = h;
	}
}

const char *filterName(void *)
{
	return obs_module_text("StereoInput");
}

void filterUpdate(void *data, obs_data_t *settings)
{
	auto *f = static_cast<Filter *>(data);
	f->input = obs_data_get_string(settings, "input");
	if (f->input.empty())
		f->input = "automatic";
	f->swap = obs_data_get_bool(settings, "swap");
	askPairing(f);
	decide(f);
}

void *filterCreate(obs_data_t *settings, obs_source_t *context)
{
	auto *f = new Filter;
	f->context = context;
	char *path = obs_module_file("stereo-input.effect");
	obs_enter_graphics();
	f->effect = gs_effect_create_from_file(path, nullptr);
	if (f->effect) {
		f->mode = gs_effect_get_param_by_name(f->effect, "mode");
		f->phase = gs_effect_get_param_by_name(f->effect, "phase");
		f->viewSize = gs_effect_get_param_by_name(f->effect, "view_size");
		f->sourceSize = gs_effect_get_param_by_name(f->effect, "source_size");
		f->onlyEye = gs_effect_get_param_by_name(f->effect, "only_eye");
		f->regionOffset = gs_effect_get_param_by_name(f->effect, "region_offset");
		f->regionSize = gs_effect_get_param_by_name(f->effect, "region_size");
		f->image = gs_effect_get_param_by_name(f->effect, "image");
		const char *names[6] = {"left_r", "left_g", "left_b", "right_r", "right_g", "right_b"};
		for (int i = 0; i < 6; ++i)
			f->weights[i] = gs_effect_get_param_by_name(f->effect, names[i]);
	}
	f->frameTr = gs_texrender_create(GS_RGBA, GS_ZS_NONE);
	f->pictureTr = gs_texrender_create(GS_RGBA_UNORM, GS_ZS_NONE);
	f->depthTr = gs_texrender_create(GS_R8, GS_ZS_NONE);
	f->layerTr = gs_texrender_create(GS_RGBA_UNORM, GS_ZS_NONE);
	f->layerDepthTr = gs_texrender_create(GS_R8, GS_ZS_NONE);
	obs_leave_graphics();
	if (!f->effect)
		blog(LOG_ERROR, "[sparky-stereo-obs] the Stereo input effect could not be loaded from %s", path ? path : "?");
	bfree(path);
	filterUpdate(f, settings);
	return f;
}

void filterDestroy(void *data)
{
	auto *f = static_cast<Filter *>(data);
	obs_source_t *parent = parentOf(f);
	if (isMediaSource(parent) && f->pairingAsked > 0) {
		calldata_t cd;
		calldata_init(&cd);
		calldata_set_int(&cd, "mode", 0);
		calldata_set_bool(&cd, "right_first", false);
		proc_handler_call(obs_source_get_proc_handler(parent), "set_stereo3d_pairing", &cd);
		calldata_free(&cd);
	}
	obs_enter_graphics();
	gs_effect_destroy(f->effect);
	gs_texture_destroy(f->layerPair);
	gs_texture_destroy(f->views);
	gs_texrender_destroy(f->frameTr);
	gs_texrender_destroy(f->pictureTr);
	gs_texrender_destroy(f->depthTr);
	gs_texrender_destroy(f->layerTr);
	gs_texrender_destroy(f->layerDepthTr);
	if (f->dibr)
		stereo_dibr_gl_free(f->dibr);
	obs_leave_graphics();
	delete f;
}

void filterDefaults(obs_data_t *settings)
{
	obs_data_set_default_string(settings, "input", "automatic");
	obs_data_set_default_bool(settings, "swap", false);
}

// What the person sees under the list: the source was asked and has no mark (Automatic shows it flat), the source is a
// kind the filter cannot ask for a mark (also flat), its packing needs a media source's decoder, or its depth could not
// be drawn; "Swap left and right eyes" only while the source is shown in 3D and its views are not drawn from depth.
void showNotes(obs_properties_t *props, Filter *f, const stereo_policy_input_format *format)
{
	const bool automatic = !strcmp(format->id, "automatic");
	const bool decoder = pairedByDecoder(format->layout) && f && !isMediaSource(parentOf(f));
	const bool noMark = automatic && f && f->markAsked && !f->markFound;
	const bool cannotAsk = automatic && f && !f->markAsked;
	obs_property_set_visible(obs_properties_get(props, "no_mark"), noMark);
	obs_property_set_visible(obs_properties_get(props, "cannot_ask"), cannotAsk);
	obs_property_set_visible(obs_properties_get(props, "needs_decoder"), decoder);
	obs_property_t *depth = obs_properties_get(props, "depth_failed");
	const bool depthFailed = isDepth(format->layout) && f && f->dibrFailed;
	obs_property_set_visible(depth, depthFailed);
	if (depthFailed) {
		std::string text = obs_module_text("Note.DepthFailed");
		const size_t at = text.find("%1");
		if (at != std::string::npos)
			text.replace(at, 2, f->depthError);
		obs_property_set_description(depth, text.c_str());
	}
	const bool shownIn3D = format->view != 3 && !isDepth(format->layout) && !noMark && !cannotAsk && !decoder;
	obs_property_set_visible(obs_properties_get(props, "swap"), shownIn3D);
}

bool inputChanged(obs_properties_t *props, obs_property_t *, obs_data_t *settings)
{
	auto *f = static_cast<Filter *>(obs_properties_get_param(props));
	showNotes(props, f, formatById(obs_data_get_string(settings, "input")));
	return true;
}

obs_properties_t *filterProperties(void *data)
{
	auto *f = static_cast<Filter *>(data);
	obs_properties_t *props = obs_properties_create();
	obs_properties_set_param(props, f, nullptr);
	const QByteArray title = SparkyStereo::layerWord("3D Input Format").toUtf8();
	obs_property_t *list = obs_properties_add_list(props, "input", title.constData(), OBS_COMBO_TYPE_LIST,
						       OBS_COMBO_FORMAT_STRING);
	for (size_t i = 0; i < stereo_policy_input_format_count(); ++i) {
		const stereo_policy_input_format *format = stereo_policy_input_format_at(i);
		const QByteArray label = SparkyStereo::layerWord(format->text).toUtf8();
		obs_property_list_add_string(list, label.constData(), format->id);
	}
	obs_property_set_modified_callback(list, inputChanged);
	const QByteArray swap = SparkyStereo::layerWord("Swap left and right eyes").toUtf8();
	obs_properties_add_bool(props, "swap", swap.constData());
	const char *notes[][2] = {{"no_mark", "Note.NoMark"},
				  {"cannot_ask", "Note.CannotAsk"},
				  {"needs_decoder", "Note.NeedsDecoder"},
				  {"depth_failed", "Note.DepthFailed"}};
	for (const auto &n : notes) {
		obs_property_t *note = obs_properties_add_text(props, n[0], obs_module_text(n[1]), OBS_TEXT_INFO);
		obs_property_text_set_info_type(note, OBS_TEXT_INFO_WARNING);
	}
	obs_properties_add_text(props, "about", obs_module_text("StereoInputAbout"), OBS_TEXT_INFO);
	showNotes(props, f, formatById(f ? f->input : "automatic"));
	return props;
}

void filterTick(void *data, float)
{
	auto *f = static_cast<Filter *>(data);
	f->viewsDrawn = false;
	askPairing(f);
	const bool markChanged = readMark(f);
	obs_source_t *target = obs_filter_get_target(f->context);
	if (markChanged || (target && (obs_source_get_base_width(target) != f->sourceWidth ||
				       obs_source_get_base_height(target) != f->sourceHeight)))
		decide(f);
}

unsigned glName(gs_texture_t *texture)
{
	return *static_cast<const unsigned *>(gs_texture_get_obj(texture));
}

stereo_dibr_gl_function resolveGl(const char *name)
{
	return reinterpret_cast<stereo_dibr_gl_function>(eglGetProcAddress(name));
}

// The source's frame, as the filters before this one hand it on, into frameTr.
bool renderFrame(Filter *f)
{
	gs_texrender_reset(f->frameTr);
	if (!gs_texrender_begin(f->frameTr, f->sourceWidth, f->sourceHeight))
		return false;
	struct vec4 clear;
	vec4_zero(&clear);
	gs_clear(GS_CLEAR_COLOR, &clear, 0.0f, 0);
	gs_ortho(0.0f, (float)f->sourceWidth, 0.0f, (float)f->sourceHeight, -100.0f, 100.0f);
	obs_source_skip_video_filter(f->context);
	gs_texrender_end(f->frameTr);
	return true;
}

// One part of the frame copied as it is (technique Region), or its gray as the layer reads a depth map (Gray).
bool cutPart(Filter *f, gs_texrender_t *into, const Region &r, const char *technique)
{
	gs_texrender_reset(into);
	if (!r.w || !gs_texrender_begin(into, r.w, r.h))
		return false;
	gs_ortho(0.0f, (float)r.w, 0.0f, (float)r.h, -100.0f, 100.0f);
	int offset[2] = {(int)r.x, (int)r.y}, size[2] = {(int)r.w, (int)r.h};
	gs_effect_set_texture(f->image, gs_texrender_get_texture(f->frameTr));
	gs_effect_set_val(f->regionOffset, offset, sizeof(offset));
	gs_effect_set_val(f->regionSize, size, sizeof(size));
	gs_blend_state_push();
	gs_blend_function(GS_BLEND_ONE, GS_BLEND_ZERO);
	while (gs_effect_loop(f->effect, technique))
		gs_draw_sprite(nullptr, 0, r.w, r.h);
	gs_blend_state_pop();
	gs_texrender_end(into);
	return true;
}

void depthFailed(Filter *f, const std::string &why)
{
	f->dibrFailed = true;
	f->depthError = why;
	blog(LOG_WARNING, "[sparky-stereo-obs] \"%s\": the depth could not be drawn (%s); both eyes see the picture alone",
	     obs_source_get_name(f->context), why.c_str());
}

// Both views of the picture with its depth map, drawn by libstereo-dibr on the GPU in OBS's own context with the
// library's one default (stereo_dibr_options_default(): the depth map's gray as nearness, 8 bits), as libstereo-gtk's
// depth_views() and the Qt layer's Picture::fromDepth() draw them on the processor. Once a tick: both eye passes of a
// 3D canvas, and every view of this source in the tick, show the same frame.
bool drawDepthViews(Filter *f)
{
	if (f->viewsDrawn)
		return f->views != nullptr;
	f->viewsDrawn = true;
	if (f->dibrFailed)
		return false;
	if (gs_get_device_type() != GS_DEVICE_OPENGL) {
		depthFailed(f, "OBS does not draw with OpenGL");
		return false;
	}
	Region pic, dep, lay, layDep;
	if (!depthRegions(f->depthLayout, f->depthFirst, f->sourceWidth, f->sourceHeight, &pic, &dep, &lay, &layDep))
		return false;
	if (!f->dibr) {
		f->dibr = stereo_dibr_gl_create(resolveGl, STEREO_DIBR_GL_DESKTOP);
		if (!f->dibr) {
			depthFailed(f, "libstereo-dibr's passes did not compile in OBS's OpenGL context");
			return false;
		}
	}
	if (!renderFrame(f) || !cutPart(f, f->pictureTr, pic, "Region") || !cutPart(f, f->depthTr, dep, "Gray"))
		return false;
	const bool layered = lay.w != 0;
	if (layered && (!cutPart(f, f->layerTr, lay, "Region") || !cutPart(f, f->layerDepthTr, layDep, "Gray")))
		return false;
	if (!f->views || gs_texture_get_width(f->views) != 2 * pic.w || gs_texture_get_height(f->views) != pic.h) {
		gs_texture_destroy(f->views);
		f->views = gs_texture_create(2 * pic.w, pic.h, GS_RGBA_UNORM, 1, nullptr, GS_RENDER_TARGET);
		if (!f->views)
			return false;
	}
	struct stereo_dibr_options options;
	struct stereo_depth_convention convention = {};
	struct stereo_dibr_params params;
	stereo_dibr_options_default(&options);
	stereo_dibr_params_default(&params);
	convention.kind = STEREO_DEPTH_NEARNESS;
	convention.bits = 8;
	stereo_dibr_options_apply(&options, &convention, &params);
	float table[256], layerTable[256];
	if (stereo_depth_parallax_table(&convention, (int)pic.w, table) < 0) {
		depthFailed(f, "the depth convention gave no parallax table");
		return false;
	}
	const float hole[4] = {0.0f, 0.0f, 0.0f, 1.0f};
	int ret;
	if (!layered) {
		ret = stereo_dibr_gl_render(f->dibr, &params, table, 256, glName(gs_texrender_get_texture(f->pictureTr)),
					    (int)pic.w, (int)pic.h, glName(gs_texrender_get_texture(f->depthTr)),
					    (int)dep.w, (int)dep.h, 0, glName(f->views), hole);
	} else {
		// a layer's samples of 0 hold nothing: no graphics there, no background there (libstereo-gtk)
		memcpy(layerTable, table, sizeof(table));
		layerTable[0] = NAN;
		const int role = f->depthLayout == STEREO_POLICY_LAYOUT_DEPTH_GRAPHICS ? STEREO_DIBR_LAYER_OVERLAY
										       : STEREO_DIBR_LAYER_BACKGROUND;
		ret = stereo_dibr_gl_render_layer(f->dibr, &params, table, 256,
						  glName(gs_texrender_get_texture(f->pictureTr)), (int)pic.w,
						  (int)pic.h, glName(gs_texrender_get_texture(f->depthTr)), (int)dep.w,
						  (int)dep.h, 0, role, glName(gs_texrender_get_texture(f->layerTr)),
						  layerTable, 256, glName(gs_texrender_get_texture(f->layerDepthTr)),
						  (int)layDep.w, (int)layDep.h, glName(f->views), hole);
	}
	if (ret != 0) {
		depthFailed(f, std::string("libstereo-dibr: ") + stereo_dibr_gl_error(f->dibr));
		return false;
	}
	return true;
}

void setWeights(Filter *f)
{
	// the weights are uniforms of the effect: set every frame (zero outside an anaglyph input), or libobs logs each
	// unset one as "set to invalid size 0" on every draw
	struct vec4 none;
	vec4_zero(&none);
	for (int i = 0; i < 6; ++i)
		gs_effect_set_vec4(f->weights[i], &none);
	if (f->decidedMode == Anaglyph && f->anaglyphPair >= 1 && f->anaglyphPair <= 3) {
		for (int out = 0; out < 2; ++out) {
			// the left output eye takes the left eye's view of the colours, or the right one's with the swap
			const int *t = kAnaglyph[f->anaglyphPair - 1][out == 0 ? f->decidedPhase : 1 - f->decidedPhase];
			for (int c = 0; c < 3; ++c) {
				struct vec4 w;
				vec4_set(&w, (float)t[3 * c], (float)t[3 * c + 1], (float)t[3 * c + 2], (float)t[9 + c]);
				gs_effect_set_vec4(f->weights[3 * out + c], &w);
			}
		}
	}
}

void setUnpack(Filter *f, int mode, int phase, int onlyEye, uint32_t sourceW, uint32_t sourceH)
{
	gs_effect_set_int(f->mode, mode);
	gs_effect_set_int(f->phase, phase);
	gs_effect_set_int(f->onlyEye, onlyEye);
	int viewSize[2] = {(int)f->viewWidth, (int)f->viewHeight};
	int sourceSize[2] = {(int)sourceW, (int)sourceH};
	gs_effect_set_val(f->viewSize, viewSize, sizeof(viewSize));
	gs_effect_set_val(f->sourceSize, sourceSize, sizeof(sourceSize));
	int zero[2] = {0, 0};
	gs_effect_set_val(f->regionOffset, zero, sizeof(zero));
	gs_effect_set_val(f->regionSize, viewSize, sizeof(viewSize));
	setWeights(f);
}

// A pair the filter holds itself (the stereo layer's, or the depth library's views), drawn as side by side.
void drawPair(Filter *f, gs_texture_t *pair, int phase, int onlyEye)
{
	setUnpack(f, SideBySide, phase, onlyEye, gs_texture_get_width(pair), gs_texture_get_height(pair));
	gs_effect_set_texture(f->image, pair);
	gs_blend_state_push();
	gs_blend_function(GS_BLEND_ONE, GS_BLEND_ZERO);
	while (gs_effect_loop(f->effect, "Draw"))
		gs_draw_sprite(pair, 0, onlyEye >= 0 ? f->viewWidth : 2 * f->viewWidth, f->viewHeight);
	gs_blend_state_pop();
}

void filterRender(void *data, gs_effect_t *)
{
	auto *f = static_cast<Filter *>(data);
	if (!f->effect || !f->viewWidth || !f->viewHeight) {
		obs_source_skip_video_filter(f->context);
		return;
	}
	const int onlyEye = canvasIsThreeD() ? (obs_get_render_eye() == OBS_RENDER_EYE_RIGHT ? 1 : 0) : -1;
	if (f->draw == FromLayerPair) {
		// the layer's pixels become a texture in the render, where libobs draws: on zink a texture made in the tick
		// was drawn empty the first time (step 4, screens-nvidia-zink)
		if (!f->layerPair && !f->layerPairPixels.isNull()) {
			const uint8_t *bits = f->layerPairPixels.constBits();
			f->layerPair = gs_texture_create(f->layerPairWidth, f->layerPairHeight, GS_RGBA_UNORM, 1, &bits, 0);
			f->layerPairPixels = QImage();
		}
		if (f->layerPair)
			drawPair(f, f->layerPair, f->decidedPhase, onlyEye);
		return;
	}
	if (f->draw == FromDepth) {
		if (drawDepthViews(f)) {
			drawPair(f, f->views, 0, onlyEye);
			return;
		}
		// told (the log and the filter's note): the picture alone in both eyes, at the views' size
		Region pic, dep, lay, layDep;
		if (!depthRegions(f->depthLayout, f->depthFirst, f->sourceWidth, f->sourceHeight, &pic, &dep, &lay,
				  &layDep) ||
		    !renderFrame(f))
			return;
		gs_texture_t *frame = gs_texrender_get_texture(f->frameTr);
		setUnpack(f, OnePicture, 0, onlyEye, f->sourceWidth, f->sourceHeight);
		int offset[2] = {(int)pic.x, (int)pic.y};
		gs_effect_set_val(f->regionOffset, offset, sizeof(offset));
		gs_effect_set_texture(f->image, frame);
		gs_blend_state_push();
		gs_blend_function(GS_BLEND_ONE, GS_BLEND_ZERO);
		while (gs_effect_loop(f->effect, "Draw"))
			gs_draw_sprite(frame, 0, onlyEye >= 0 ? f->viewWidth : 2 * f->viewWidth, f->viewHeight);
		gs_blend_state_pop();
		return;
	}
	if (!obs_source_process_filter_begin(f->context, GS_RGBA, OBS_NO_DIRECT_RENDERING))
		return;
	setUnpack(f, f->decidedMode, f->decidedPhase, onlyEye, f->sourceWidth, f->sourceHeight);
	gs_blend_state_push();
	gs_blend_function(GS_BLEND_ONE, GS_BLEND_ZERO);
	obs_source_process_filter_end(f->context, f->effect, onlyEye >= 0 ? f->viewWidth : 2 * f->viewWidth,
				      f->viewHeight);
	gs_blend_state_pop();
}

uint32_t filterWidth(void *data)
{
	auto *f = static_cast<Filter *>(data);
	return canvasIsThreeD() ? f->viewWidth : 2 * f->viewWidth;
}

uint32_t filterHeight(void *data)
{
	auto *f = static_cast<Filter *>(data);
	return f->viewHeight;
}

} // namespace

struct obs_source_info sparky_stereo_input_info = [] {
	struct obs_source_info info = {};
	info.id = "sparky_stereo_input";
	info.type = OBS_SOURCE_TYPE_FILTER;
	info.output_flags = OBS_SOURCE_VIDEO;
	info.get_name = filterName;
	info.create = filterCreate;
	info.destroy = filterDestroy;
	info.update = filterUpdate;
	info.get_defaults = filterDefaults;
	info.get_properties = filterProperties;
	info.video_tick = filterTick;
	info.video_render = filterRender;
	info.get_width = filterWidth;
	info.get_height = filterHeight;
	return info;
}();
