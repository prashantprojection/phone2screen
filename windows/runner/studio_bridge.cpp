#include "studio_bridge.h"

#include <flutter/standard_method_codec.h>

#include <cctype>
#include <cstring>
#include <initializer_list>
#include <string>
#include <utility>

#pragma warning(push, 3)
#include <dshow.h>
#include <mmsystem.h>
#include <objbase.h>
#include <oleauto.h>
#pragma warning(pop)

namespace {

std::string WideToUtf8(const wchar_t* wide) {
  if (wide == nullptr || wide[0] == L'\0') return {};
  const int wlen = static_cast<int>(::wcslen(wide));
  const int needed = ::WideCharToMultiByte(
      CP_UTF8, 0, wide, wlen, nullptr, 0, nullptr, nullptr);
  if (needed <= 0) return {};
  std::string out(static_cast<size_t>(needed), '\0');
  const int written = ::WideCharToMultiByte(
      CP_UTF8, 0, wide, wlen, out.data(), needed, nullptr, nullptr);
  return written > 0 ? out : std::string();
}

bool ContainsAnyToken(const std::string& text,
                      std::initializer_list<const char*> tokens) {
  std::string lower = text;
  for (char& ch : lower) {
    ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
  }
  for (const char* token : tokens) {
    if (lower.find(token) != std::string::npos) return true;
  }
  return false;
}

bool IsVirtualCamName(const std::string& name) {
  return ContainsAnyToken(name, {"obs", "virtual", "unitycapture", "droidcam",
                                 "iriun", "camo", "ndi", "elgato", "xsplit"});
}

bool IsVirtualCableName(const std::string& name) {
  return ContainsAnyToken(name, {"vb-audio", "cable", "voicemeeter",
                                 "wave link", "sonar", "virtual audio"});
}

std::string ReadPropertyString(IPropertyBag* prop_bag, const wchar_t* key) {
  VARIANT var;
  ::VariantInit(&var);
  std::string value;
  if (SUCCEEDED(prop_bag->Read(key, &var, nullptr)) && var.vt == VT_BSTR &&
      var.bstrVal != nullptr) {
    value = WideToUtf8(var.bstrVal);
  }
  ::VariantClear(&var);
  return value;
}

bool TryExtractEnabledArg(const flutter::EncodableValue* args, bool* out) {
  if (args == nullptr || out == nullptr) return false;
  if (const auto* direct = std::get_if<bool>(args)) {
    *out = *direct;
    return true;
  }
  if (const auto* map = std::get_if<flutter::EncodableMap>(args)) {
    const auto it = map->find(flutter::EncodableValue("enabled"));
    if (it != map->end()) {
      if (const auto* enabled = std::get_if<bool>(&it->second)) {
        *out = *enabled;
        return true;
      }
    }
  }
  return false;
}

}  // namespace

StudioBridge::StudioBridge(flutter::BinaryMessenger* messenger, HWND hwnd)
    : hwnd_(hwnd) {
  if (messenger == nullptr) return;
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "phone2screen/windows_studio",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleMethodCall(call, std::move(result)); });
}

StudioBridge::~StudioBridge() {
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
    channel_.reset();
  }
}

void StudioBridge::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "listVideoCaptureDevices") {
    result->Success(ListVideoCaptureDevices());
    return;
  }
  if (method == "listAudioOutputDevices") {
    result->Success(ListAudioOutputDevices());
    return;
  }
  if (method == "setAlwaysOnTop") {
    bool enabled = false;
    if (!TryExtractEnabledArg(call.arguments(), &enabled)) {
      result->Error("INVALID_ARGS", "Expected bool or {enabled: bool}");
      return;
    }
    result->Success(flutter::EncodableValue(SetAlwaysOnTop(enabled)));
    return;
  }
  if (method == "getAlwaysOnTop") {
    result->Success(flutter::EncodableValue(GetAlwaysOnTop()));
    return;
  }
  result->NotImplemented();
}

flutter::EncodableValue StudioBridge::ListVideoCaptureDevices() const {
  flutter::EncodableList devices;
  // Call CoUninitialize only when CoInitializeEx succeeded on this thread.
  const HRESULT co_hr = ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool should_uninit = SUCCEEDED(co_hr);
  if (FAILED(co_hr) && co_hr != RPC_E_CHANGED_MODE) {
    return flutter::EncodableValue(std::move(devices));
  }

  ICreateDevEnum* dev_enum = nullptr;
  HRESULT hr = ::CoCreateInstance(
      CLSID_SystemDeviceEnum, nullptr, CLSCTX_INPROC_SERVER, IID_ICreateDevEnum,
      reinterpret_cast<void**>(&dev_enum));
  if (SUCCEEDED(hr) && dev_enum != nullptr) {
    IEnumMoniker* enum_moniker = nullptr;
    hr = dev_enum->CreateClassEnumerator(CLSID_VideoInputDeviceCategory,
                                         &enum_moniker, 0);
    if (hr == S_OK && enum_moniker != nullptr) {
      IMoniker* moniker = nullptr;
      while (enum_moniker->Next(1, &moniker, nullptr) == S_OK &&
             moniker != nullptr) {
        IPropertyBag* prop_bag = nullptr;
        if (SUCCEEDED(moniker->BindToStorage(
                nullptr, nullptr, IID_IPropertyBag,
                reinterpret_cast<void**>(&prop_bag))) &&
            prop_bag != nullptr) {
          const std::string name = ReadPropertyString(prop_bag, L"FriendlyName");
          if (!name.empty()) {
            const std::string path = ReadPropertyString(prop_bag, L"DevicePath");
            flutter::EncodableMap entry;
            entry[flutter::EncodableValue("name")] =
                flutter::EncodableValue(name);
            entry[flutter::EncodableValue("devicePath")] =
                flutter::EncodableValue(path);
            entry[flutter::EncodableValue("isVirtualCam")] =
                flutter::EncodableValue(IsVirtualCamName(name));
            devices.push_back(flutter::EncodableValue(std::move(entry)));
          }
          prop_bag->Release();
        }
        moniker->Release();
        moniker = nullptr;
      }
      enum_moniker->Release();
    }
    dev_enum->Release();
  }
  if (should_uninit) ::CoUninitialize();
  return flutter::EncodableValue(std::move(devices));
}

flutter::EncodableValue StudioBridge::ListAudioOutputDevices() const {
  flutter::EncodableList devices;
  const UINT count = ::waveOutGetNumDevs();
  for (UINT i = 0; i < count; ++i) {
    WAVEOUTCAPSW caps{};
    if (::waveOutGetDevCapsW(i, &caps, sizeof(caps)) != MMSYSERR_NOERROR) {
      continue;
    }
    caps.szPname[MAXPNAMELEN - 1] = L'\0';
    const std::string name = WideToUtf8(caps.szPname);
    if (name.empty()) continue;
    flutter::EncodableMap entry;
    entry[flutter::EncodableValue("id")] =
        flutter::EncodableValue(std::to_string(i));
    entry[flutter::EncodableValue("name")] = flutter::EncodableValue(name);
    entry[flutter::EncodableValue("isVirtualCable")] =
        flutter::EncodableValue(IsVirtualCableName(name));
    devices.push_back(flutter::EncodableValue(std::move(entry)));
  }
  return flutter::EncodableValue(std::move(devices));
}

bool StudioBridge::SetAlwaysOnTop(bool enabled) const {
  if (hwnd_ == nullptr || !::IsWindow(hwnd_)) return false;
  const BOOL ok = ::SetWindowPos(
      hwnd_, enabled ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  return ok != FALSE;
}

bool StudioBridge::GetAlwaysOnTop() const {
  if (hwnd_ == nullptr || !::IsWindow(hwnd_)) return false;
  return (::GetWindowLongPtr(hwnd_, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0;
}
