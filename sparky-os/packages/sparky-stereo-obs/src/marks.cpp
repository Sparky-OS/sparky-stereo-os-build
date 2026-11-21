/* SPDX-License-Identifier: GPL-3.0-or-later */
/* SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com> */
// The 3D marks of what OBS records and streams, written by the encoder while it encodes: never a file mended after the
// recording (Daniel, 2026-10-14: "fix it at the proper layer ... not an after-the-fact injector"). Where the encoder or
// the muxer cannot be told the layout from a module, the person is told before the start.
#include "marks.hpp"
#include "sei.h"

#include <obs-frontend-api.h>
#include <obs-module.h>
#include <util/config-file.h>

#include <atomic>
#include <cstring>
#include <set>
#include <string>

namespace SparkyStereo {

namespace {

// the encoders whose x264 options carry the token because this module put it there, by name
std::set<std::string> markedByUs;

bool hasToken(const std::string &options)
{
	size_t at = 0;
	const std::string token = kX264Token;
	while ((at = options.find(token, at)) != std::string::npos) {
		const bool startOk = at == 0 || options[at - 1] == ' ';
		const size_t end = at + token.size();
		const bool endOk = end == options.size() || options[end] == ' ';
		if (startOk && endOk)
			return true;
		at = end;
	}
	return false;
}

std::string withoutToken(std::string options)
{
	const std::string token = kX264Token;
	size_t at = 0;
	while ((at = options.find(token, at)) != std::string::npos) {
		const size_t end = at + token.size();
		if ((at == 0 || options[at - 1] == ' ') && (end == options.size() || options[end] == ' ')) {
			size_t from = at, to = end;
			if (to < options.size())
				to++;
			else if (from > 0)
				from--;
			options.erase(from, to - from);
		} else {
			at = end;
		}
	}
	return options;
}

bool updateX264(void *param, obs_encoder_t *encoder)
{
	const bool stereo = *static_cast<bool *>(param);
	if (obs_encoder_get_type(encoder) != OBS_ENCODER_VIDEO || strcmp(obs_encoder_get_id(encoder), "obs_x264") != 0)
		return true;
	video_t *video = obs_encoder_video(encoder);
	if (video && video != obs_get_video())
		return true; // another canvas
	if (obs_encoder_active(encoder))
		return true; // its options were read when it started
	const std::string name = obs_encoder_get_name(encoder) ? obs_encoder_get_name(encoder) : "";
	obs_data_t *settings = obs_encoder_get_settings(encoder);
	const std::string options = obs_data_get_string(settings, "x264opts");
	obs_data_release(settings);
	std::string next = options;
	if (stereo && !hasToken(options)) {
		next = options.empty() ? std::string(kX264Token) : options + " " + kX264Token;
		markedByUs.insert(name);
	} else if (!stereo && markedByUs.count(name)) {
		next = withoutToken(options);
		markedByUs.erase(name);
	}
	if (next != options) {
		obs_data_t *update = obs_data_create();
		obs_data_set_string(update, "x264opts", next.c_str());
		obs_encoder_update(encoder, update);
		obs_data_release(update);
		blog(LOG_INFO, "[sparky-stereo-obs] %s: x264 options \"%s\"", name.c_str(), next.c_str());
	}
	return true;
}

obs_output_t *outputOf(OutputKind kind)
{
	switch (kind) {
	case OutputKind::Stream:
		return obs_frontend_get_streaming_output();
	case OutputKind::Record:
		return obs_frontend_get_recording_output();
	case OutputKind::Replay:
		return obs_frontend_get_replay_buffer_output();
	}
	return nullptr;
}

std::string simpleEncoderId(const char *name)
{
	const std::string n = name ? name : "";
	if (n == "qsv")
		return "obs_qsv11_v2";
	if (n == "qsv_av1")
		return "obs_qsv11_av1";
	if (n == "amd")
		return "h264_texture_amf";
	if (n == "amd_hevc")
		return "h265_texture_amf";
	if (n == "amd_av1")
		return "av1_texture_amf";
	if (n == "nvenc")
		return obs_encoder_get_display_name("obs_nvenc_h264_tex") ? "obs_nvenc_h264_tex" : "ffmpeg_nvenc";
	if (n == "nvenc_hevc")
		return obs_encoder_get_display_name("obs_nvenc_hevc_tex") ? "obs_nvenc_hevc_tex" : "ffmpeg_hevc_nvenc";
	if (n == "nvenc_av1")
		return "obs_nvenc_av1_tex";
	return "obs_x264"; // x264, x264_lowcpu and the frontend's own default (SimpleOutput.cpp)
}

bool advancedMode(config_t *config)
{
	const char *mode = config_get_string(config, "Output", "Mode");
	return mode && strcmp(mode, "Advanced") == 0;
}

// the encoder the frontend will use, as frontend/utility/SimpleOutput.cpp and AdvancedOutput.cpp choose it
std::string predictedEncoder(OutputKind kind, bool *usesStreamEncoder)
{
	config_t *config = obs_frontend_get_profile_config();
	*usesStreamEncoder = kind == OutputKind::Stream;
	if (advancedMode(config)) {
		const char *stream = config_get_string(config, "AdvOut", "Encoder");
		if (kind == OutputKind::Stream)
			return stream ? stream : "";
		const char *type = config_get_string(config, "AdvOut", "RecType");
		if (type && strcmp(type, "FFmpeg") == 0)
			return "ffmpeg_output";
		const char *record = config_get_string(config, "AdvOut", "RecEncoder");
		if (!record || !*record || strcmp(record, "none") == 0) {
			*usesStreamEncoder = true;
			return stream ? stream : "";
		}
		return record;
	}
	const std::string stream = simpleEncoderId(config_get_string(config, "SimpleOutput", "StreamEncoder"));
	if (kind == OutputKind::Stream)
		return stream;
	const char *quality = config_get_string(config, "SimpleOutput", "RecQuality");
	if (quality && strcmp(quality, "Stream") == 0) {
		*usesStreamEncoder = true;
		return stream;
	}
	if (quality && strcmp(quality, "Lossless") == 0)
		return "ffmpeg_output";
	return simpleEncoderId(config_get_string(config, "SimpleOutput", "RecEncoder"));
}

// The person's own x264 options replace the encoder's whole option string at the start (SimpleOutput::Update with
// "Enable Advanced Encoder Settings"; AdvancedOutput reads streamEncoder.json and recordEncoder.json): what they hold
// decides. Returns false when the person has none.
bool ownX264Options(bool usesStreamEncoder, std::string *options)
{
	config_t *config = obs_frontend_get_profile_config();
	if (!advancedMode(config)) {
		if (!usesStreamEncoder || !config_get_bool(config, "SimpleOutput", "UseAdvanced"))
			return false;
		const char *custom = config_get_string(config, "SimpleOutput", "x264Settings");
		if (!custom || !*custom)
			return false;
		*options = custom;
		return true;
	}
	char *profile = obs_frontend_get_current_profile_path();
	if (!profile)
		return false;
	const std::string path = std::string(profile) + (usesStreamEncoder ? "/streamEncoder.json" : "/recordEncoder.json");
	bfree(profile);
	obs_data_t *data = obs_data_create_from_json_file_safe(path.c_str(), "bak");
	if (!data)
		return false;
	const bool has = obs_data_has_user_value(data, "x264opts") && *obs_data_get_string(data, "x264opts");
	if (has)
		*options = obs_data_get_string(data, "x264opts");
	obs_data_release(data);
	return has;
}

QString text(const char *key)
{
	return QString::fromUtf8(obs_module_text(key));
}

QString encoderName(const std::string &id)
{
	const char *name = obs_encoder_get_display_name(id.c_str());
	return QString::fromUtf8(name ? name : id.c_str());
}

// why an encoder of the shipped OBS (33.0.1) cannot be given the layout from a module, read at its source
const char *reasonFor(const std::string &id)
{
	if (id.find("av1") != std::string::npos)
		return "Reason.AV1";
	if (id.find("vaapi") != std::string::npos)
		return "Reason.VAAPI";
	if (id.find("nvenc") != std::string::npos)
		return "Reason.NVENC";
	if (id.rfind("obs_qsv11", 0) == 0)
		return "Reason.QSV";
	if (id.find("amf") != std::string::npos)
		return "Reason.AMF";
	if (id == "ffmpeg_openh264")
		return "Reason.OpenH264";
	if (id == "ffmpeg_output")
		return "Reason.CustomFFmpeg";
	return "Reason.Unknown";
}

struct Watch {
	obs_output_t *output = nullptr;
	std::atomic<bool> checked{false};
	OutputKind kind = OutputKind::Record;
};

Watch watches[3];

Watch *watchFor(OutputKind kind)
{
	switch (kind) {
	case OutputKind::Stream:
		return &watches[0];
	case OutputKind::Record:
		return &watches[1];
	case OutputKind::Replay:
		return &watches[2];
	}
	return nullptr;
}

void onPacket(obs_output_t *, struct encoder_packet *packet, struct encoder_packet_time *, void *param)
{
	auto *watch = static_cast<Watch *>(param);
	if (packet->type != OBS_ENCODER_VIDEO || !packet->keyframe || watch->checked.exchange(true))
		return;
	const char *codec = packet->encoder ? obs_encoder_get_codec(packet->encoder) : nullptr;
	const char *id = packet->encoder ? obs_encoder_get_id(packet->encoder) : "?";
	struct stereo_sei_packing packing = {};
	int found = 0;
	if (codec && (strcmp(codec, "h264") == 0 || strcmp(codec, "hevc") == 0))
		found = stereo_sei_find_packing(packet->data, packet->size,
						strcmp(codec, "h264") == 0 ? STEREO_SEI_H264 : STEREO_SEI_HEVC, &packing);
	if (found == 1 && !packing.cancel) {
		blog(LOG_INFO,
		     "[sparky-stereo-obs] %s: the first keyframe carries a frame packing arrangement, type %d, content "
		     "interpretation %d",
		     id, packing.type, packing.interpretation);
		return;
	}
	blog(LOG_WARNING, "[sparky-stereo-obs] %s (%s): the first keyframe carries no frame packing arrangement", id,
	     codec ? codec : "?");
	tell(text("Notice.NoStreamMark").arg(encoderName(id)));
}

} // namespace

void applyX264Mark(bool stereo)
{
	obs_enum_encoders(updateX264, &stereo);
}

MarkPlan planFor(OutputKind kind)
{
	MarkPlan plan;
	bool usesStreamEncoder = false;
	std::string id = predictedEncoder(kind, &usesStreamEncoder);
	if (obs_output_t *output = outputOf(kind)) {
		if (obs_encoder_t *encoder = obs_output_get_video_encoder(output))
			id = obs_encoder_get_id(encoder);
		obs_output_release(output);
	}
	plan.encoderId = QString::fromStdString(id);
	if (id == "obs_x264") {
		std::string own;
		if (ownX264Options(usesStreamEncoder, &own) && !hasToken(own)) {
			plan.missing << text("Reason.OwnX264").arg(QString::fromStdString(own));
		} else {
			plan.streamMarked = true;
		}
	} else {
		plan.missing << text(reasonFor(id)).arg(encoderName(id));
	}
	if (kind != OutputKind::Stream && plan.streamMarked)
		plan.missing << text("Reason.Container");
	return plan;
}

void watchOutput(OutputKind kind)
{
	Watch *found = watchFor(kind);
	if (!found || found->output)
		return;
	Watch &watch = *found;
	watch.output = outputOf(kind);
	if (!watch.output)
		return;
	watch.kind = kind;
	watch.checked = false;
	obs_output_add_packet_callback(watch.output, onPacket, &watch);
}

void unwatchOutput(OutputKind kind)
{
	Watch *found = watchFor(kind);
	if (!found || !found->output)
		return;
	Watch &watch = *found;
	obs_output_remove_packet_callback(watch.output, onPacket, &watch);
	obs_output_release(watch.output);
	watch.output = nullptr;
}

} // namespace SparkyStereo
