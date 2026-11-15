#include "vcam_registry.h"

#include <algorithm>
#include <cstring>
#include <vector>

#pragma warning(push, 3)
#include <dshow.h>
#include <objbase.h>
#pragma warning(pop)

#include "vcam_shared_mem.h"

namespace p2s_vcam {

const CLSID kVCamClsid = {
    0xD8E4A2F1, 0x7B3C, 0x4E9A,
    {0x9C, 0x1D, 0x5F, 0x2A, 0x8B, 0x6E, 0x4C, 0x10},
};

namespace {

constexpr wchar_t kClsidBase[] = L"Software\\Classes\\CLSID\\";
constexpr wchar_t kVideoCategory[] = L"{860BB310-5D01-11D0-BD3B-00A0C911CE86}";

std::wstring ClsidKeyPath() { return std::wstring(kClsidBase) + kVCamClsidStr; }
std::wstring InprocKeyPath() { return ClsidKeyPath() + L"\\InprocServer32"; }
std::wstring InstanceKeyPath() {
  return std::wstring(kClsidBase) + kVideoCategory + L"\\Instance\\" +
         kVCamClsidStr;
}

bool SetRegSz(HKEY key, const wchar_t* name, const wchar_t* value) {
  const DWORD bytes =
      static_cast<DWORD>((::wcslen(value) + 1) * sizeof(wchar_t));
  return ::RegSetValueExW(key, name, 0, REG_SZ,
                          reinterpret_cast<const BYTE*>(value), bytes) == 0;
}

bool CreateWriteKey(const std::wstring& subkey, HKEY* out_key) {
  return ::RegCreateKeyExW(HKEY_CURRENT_USER, subkey.c_str(), 0, nullptr, 0,
                           KEY_WRITE, nullptr, out_key, nullptr) == 0;
}

template <typename T>
void AppendRaw(std::vector<uint8_t>* out, const T& value) {
  const auto* p = reinterpret_cast<const uint8_t*>(&value);
  out->insert(out->end(), p, p + sizeof(T));
}

std::vector<uint8_t> BuildFilterDataBlob() {
  std::vector<uint8_t> b;
  b.reserve(104);
  const uint32_t hdr[] = {
      2u, 0x00200000u, 1u, 0u,
      0x33697030u, 0x00000008u, 1u, 1u, 0u, 56u,
      0x33797430u, 0u, 72u, 88u,
  };
  for (uint32_t d : hdr) AppendRaw(&b, d);
  AppendRaw(&b, PIN_CATEGORY_CAPTURE);
  AppendRaw(&b, MEDIATYPE_Video);
  AppendRaw(&b, MEDIASUBTYPE_RGB24);
  return b;
}

void EnsureHeader(VCamSharedFrame* frame, uint32_t default_state) {
  if (frame->magic == kVCamMagic && frame->version == kVCamVersion) return;
  frame->magic = kVCamMagic;
  frame->version = kVCamVersion;
  frame->seq = 0;
  frame->state = default_state;
  frame->timestamp_ms = ::GetTickCount64();
  RenderVCamSlate(frame->bgr24, default_state == kVCamStatePaused);
}

inline void FillBgPixel(uint8_t* dst) {
  dst[0] = 23; dst[1] = 17; dst[2] = 14;
}

}  // namespace

std::wstring ResolveVCamDllPath(HMODULE module) {
  wchar_t buffer[MAX_PATH] = {};
  const DWORD len = ::GetModuleFileNameW(module, buffer, MAX_PATH);
  if (len == 0 || len >= MAX_PATH) return {};
  std::wstring path(buffer, len);
  if (module != nullptr) return path;
  const size_t slash = path.find_last_of(L"\\/");
  return slash == std::wstring::npos
             ? L"p2s_vcam.dll"
             : path.substr(0, slash + 1) + L"p2s_vcam.dll";
}

bool RegisterVirtualCamHkcu(const wchar_t* dll_path) {
  if (dll_path == nullptr || dll_path[0] == L'\0') return false;
  HKEY clsid_key = nullptr, inproc_key = nullptr, inst_key = nullptr;
  if (!CreateWriteKey(ClsidKeyPath(), &clsid_key)) return false;
  bool ok = SetRegSz(clsid_key, nullptr, kVCamFriendlyName);
  ::RegCloseKey(clsid_key);
  if (!ok || !CreateWriteKey(InprocKeyPath(), &inproc_key)) return false;
  ok = SetRegSz(inproc_key, nullptr, dll_path) &&
       SetRegSz(inproc_key, L"ThreadingModel", L"Both");
  ::RegCloseKey(inproc_key);
  if (!ok || !CreateWriteKey(InstanceKeyPath(), &inst_key)) return false;
  const std::vector<uint8_t> filter_data = BuildFilterDataBlob();
  ok = SetRegSz(inst_key, L"CLSID", kVCamClsidStr) &&
       SetRegSz(inst_key, L"FriendlyName", kVCamFriendlyName) &&
       SetRegSz(inst_key, L"DevicePath", kVCamDevicePath) &&
       (::RegSetValueExW(inst_key, L"FilterData", 0, REG_BINARY,
                         filter_data.data(),
                         static_cast<DWORD>(filter_data.size())) == 0);
  ::RegCloseKey(inst_key);
  return ok;
}

bool UnregisterVirtualCamHkcu() {
  const LONG r1 = ::RegDeleteTreeW(HKEY_CURRENT_USER, InstanceKeyPath().c_str());
  const LONG r2 = ::RegDeleteTreeW(HKEY_CURRENT_USER, ClsidKeyPath().c_str());
  return (r1 == 0 || r1 == ERROR_FILE_NOT_FOUND) &&
         (r2 == 0 || r2 == ERROR_FILE_NOT_FOUND);
}

bool IsVirtualCamRegisteredHkcu(std::wstring* out_dll_path) {
  HKEY inproc = nullptr, inst = nullptr;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, InprocKeyPath().c_str(), 0, KEY_READ, &inproc) != 0) {
    return false;
  }
  wchar_t buf[MAX_PATH] = {};
  DWORD bytes = sizeof(buf), type = 0;
  const LONG q = ::RegQueryValueExW(inproc, nullptr, nullptr, &type,
                                    reinterpret_cast<BYTE*>(buf), &bytes);
  ::RegCloseKey(inproc);
  if (q != 0 || (type != REG_SZ && type != REG_EXPAND_SZ) || buf[0] == L'\0') return false;
  if (out_dll_path != nullptr) *out_dll_path = buf;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, InstanceKeyPath().c_str(), 0, KEY_READ, &inst) != 0) {
    return false;
  }
  ::RegCloseKey(inst);
  return true;
}

uint32_t ReadVirtualCamSharedState() {
  VCamSharedMem mem;
  if (!mem.Open(false, false)) return kVCamStateStandby;
  uint32_t state = kVCamStateStandby;
  if (mem.Lock()) {
    VCamSharedFrame* f = mem.View();
    if (f && f->magic == kVCamMagic && f->version == kVCamVersion) state = f->state;
    mem.Unlock();
  }
  return state;
}

bool SetVirtualCamSharedState(uint32_t state) {
  const uint32_t clamped = state <= kVCamStatePaused ? state : kVCamStateStandby;
  VCamSharedMem mem;
  if (!mem.Open(true, true) || !mem.Lock()) return false;
  VCamSharedFrame* f = mem.View();
  EnsureHeader(f, clamped);
  f->state = clamped;
  f->timestamp_ms = ::GetTickCount64();
  if (clamped != kVCamStateStreaming) {
    RenderVCamSlate(f->bgr24, clamped == kVCamStatePaused);
  }
  ::InterlockedIncrement(&f->seq);
  mem.Unlock();
  return true;
}

bool PushVirtualCamRgbaFrame(const uint8_t* rgba, int32_t w, int32_t h) {
  if (rgba == nullptr || w <= 0 || h <= 0) return false;
  VCamSharedMem mem;
  if (!mem.Open(true, true) || !mem.Lock()) return false;
  VCamSharedFrame* f = mem.View();
  EnsureHeader(f, kVCamStateStreaming);
  const bool wider =
      static_cast<int64_t>(w) * kVCamHeight >= static_cast<int64_t>(kVCamWidth) * h;
  const int32_t sw = wider
      ? kVCamWidth
      : std::max<int32_t>(1, static_cast<int32_t>((static_cast<int64_t>(w) * kVCamHeight + h / 2) / h));
  const int32_t sh = wider
      ? std::max<int32_t>(1, static_cast<int32_t>((static_cast<int64_t>(h) * kVCamWidth + w / 2) / w))
      : kVCamHeight;
  const int32_t ox = (kVCamWidth - sw) / 2, oy = (kVCamHeight - sh) / 2;
  for (int32_t dy = 0; dy < kVCamHeight; ++dy) {
    uint8_t* row = f->bgr24 + static_cast<size_t>(kVCamHeight - 1 - dy) *
                                  static_cast<size_t>(kVCamStride);
    if (dy < oy || dy >= oy + sh) {
      for (int32_t dx = 0; dx < kVCamWidth; ++dx) FillBgPixel(row + dx * 3);
      continue;
    }
    const int32_t sy = std::clamp(((dy - oy) * h) / sh, 0, h - 1);
    const uint8_t* src = rgba + static_cast<size_t>(sy) * static_cast<size_t>(w) * 4u;
    for (int32_t dx = 0; dx < kVCamWidth; ++dx) {
      if (dx < ox || dx >= ox + sw) {
        FillBgPixel(row + dx * 3);
        continue;
      }
      const uint8_t* px =
          src + static_cast<size_t>(std::clamp(((dx - ox) * w) / sw, 0, w - 1)) * 4u;
      const uint32_t inv_a = 255u - px[3];
      row[dx * 3 + 0] = static_cast<uint8_t>(px[2] + (23u * inv_a) / 255u);
      row[dx * 3 + 1] = static_cast<uint8_t>(px[1] + (17u * inv_a) / 255u);
      row[dx * 3 + 2] = static_cast<uint8_t>(px[0] + (14u * inv_a) / 255u);
    }
  }
  f->state = kVCamStateStreaming;
  f->timestamp_ms = ::GetTickCount64();
  ::InterlockedIncrement(&f->seq);
  mem.Unlock();
  return true;
}

}  // namespace p2s_vcam
