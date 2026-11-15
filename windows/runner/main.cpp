#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <algorithm>
#include <cstdlib>
#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {
std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) return {};
  const int len = ::MultiByteToWideChar(
      CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()), nullptr, 0);
  if (len <= 0) return {};
  std::wstring out(static_cast<size_t>(len), L'\0');
  const int n = ::MultiByteToWideChar(
      CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()), out.data(), len);
  return n > 0 ? out : std::wstring();
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  std::vector<std::string> args = GetCommandLineArguments();

  std::wstring windowTitle = L"phone2screen";
  int windowOffset = 0;
  for (const auto& arg : args) {
    if (arg.rfind("--window-title=", 0) == 0 && arg.size() > 15) {
      const std::wstring parsed = Utf16FromUtf8(arg.substr(15));
      if (!parsed.empty()) windowTitle = parsed;
    } else if (arg.rfind("--window-offset=", 0) == 0) {
      char* end = nullptr;
      const long parsed = std::strtol(arg.substr(16).c_str(), &end, 10);
      if (end != nullptr && *end == '\0') {
        windowOffset = static_cast<int>(std::clamp(parsed, 0L, 310L));
      }
    }
  }

  project.set_dart_entrypoint_arguments(std::move(args));

  FlutterWindow window(project);
  const auto coord = static_cast<unsigned int>(std::clamp(10 + windowOffset, 10, 320));
  Win32Window::Point origin(coord, coord);
  Win32Window::Size size(1280, 720);
  if (!window.Create(windowTitle.c_str(), origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
