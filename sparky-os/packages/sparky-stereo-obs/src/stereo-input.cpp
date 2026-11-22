/* SPDX-License-Identifier: GPL-3.0-or-later */
/* SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com> */
// "Stereo input": a source filter that takes the source's packing, chosen from the stereo layer's own input list
// (stereo_policy_input_format_at(), the list every program of the edition offers) or decided by the layer's video rule,
// to full side by side, left eye first, each eye at the resolution it has. Per source, as OBS keeps a source's
// settings in the scene collection: the input packing and "Swap left and right eyes", since a declaration can be wrong.
#include "layer-words.hpp"

#include <graphics/vec4.h>
#include <obs-module.h>
#include <stereo-policy.h>

#include <QByteArray>

#include <cstring>
#include <string>

namespace {

enum Mode { SideBySide = 0, TopBottom = 1, Rows = 2, Columns = 3, Checkerboard = 4, OnePicture = 5, Anaglyph = 6 };

// Picture::anaglyphTransform() of the layer (src/picture/anaglyph.cpp, src/gtk/stereo-gtk-unpack.c): for red/cyan,
// green/magenta and amber/blue, for the left eye's view and the right eye's, three weights per channel, then the
// three divisors.
constexpr int kAnaglyph[3][2][12] = {
	{{1, 0, 0, 1, 1, 0, 1, 0, 1, 1, 2, 2}, {1, 1, 0, 0, 1, 0, 0, 0, 1, 2, 1, 1}},
	{{1, 1, 0, 0, 1, 0, 0, 1, 1, 2, 1, 2}, {1, 0, 0, 1, 1, 1, 0, 0, 1, 1, 3, 1}},
	{{1, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 2}, {1, 0, 1, 0, 1, 1, 0, 0, 1, 2, 2, 1}},
};

struct Filter {
	obs_source_t *context = nullptr;
	gs_effect_t *effect = nullptr;
	gs_eparam_t *mode = nullptr, *phase = nullptr, *viewSize = nullptr, *sourceSize = nullptr, *onlyEye = nullptr;
	gs_eparam_t *weights[6] = {};
	std::string input = "automatic";
	bool swap = false;
	// decided at each tick from the source's size
	int decidedMode = OnePicture;
	int decidedPhase = 0;
	int anaglyphPair = 0;
	uint32_t sourceWidth = 0, sourceHeight = 0, viewWidth = 0, viewHeight = 0;
	std::string toldUnsupported;
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

// The packings that need more than the one picture a filter is handed (frames in turn, both views in one block, a
// picture and its depth) are listed, as every list of the edition lists the whole specification, and are not converted
// yet: say so where the person chose it and in OBS's log.
// A 3D canvas lays its scenes out in one eye's space and draws them once per eye (libobs, obs_get_video_eye_size()):
// the filter is then one view wide and gives each eye pass its own view, the left one outside an eye pass, as a 2D
// screen shows a pair. On a 2D canvas it gives both views side by side, as before.
bool canvasIsThreeD()
{
	return obs_get_video_eye_size(nullptr, nullptr);
}

bool convertsOnePicture(const stereo_policy_input_format *format)
{
	if (format->anaglyph || format->view == 3)
		return true;
	switch (format->layout) {
	case STEREO_POLICY_LAYOUT_NONE:
	case STEREO_POLICY_LAYOUT_SIDE_BY_SIDE:
	case STEREO_POLICY_LAYOUT_SIDE_BY_SIDE_QUINCUNX:
	case STEREO_POLICY_LAYOUT_TOP_AND_BOTTOM:
	case STEREO_POLICY_LAYOUT_ROWS:
	case STEREO_POLICY_LAYOUT_COLUMNS:
	case STEREO_POLICY_LAYOUT_CHECKERBOARD:
		return true;
	default:
		return false;
	}
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
	f->viewWidth = w;
	f->viewHeight = h;
	if (!w || !h)
		return;
	const stereo_policy_input_format *format = formatById(f->input);
	if (format->anaglyph) {
		f->decidedMode = Anaglyph;
		f->anaglyphPair = format->anaglyph;
		f->decidedPhase = f->swap ? 1 : 0;
		return;
	}
	if (format->view == 3 || !convertsOnePicture(format)) {
		if (!convertsOnePicture(format) && f->toldUnsupported != f->input) {
			f->toldUnsupported = f->input;
			blog(LOG_WARNING,
			     "[sparky-stereo-obs] \"%s\": %s needs more than one picture and is not converted yet; the source is "
			     "shown as one picture in both eyes",
			     obs_source_get_name(f->context), format->id);
		}
		return; // one picture in both eyes
	}
	const int userLayout = f->input == "automatic" ? STEREO_POLICY_LAYOUT_NONE : format->layout;
	int layout = STEREO_POLICY_LAYOUT_NONE, order = STEREO_POLICY_LEFT_FIRST, source = 0;
	if (stereo_policy_video_layout((int)w, (int)h, nullptr, userLayout, format->order, f->swap ? 1 : 0, &layout,
				       &order, &source) != 0)
		return;
	f->decidedPhase = order == STEREO_POLICY_RIGHT_FIRST ? 1 : 0;
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
		f->decidedPhase = 0;
		break;
	}
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
		const char *names[6] = {"left_r", "left_g", "left_b", "right_r", "right_g", "right_b"};
		for (int i = 0; i < 6; ++i)
			f->weights[i] = gs_effect_get_param_by_name(f->effect, names[i]);
	}
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
	obs_enter_graphics();
	gs_effect_destroy(f->effect);
	obs_leave_graphics();
	delete f;
}

void filterDefaults(obs_data_t *settings)
{
	obs_data_set_default_string(settings, "input", "automatic");
	obs_data_set_default_bool(settings, "swap", false);
}

bool inputChanged(obs_properties_t *props, obs_property_t *, obs_data_t *settings)
{
	const stereo_policy_input_format *format = formatById(obs_data_get_string(settings, "input"));
	obs_property_t *note = obs_properties_get(props, "note");
	obs_property_set_visible(note, !convertsOnePicture(format));
	obs_property_set_visible(obs_properties_get(props, "swap"), format->view != 3);
	return true;
}

obs_properties_t *filterProperties(void *)
{
	obs_properties_t *props = obs_properties_create();
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
	obs_property_t *note = obs_properties_add_text(props, "note", obs_module_text("NotConvertedYet"), OBS_TEXT_INFO);
	obs_property_text_set_info_type(note, OBS_TEXT_INFO_WARNING);
	obs_properties_add_text(props, "about", obs_module_text("StereoInputAbout"), OBS_TEXT_INFO);
	return props;
}

void filterTick(void *data, float)
{
	auto *f = static_cast<Filter *>(data);
	obs_source_t *target = obs_filter_get_target(f->context);
	if (target && (obs_source_get_base_width(target) != f->sourceWidth ||
		       obs_source_get_base_height(target) != f->sourceHeight))
		decide(f);
}

void filterRender(void *data, gs_effect_t *)
{
	auto *f = static_cast<Filter *>(data);
	if (!f->effect || !f->viewWidth || !f->viewHeight) {
		obs_source_skip_video_filter(f->context);
		return;
	}
	if (!obs_source_process_filter_begin(f->context, GS_RGBA, OBS_NO_DIRECT_RENDERING))
		return;
	const int onlyEye = canvasIsThreeD() ? (obs_get_render_eye() == OBS_RENDER_EYE_RIGHT ? 1 : 0) : -1;
	gs_effect_set_int(f->mode, f->decidedMode);
	gs_effect_set_int(f->phase, f->decidedPhase);
	gs_effect_set_int(f->onlyEye, onlyEye);
	int viewSize[2] = {(int)f->viewWidth, (int)f->viewHeight};
	int sourceSize[2] = {(int)f->sourceWidth, (int)f->sourceHeight};
	gs_effect_set_val(f->viewSize, viewSize, sizeof(viewSize));
	gs_effect_set_val(f->sourceSize, sourceSize, sizeof(sourceSize));
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
