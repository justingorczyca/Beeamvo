#ifndef RUNNER_HOTKEY_PLUGIN_H_
#define RUNNER_HOTKEY_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <cstdint>
#include <map>
#include <memory>
#include <optional>
#include <string>

namespace beeamvo {

class HotkeyPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar,
                                    HWND window);
  HotkeyPlugin(flutter::PluginRegistrarWindows* registrar, HWND window);
  ~HotkeyPlugin() override;

 private:
  struct Binding {
    std::string identifier;
    UINT key;
    UINT modifiers;
    uint32_t generation;
    bool pressed = false;
  };

  static LRESULT CALLBACK KeyboardHook(int code, WPARAM message, LPARAM data);
  std::optional<LRESULT> HandleWindowMessage(UINT message, WPARAM wparam,
                                           LPARAM lparam);
  void HandleMethod(const flutter::MethodCall<flutter::EncodableValue>& call,
                    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Emit(const Binding& binding, const char* type);
  void UnregisterAll();
  void StopHookIfUnused();

  static HotkeyPlugin* instance_;
  flutter::PluginRegistrarWindows* registrar_;
  HWND window_;
  HHOOK hook_ = nullptr;
  int delegate_id_;
  int next_id_ = 0x4000;
  uint32_t next_generation_ = 1;
  std::map<int, Binding> bindings_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> events_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;
};

}

#endif
