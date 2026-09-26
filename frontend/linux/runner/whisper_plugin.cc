#include "whisper_plugin.h"

#include <flutter_linux/flutter_linux.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "whisper.h"

// ── Helper functions ─────────────────────────────────────────────────────────

static int count_physical_cores() {
  // On Linux, count unique physical core IDs from /proc/cpuinfo
  FILE* f = fopen("/proc/cpuinfo", "r");
  if (!f) return 0;

  std::vector<int> core_ids;
  char line[256];
  while (fgets(line, sizeof(line), f)) {
    int core_id;
    if (sscanf(line, "core id : %d", &core_id) == 1) {
      bool found = false;
      for (int id : core_ids) {
        if (id == core_id) { found = true; break; }
      }
      if (!found) core_ids.push_back(core_id);
    }
  }
  fclose(f);
  return static_cast<int>(core_ids.size());
}

static int choose_thread_count(int requested_threads) {
  const int logical = static_cast<int>(std::thread::hardware_concurrency());
  const int physical = count_physical_cores();
  const int recommended =
      std::max(1, std::min(physical > 0 ? physical : std::max(1, logical / 2), 8));

  if (requested_threads > 0) {
    return std::max(1, std::min(requested_threads, std::max(1, logical)));
  }
  return recommended;
}

static int choose_audio_context(int sample_count, int sample_rate) {
  if (sample_count <= 0 || sample_rate <= 0) return 0;

  const float audio_seconds =
      static_cast<float>(sample_count) / static_cast<float>(sample_rate);
  if (audio_seconds >= 30.0f) return 0;

  const int ctx_frames = static_cast<int>(
      std::ceil(audio_seconds / 30.0f * 1500.0f / 64.0f)) * 64;
  return std::clamp(ctx_frames, 768, 1500);
}

// ── Plugin state ─────────────────────────────────────────────────────────────

struct WhisperPluginState {
  whisper_context* ctx = nullptr;
  std::string model_path;
  int n_threads = 0;
  bool gpu_enabled = false;
  bool flash_attn_enabled = false;
  std::mutex ctx_mutex;
  std::atomic<bool> busy{false};
  std::atomic<bool> cancel_requested{false};
};

static WhisperPluginState* g_state = nullptr;

static bool abort_callback(void* user_data) {
  if (!user_data) return false;
  auto* state = static_cast<WhisperPluginState*>(user_data);
  return state->cancel_requested.load();
}

static void free_context(WhisperPluginState* state) {
  std::lock_guard<std::mutex> lock(state->ctx_mutex);
  if (state->ctx) {
    whisper_free(state->ctx);
    state->ctx = nullptr;
    state->model_path.clear();
    g_message("[Whisper] Context freed");
  }
}

static bool initialize_context(WhisperPluginState* state,
                                const std::string& model_path,
                                int threads) {
  std::lock_guard<std::mutex> lock(state->ctx_mutex);

  if (state->ctx) {
    if (state->model_path == model_path) {
      g_message("[Whisper] Already initialized, reusing context");
      return true;
    }
    g_message("[Whisper] Model path changed, reloading context");
    whisper_free(state->ctx);
    state->ctx = nullptr;
    state->model_path.clear();
  }

  state->n_threads = choose_thread_count(threads);
  g_message("[Whisper] Using %d threads", state->n_threads);

  whisper_context_params cparams = whisper_context_default_params();
  cparams.use_gpu = true;
#ifdef GGML_USE_CUDA
  state->flash_attn_enabled = true;
#else
  state->flash_attn_enabled = false;
#endif
  cparams.flash_attn = state->flash_attn_enabled;
  state->gpu_enabled = cparams.use_gpu;

  g_message("[Whisper] Loading model from: %s", model_path.c_str());
  state->ctx = whisper_init_from_file_with_params(model_path.c_str(), cparams);

  if (state->ctx) {
    state->model_path = model_path;
    g_message("[Whisper] Model loaded successfully");
  } else {
    g_warning("[Whisper] FAILED to load model!");
  }

  return state->ctx != nullptr;
}

static std::string transcribe_pcm(WhisperPluginState* state,
                                   const std::vector<float>& samples,
                                   int sample_rate,
                                   const std::string& language) {
  std::lock_guard<std::mutex> lock(state->ctx_mutex);

  if (!state->ctx || samples.empty()) {
    g_message("[Whisper] TranscribePcm: no context or empty samples");
    return "";
  }

  whisper_full_params wparams =
      whisper_full_default_params(WHISPER_SAMPLING_GREEDY);

  wparams.n_threads = std::max(1, state->n_threads);
  wparams.n_max_text_ctx = 0;
  wparams.no_context = true;
  wparams.no_timestamps = true;
  wparams.single_segment = true;
  wparams.max_tokens = 0;

  if (language == "auto") {
    wparams.language = "auto";
  } else {
    wparams.language = language.c_str();
  }
  wparams.detect_language = false;

  wparams.print_progress = false;
  wparams.print_special = false;
  wparams.print_realtime = false;
  wparams.print_timestamps = false;
  wparams.token_timestamps = false;
  wparams.suppress_blank = true;
  wparams.suppress_nst = true;
  wparams.abort_callback = abort_callback;
  wparams.abort_callback_user_data = state;

  wparams.audio_ctx =
      choose_audio_context(static_cast<int>(samples.size()), sample_rate);

  g_message("[Whisper] Running inference on %zu float samples...", samples.size());

  const int ret = whisper_full(state->ctx, wparams, samples.data(),
                                static_cast<int>(samples.size()));
  if (ret != 0) {
    if (state->cancel_requested) {
      g_message("[Whisper] Transcription cancelled");
    } else {
      g_warning("[Whisper] whisper_full returned error: %d", ret);
    }
    return "";
  }

  const int n_segments = whisper_full_n_segments(state->ctx);
  g_message("[Whisper] Got %d segments", n_segments);

  std::string result;
  for (int i = 0; i < n_segments; ++i) {
    const char* text = whisper_full_get_segment_text(state->ctx, i);
    if (text) {
      if (!result.empty()) result += " ";
      result += text;
    }
  }

  return result;
}

// ── Method call handler ──────────────────────────────────────────────────────

static void handle_method_call(FlMethodChannel* channel,
                                FlMethodCall* method_call,
                                gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (g_strcmp0(method, "init") == 0) {
    FlValue* model_path_val = fl_value_lookup_string(args, "modelPath");
    if (model_path_val == nullptr) {
      g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
          fl_method_error_response_new("invalid_args", "Missing modelPath", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    const char* model_path = fl_value_get_string(model_path_val);

    int threads = 0;
    FlValue* threads_val = fl_value_lookup_string(args, "threads");
    if (threads_val != nullptr) {
      threads = static_cast<int>(fl_value_get_int(threads_val));
    }

    const bool ok = initialize_context(g_state, model_path, threads);
    g_autoptr(FlValue) result = fl_value_new_bool(ok);
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    fl_method_call_respond(method_call, response, nullptr);

  } else if (g_strcmp0(method, "transcribeRaw") == 0) {
    if (g_state->busy.exchange(true)) {
      g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
          fl_method_error_response_new("busy", "Transcription already in progress", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    g_state->cancel_requested = false;

    FlValue* pcm_val = fl_value_lookup_string(args, "pcmBytes");
    if (pcm_val == nullptr) {
      g_state->busy = false;
      g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
          fl_method_error_response_new("invalid_args", "Missing pcmBytes", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    const uint8_t* pcm_data = fl_value_get_uint8_list(pcm_val);
    size_t pcm_len = fl_value_get_length(pcm_val);

    int sample_rate = 16000;
    FlValue* sr_val = fl_value_lookup_string(args, "sampleRate");
    if (sr_val != nullptr) {
      sample_rate = static_cast<int>(fl_value_get_int(sr_val));
    }

    int channels = 1;
    FlValue* ch_val = fl_value_lookup_string(args, "channels");
    if (ch_val != nullptr) {
      channels = static_cast<int>(fl_value_get_int(ch_val));
    }

    std::string language = "auto";
    FlValue* lang_val = fl_value_lookup_string(args, "language");
    if (lang_val != nullptr) {
      language = fl_value_get_string(lang_val);
    }

    {
      std::lock_guard<std::mutex> lock(g_state->ctx_mutex);
      if (!g_state->ctx) {
        g_state->busy = false;
        g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
            fl_method_error_response_new("not_initialized",
                                          "Whisper context not initialized", nullptr));
        fl_method_call_respond(method_call, response, nullptr);
        return;
      }
    }

    // Convert PCM16LE to float samples
    const size_t num_samples = pcm_len / 2 / channels;
    const size_t frame_stride = static_cast<size_t>(channels) * 2;
    std::vector<float> samples(num_samples);
    for (size_t i = 0; i < num_samples; ++i) {
      const size_t offset = i * frame_stride;
      const uint16_t lo = pcm_data[offset];
      const uint16_t hi = pcm_data[offset + 1];
      const int16_t sample = static_cast<int16_t>((hi << 8) | lo);
      samples[i] = static_cast<float>(sample) / 32768.0f;
    }

    std::string text = transcribe_pcm(g_state, samples, sample_rate, language);

    g_state->busy = false;
    g_autoptr(FlValue) result = fl_value_new_string(text.c_str());
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    fl_method_call_respond(method_call, response, nullptr);

  } else if (g_strcmp0(method, "cleanup") == 0) {
    free_context(g_state);
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, nullptr);

  } else if (g_strcmp0(method, "cancel") == 0) {
    g_state->cancel_requested = true;
    g_autoptr(FlValue) result = fl_value_new_bool(true);
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    fl_method_call_respond(method_call, response, nullptr);

  } else {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, response, nullptr);
  }
}

// ── Plugin registration ──────────────────────────────────────────────────────

void beeamvo_whisper_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  if (!g_state) {
    g_state = new WhisperPluginState();
  }

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "com.beeamvo/whisper",
      FL_METHOD_CODEC(codec));

  fl_method_channel_set_method_call_handler(
      channel, handle_method_call, g_state, nullptr);
}
