#include "hotkey_plugin.h"

#include <flutter/standard_method_codec.h>
#include <flutter/event_stream_handler_functions.h>

namespace beeamvo {
namespace {
constexpr UINT kReleased = WM_APP + 0x371;

UINT ModifierForKey(DWORD key) {
  switch (key) {
    case VK_CONTROL: case VK_LCONTROL: case VK_RCONTROL: return MOD_CONTROL;
    case VK_SHIFT: case VK_LSHIFT: case VK_RSHIFT: return MOD_SHIFT;
    case VK_MENU: case VK_LMENU: case VK_RMENU: return MOD_ALT;
    case VK_LWIN: case VK_RWIN: return MOD_WIN;
    default: return 0;
  }
}
}

HotkeyPlugin* HotkeyPlugin::instance_ = nullptr;

void HotkeyPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar,
                                         HWND window) {
  registrar->AddPlugin(std::make_unique<HotkeyPlugin>(registrar, window));
}

HotkeyPlugin::HotkeyPlugin(flutter::PluginRegistrarWindows* registrar, HWND window)
    : registrar_(registrar), window_(window) {
  instance_ = this;
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "dev.leanflutter.plugins/hotkey_manager",
      &flutter::StandardMethodCodec::GetInstance());
  events_ = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      registrar->messenger(), "dev.leanflutter.plugins/hotkey_manager_event",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethod(call, std::move(result));
  });
  events_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [this](const auto*, auto sink) -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            sink_ = std::move(sink);
            return nullptr;
          },
          [this](const auto*) -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            sink_.reset();
            UnregisterAll();
            return nullptr;
          }));
  delegate_id_ = registrar->RegisterTopLevelWindowProcDelegate(
      [this](HWND, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowMessage(message, wparam, lparam);
      });
}

HotkeyPlugin::~HotkeyPlugin() {
  UnregisterAll();
  instance_ = nullptr;
  registrar_->UnregisterTopLevelWindowProcDelegate(delegate_id_);
}

void HotkeyPlugin::StopHookIfUnused() {
  if (bindings_.empty() && hook_) {
    UnhookWindowsHookEx(hook_);
    hook_ = nullptr;
  }
}

void HotkeyPlugin::UnregisterAll() {
  for (const auto& entry : bindings_) UnregisterHotKey(window_, entry.first);
  bindings_.clear();
  StopHookIfUnused();
}

void HotkeyPlugin::Emit(const Binding& binding, const char* type) {
  if (!sink_) return;
  sink_->Success(flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("type"), flutter::EncodableValue(type)},
      {flutter::EncodableValue("data"), flutter::EncodableValue(flutter::EncodableMap{
          {flutter::EncodableValue("identifier"), flutter::EncodableValue(binding.identifier)}})}}));
}

LRESULT CALLBACK HotkeyPlugin::KeyboardHook(int code, WPARAM message, LPARAM data) {
  if (code == HC_ACTION && instance_ &&
      (message == WM_KEYUP || message == WM_SYSKEYUP)) {
    const auto* event = reinterpret_cast<const KBDLLHOOKSTRUCT*>(data);
    if (!(event->flags & LLKHF_INJECTED)) {
      for (auto& entry : instance_->bindings_) {
        auto& binding = entry.second;
        if (binding.pressed && (binding.key == event->vkCode ||
            (binding.modifiers & ModifierForKey(event->vkCode)))) {
          binding.pressed = false;
          PostMessage(instance_->window_, kReleased, static_cast<WPARAM>(entry.first),
                      static_cast<LPARAM>(binding.generation));
        }
      }
    }
  }
  return CallNextHookEx(nullptr, code, message, data);
}

std::optional<LRESULT> HotkeyPlugin::HandleWindowMessage(
    UINT message, WPARAM wparam, LPARAM lparam) {
  if (message != WM_HOTKEY && message != kReleased) return std::nullopt;
  const auto it = bindings_.find(static_cast<int>(wparam));
  if (it == bindings_.end()) return std::nullopt;
  auto& binding = it->second;
  if (message == kReleased) {
    if (binding.generation != static_cast<uint32_t>(lparam)) return 0;
    Emit(binding, "onKeyUp");
  } else if (!binding.pressed) {
    binding.pressed = true;
    Emit(binding, "onKeyDown");
    if (!(GetAsyncKeyState(static_cast<int>(binding.key)) & 0x8000)) {
      binding.pressed = false;
      Emit(binding, "onKeyUp");
    }
  }
  return 0;
}

void HotkeyPlugin::HandleMethod(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "unregisterAll") {
    UnregisterAll();
    result->Success();
    return;
  }
  const auto* args = call.arguments()
      ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
  if (!args) {
    result->Error("invalid_arguments", "Missing hotkey configuration.");
    return;
  }
  const auto identifier_it = args->find(flutter::EncodableValue("identifier"));
  const auto* identifier = identifier_it != args->end()
      ? std::get_if<std::string>(&identifier_it->second) : nullptr;
  if (!identifier) {
    result->Error("invalid_arguments", "Missing hotkey identifier.");
    return;
  }
  if (call.method_name() == "unregister") {
    for (auto it = bindings_.begin(); it != bindings_.end(); ++it) {
      if (it->second.identifier == *identifier) {
        UnregisterHotKey(window_, it->first);
        bindings_.erase(it);
        break;
      }
    }
    StopHookIfUnused();
    result->Success();
    return;
  }
  if (call.method_name() != "register") {
    result->NotImplemented();
    return;
  }
  const auto key_it = args->find(flutter::EncodableValue("keyCode"));
  const auto* key = key_it != args->end()
      ? std::get_if<int32_t>(&key_it->second) : nullptr;
  if (!key || *key < 1 || *key > 255) {
    result->Error("invalid_arguments", "Invalid hotkey key code.");
    return;
  }
  UINT modifiers = 0;
  const auto mods_it = args->find(flutter::EncodableValue("modifiers"));
  const auto* mods = mods_it != args->end()
      ? std::get_if<flutter::EncodableList>(&mods_it->second) : nullptr;
  if (mods) {
    for (const auto& value : *mods) {
      const auto* name = std::get_if<std::string>(&value);
      if (!name) continue;
      if (*name == "control") modifiers |= MOD_CONTROL;
      if (*name == "shift") modifiers |= MOD_SHIFT;
      if (*name == "alt") modifiers |= MOD_ALT;
      if (*name == "meta") modifiers |= MOD_WIN;
    }
  }
  if (!hook_) hook_ = SetWindowsHookEx(WH_KEYBOARD_LL, KeyboardHook, GetModuleHandle(nullptr), 0);
  if (!hook_) {
    result->Error("hotkey_hook_failed", "Could not listen for hotkey release.");
    return;
  }
  const int first_id = next_id_;
  while (bindings_.count(next_id_)) {
    next_id_ = next_id_ == 0xBFFF ? 0x4000 : next_id_ + 1;
    if (next_id_ == first_id) {
      result->Error("hotkey_unavailable", "Too many registered shortcuts.");
      return;
    }
  }
  const int id = next_id_;
  next_id_ = next_id_ == 0xBFFF ? 0x4000 : next_id_ + 1;
  if (!RegisterHotKey(window_, id, modifiers | MOD_NOREPEAT, static_cast<UINT>(*key))) {
    StopHookIfUnused();
    result->Error("hotkey_unavailable", "The shortcut is already registered or unavailable.");
    return;
  }
  bindings_.emplace(id, Binding{*identifier, static_cast<UINT>(*key), modifiers, next_generation_++});
  result->Success();
}

}
