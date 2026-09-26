#include "whisper_plugin.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <thread>
#include <vector>

#include "whisper.h"

namespace beeamvo {

namespace {

int CountPhysicalCores() {
  DWORD len = 0;
  GetLogicalProcessorInformationEx(RelationProcessorCore, nullptr, &len);
  if (len == 0) {
    return 0;
  }

  std::vector<uint8_t> buffer(len);
  if (!GetLogicalProcessorInformationEx(
          RelationProcessorCore,
          reinterpret_cast<SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX*>(
              buffer.data()),
          &len)) {
    return 0;
  }

  int physical_cores = 0;
  size_t offset = 0;
  while (offset < len) {
    auto* entry = reinterpret_cast<SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX*>(
        buffer.data() + offset);
    if (entry->Relationship == RelationProcessorCore) {
      ++physical_cores;
    }
    offset += entry->Size;
  }

  return physical_cores;
}

int ChooseThreadCount(int requested_threads) {
  const int logical = static_cast<int>(std::thread::hardware_concurrency());
  const int physical = CountPhysicalCores();
  const int recommended =
      std::max(1, std::min(physical > 0 ? physical : std::max(1, logical / 2), 8));

  if (requested_threads > 0) {
    return std::max(1, std::min(requested_threads, std::max(1, logical)));
  }

  return recommended;
}

int ChooseAudioContext(int sample_count, int sample_rate) {
  if (sample_count <= 0 || sample_rate <= 0) {
    return 0;
  }

  const float audio_seconds =
      static_cast<float>(sample_count) / static_cast<float>(sample_rate);
  if (audio_seconds >= 30.0f) {
    return 0;
  }

  const int ctx_frames = static_cast<int>(
      std::ceil(audio_seconds / 30.0f * 1500.0f / 64.0f)) * 64;
  return std::clamp(ctx_frames, 768, 1500);
}

}  // namespace

void WhisperPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "com.beeamvo/whisper",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<WhisperPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

WhisperPlugin::WhisperPlugin()
    : ctx_(nullptr),
      n_threads_(0),
      gpu_enabled_(false),
      flash_attn_enabled_(false),
      busy_(false),
      cancel_requested_(false) {}

WhisperPlugin::~WhisperPlugin() {
  FreeContext();
}

void WhisperPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = method_call.method_name();

  if (method == "init") {
    const auto* args =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    HandleInit(args, std::move(result));
  } else if (method == "transcribeRaw") {
    const auto* args =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    HandleTranscribeRaw(args, std::move(result));
  } else if (method == "cleanup") {
    HandleCleanup(std::move(result));
  } else if (method == "cancel") {
    HandleCancel(std::move(result));
  } else {
    result->NotImplemented();
  }
}

void WhisperPlugin::HandleInit(
    const flutter::EncodableMap* args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!args) {
    result->Error("invalid_args", "Missing arguments");
    return;
  }

  auto model_path_it = args->find(flutter::EncodableValue("modelPath"));
  if (model_path_it == args->end()) {
    result->Error("invalid_args", "Missing modelPath");
    return;
  }
  const std::string& model_path = std::get<std::string>(model_path_it->second);

  int threads = 0;
  auto threads_it = args->find(flutter::EncodableValue("threads"));
  if (threads_it != args->end()) {
    threads = static_cast<int>(std::get<int32_t>(threads_it->second));
  }

  OutputDebugStringA(("[Whisper] Init with model: " + model_path + "\n").c_str());
  const bool ok = InitializeContext(model_path, threads);
  OutputDebugStringA(ok ? "[Whisper] Init OK\n" : "[Whisper] Init FAILED\n");
  result->Success(flutter::EncodableValue(ok));
}

void WhisperPlugin::HandleTranscribeRaw(
    const flutter::EncodableMap* args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!args) {
    result->Error("invalid_args", "Missing arguments");
    return;
  }

  if (busy_.exchange(true)) {
    result->Error("busy", "Transcription already in progress");
    return;
  }
  cancel_requested_ = false;

  auto pcm_it = args->find(flutter::EncodableValue("pcmBytes"));
  if (pcm_it == args->end()) {
    busy_ = false;
    result->Error("invalid_args", "Missing pcmBytes");
    return;
  }
  const std::vector<uint8_t>& pcm_bytes =
      std::get<std::vector<uint8_t>>(pcm_it->second);

  int sample_rate = 16000;
  auto sr_it = args->find(flutter::EncodableValue("sampleRate"));
  if (sr_it != args->end()) {
    sample_rate = static_cast<int>(std::get<int32_t>(sr_it->second));
  }

  int channels = 1;
  auto ch_it = args->find(flutter::EncodableValue("channels"));
  if (ch_it != args->end()) {
    channels = static_cast<int>(std::get<int32_t>(ch_it->second));
  }
  if (channels <= 0) {
    busy_ = false;
    result->Error("invalid_args", "channels must be > 0");
    return;
  }

  std::string language = "auto";
  auto lang_it = args->find(flutter::EncodableValue("language"));
  if (lang_it != args->end()) {
    language = std::get<std::string>(lang_it->second);
  }

  {
    std::lock_guard<std::mutex> lock(ctx_mutex_);
    if (!ctx_) {
      busy_ = false;
      OutputDebugStringA("[Whisper] TranscribeRaw: context is null!\n");
      result->Error("not_initialized", "Whisper context not initialized");
      return;
    }
  }

  const size_t num_samples = pcm_bytes.size() / 2 / channels;
  const size_t frame_stride = static_cast<size_t>(channels) * 2;
  std::vector<float> samples(num_samples);
  for (size_t i = 0; i < num_samples; ++i) {
    const size_t offset = i * frame_stride;
    const uint16_t lo = pcm_bytes[offset];
    const uint16_t hi = pcm_bytes[offset + 1];
    const int16_t sample = static_cast<int16_t>((hi << 8) | lo);
    samples[i] = static_cast<float>(sample) / 32768.0f;
  }

  OutputDebugStringA(("[Whisper] Transcribing " + std::to_string(samples.size()) +
                      " samples, sr=" + std::to_string(sample_rate) +
                      ", ch=" + std::to_string(channels) +
                      ", lang=" + language + "\n").c_str());

  std::string text = TranscribePcm(samples, sample_rate, language);

  OutputDebugStringA(("[Whisper] Transcription completed, characters=" +
                      std::to_string(text.size()) + "\n").c_str());

  busy_ = false;
  result->Success(flutter::EncodableValue(text));
}

void WhisperPlugin::HandleCleanup(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  FreeContext();
  result->Success(nullptr);
}

void WhisperPlugin::HandleCancel(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  cancel_requested_ = true;
  result->Success(flutter::EncodableValue(true));
}

bool WhisperPlugin::InitializeContext(const std::string& model_path,
                                      int threads) {
  std::lock_guard<std::mutex> lock(ctx_mutex_);

  if (ctx_) {
    if (model_path_ == model_path) {
      OutputDebugStringA("[Whisper] Already initialized, reusing context\n");
      return true;
    }

    OutputDebugStringA("[Whisper] Model path changed, reloading context\n");
    whisper_free(ctx_);
    ctx_ = nullptr;
    model_path_.clear();
  }

  const int physical = CountPhysicalCores();
  const int logical = static_cast<int>(std::thread::hardware_concurrency());
  n_threads_ = ChooseThreadCount(threads);
  OutputDebugStringA(("[Whisper] Using " + std::to_string(n_threads_) +
                      " threads (physical=" + std::to_string(physical) +
                      ", logical=" + std::to_string(logical) + ")\n").c_str());

  whisper_context_params cparams = whisper_context_default_params();
  cparams.use_gpu = true;
#ifdef GGML_USE_CUDA
  flash_attn_enabled_ = true;
#else
  flash_attn_enabled_ = false;
#endif
  cparams.flash_attn = flash_attn_enabled_;
  gpu_enabled_ = cparams.use_gpu;

  OutputDebugStringA(("[Whisper] GPU requested=" +
                      std::string(gpu_enabled_ ? "true" : "false") +
                      ", flash_attn=" +
                      std::string(flash_attn_enabled_ ? "true" : "false") +
                      "\n").c_str());

  OutputDebugStringA(("[Whisper] Loading model from: " + model_path + "\n").c_str());
  ctx_ = whisper_init_from_file_with_params(model_path.c_str(), cparams);

  if (ctx_) {
    model_path_ = model_path;
    OutputDebugStringA("[Whisper] Model loaded successfully\n");
  } else {
    OutputDebugStringA("[Whisper] FAILED to load model!\n");
  }

  return ctx_ != nullptr;
}

std::string WhisperPlugin::TranscribePcm(const std::vector<float>& samples,
                                         int sample_rate,
                                         const std::string& language) {
  std::lock_guard<std::mutex> lock(ctx_mutex_);

  if (!ctx_ || samples.empty()) {
    OutputDebugStringA("[Whisper] TranscribePcm: no context or empty samples\n");
    return "";
  }

  whisper_full_params wparams =
      whisper_full_default_params(WHISPER_SAMPLING_GREEDY);

  wparams.n_threads = std::max(1, n_threads_);
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
  wparams.abort_callback = AbortCallback;
  wparams.abort_callback_user_data = this;

  wparams.audio_ctx =
      ChooseAudioContext(static_cast<int>(samples.size()), sample_rate);
  const float audio_seconds = static_cast<float>(samples.size()) /
                              static_cast<float>(std::max(1, sample_rate));
  OutputDebugStringA(("[Whisper] audio_ctx=" + std::to_string(wparams.audio_ctx) +
                      ", max_tokens=" + std::to_string(wparams.max_tokens) +
                      " for " + std::to_string(audio_seconds) + "s audio\n")
                         .c_str());

  OutputDebugStringA(("[Whisper] Running inference on " +
                      std::to_string(samples.size()) + " float samples...\n")
                         .c_str());

  const int ret = whisper_full(ctx_, wparams, samples.data(),
                               static_cast<int>(samples.size()));
  if (ret != 0) {
    if (cancel_requested_) {
      OutputDebugStringA("[Whisper] Transcription cancelled\n");
    } else {
      OutputDebugStringA(("[Whisper] whisper_full returned error: " +
                          std::to_string(ret) + "\n").c_str());
    }
    return "";
  }

  const int n_segments = whisper_full_n_segments(ctx_);
  OutputDebugStringA(
      ("[Whisper] Got " + std::to_string(n_segments) + " segments\n").c_str());

  std::string result;
  for (int i = 0; i < n_segments; ++i) {
    const char* text = whisper_full_get_segment_text(ctx_, i);
    if (text) {
      if (!result.empty()) {
        result += " ";
      }
      result += text;
    }
  }

  return result;
}

void WhisperPlugin::FreeContext() {
  std::lock_guard<std::mutex> lock(ctx_mutex_);
  if (ctx_) {
    whisper_free(ctx_);
    ctx_ = nullptr;
    model_path_.clear();
    OutputDebugStringA("[Whisper] Context freed\n");
  }
}

bool WhisperPlugin::AbortCallback(void* user_data) {
  if (!user_data) {
    return false;
  }

  auto* plugin = static_cast<WhisperPlugin*>(user_data);
  return plugin->cancel_requested_.load();
}

}  // namespace beeamvo
