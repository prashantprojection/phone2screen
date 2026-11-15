#ifndef RUNNER_STUDIO_BRIDGE_H_
#define RUNNER_STUDIO_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

// Native Win32 bridge for DirectShow virtual camera discovery, WaveOut audio
// output enumeration, and Always-On-Top window management.
class StudioBridge {
 public:
  StudioBridge(flutter::BinaryMessenger* messenger, HWND hwnd);
  ~StudioBridge();

  StudioBridge(const StudioBridge&) = delete;
  StudioBridge& operator=(const StudioBridge&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  flutter::EncodableValue ListVideoCaptureDevices() const;
  flutter::EncodableValue ListAudioOutputDevices() const;
  bool SetAlwaysOnTop(bool enabled) const;
  bool GetAlwaysOnTop() const;

  HWND hwnd_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_STUDIO_BRIDGE_H_
