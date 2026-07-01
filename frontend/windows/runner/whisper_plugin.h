#ifndef WHISPER_PLUGIN_H_
#define WHISPER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <memory>
#include <string>
#include <mutex>
#include <atomic>
#include <vector>

// Forward declarations from whisper.cpp
struct whisper_context;
struct whisper_full_params;

namespace beeamvo {

/// WhisperPlugin integrates whisper.cpp for offline speech-to-text.
/// Uses MethodChannel "com.beeamvo/whisper" for Dart communication.
class WhisperPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  WhisperPlugin();
  ~WhisperPlugin() override;

  // Disallow copy and assign
  WhisperPlugin(const WhisperPlugin&) = delete;
  WhisperPlugin& operator=(const WhisperPlugin&) = delete;

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  whisper_context* ctx_;
  std::string model_path_;
  int n_threads_;
  bool gpu_enabled_;
  bool flash_attn_enabled_;
  std::mutex ctx_mutex_;
  std::atomic<bool> busy_;
  std::atomic<bool> cancel_requested_;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void HandleInit(const flutter::EncodableMap* args,
                  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void HandleTranscribeRaw(const flutter::EncodableMap* args,
                           std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void HandleCleanup(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandleCancel(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  bool InitializeContext(const std::string& model_path, int threads);
  std::string TranscribePcm(const std::vector<float>& samples,
                            int sample_rate,
                            const std::string& language);
  void FreeContext();
  static bool AbortCallback(void* user_data);
};

}  // namespace beeamvo

#endif  // WHISPER_PLUGIN_H_
