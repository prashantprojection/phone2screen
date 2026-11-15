#ifndef RUNNER_VCAM_REGISTRY_H_
#define RUNNER_VCAM_REGISTRY_H_

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <cstdint>
#include <string>

namespace p2s_vcam {

extern const CLSID kVCamClsid;
constexpr wchar_t kVCamClsidStr[] =
    L"{D8E4A2F1-7B3C-4E9A-9C1D-5F2A8B6E4C10}";
constexpr wchar_t kVCamFriendlyName[] = L"Phone2Screen Camera";
constexpr wchar_t kVCamDevicePath[] = L"p2s://virtual-camera/0";

// Resolves the full path to `p2s_vcam.dll`. When `module` is null, resolves next
// to the current executable; otherwise queries the DLL module path directly.
std::wstring ResolveVCamDllPath(HMODULE module);

// Registers `p2s_vcam.dll` under HKCU COM & DirectShow Video Input Category.
bool RegisterVirtualCamHkcu(const wchar_t* dll_path);

// Removes HKCU COM & DirectShow Video Input Category keys for Phone2Screen.
bool UnregisterVirtualCamHkcu();

// Returns true when both HKCU CLSID and DirectShow Instance keys are present.
bool IsVirtualCamRegisteredHkcu(std::wstring* out_dll_path = nullptr);

// Reads current state from shared memory (0=standby, 1=streaming, 2=paused).
uint32_t ReadVirtualCamSharedState();

// Updates shared memory state and renders a procedural slate for standby/paused.
bool SetVirtualCamSharedState(uint32_t state);

// Converts top-down RGBA8888 into aspect-preserving letterboxed 1280x720
// bottom-up BGR24 inside shared memory with state=1 and fresh GetTickCount64().
bool PushVirtualCamRgbaFrame(const uint8_t* rgba, int32_t width,
                             int32_t height);

}  // namespace p2s_vcam

#endif  // RUNNER_VCAM_REGISTRY_H_
