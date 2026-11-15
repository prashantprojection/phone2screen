#ifndef RUNNER_VCAM_SHARED_MEM_H_
#define RUNNER_VCAM_SHARED_MEM_H_

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <algorithm>
#include <cstdint>
#include <cstring>

namespace p2s_vcam {

constexpr wchar_t kVCamSharedMemName[] = L"Local\\Phone2ScreenVCamSharedV1";
constexpr wchar_t kVCamMutexName[] = L"Local\\Phone2ScreenVCamMutexV1";

constexpr uint32_t kVCamMagic = 0x50325356u;
constexpr uint32_t kVCamVersion = 1u;
constexpr int32_t kVCamWidth = 1280;
constexpr int32_t kVCamHeight = 720;
constexpr int32_t kVCamStride = kVCamWidth * 3;
constexpr size_t kVCamFrameBytes =
    static_cast<size_t>(kVCamWidth) * static_cast<size_t>(kVCamHeight) * 3u;
constexpr int64_t kVCamFrameInterval100Ns = 333333;
constexpr uint64_t kVCamStaleTimeoutMs = 3000u;

enum VCamState : uint32_t {
  kVCamStateStandby = 0,
  kVCamStateStreaming = 1,
  kVCamStatePaused = 2,
};

struct VCamSharedFrame {
  uint32_t magic;
  uint32_t version;
  volatile LONG seq;
  uint32_t state;
  uint64_t timestamp_ms;
  uint8_t bgr24[kVCamFrameBytes];
};

inline void SetBottomUpPixel(uint8_t* bgr24, int32_t x, int32_t y, uint8_t r,
                               uint8_t g, uint8_t b) {
  if (x < 0 || x >= kVCamWidth || y < 0 || y >= kVCamHeight) return;
  const size_t dib_y = static_cast<size_t>(kVCamHeight - 1 - y);
  const size_t idx =
      dib_y * static_cast<size_t>(kVCamStride) + static_cast<size_t>(x) * 3u;
  bgr24[idx + 0] = b;
  bgr24[idx + 1] = g;
  bgr24[idx + 2] = r;
}

inline bool InsideRoundedRect(int32_t px, int32_t py, int32_t l, int32_t t,
                              int32_t r, int32_t b, int32_t rad) {
  if (px < l || px >= r || py < t || py >= b) return false;
  const int32_t dx = px - std::clamp(px, l + rad, r - 1 - rad);
  const int32_t dy = py - std::clamp(py, t + rad, b - 1 - rad);
  return (dx * dx + dy * dy) <= (rad * rad);
}

// Renders a bottom-up 1280x720 BGR24 studio slate for Standby or Privacy Paused.
inline void RenderVCamSlate(uint8_t* bgr24, bool paused) {
  if (bgr24 == nullptr) return;
  const uint8_t ac_r = paused ? 245 : 56;
  const uint8_t ac_g = paused ? 158 : 189;
  const uint8_t ac_b = paused ? 11 : 248;
  for (int32_t y = 0; y < kVCamHeight; ++y) {
    const uint8_t r = static_cast<uint8_t>(14 + (y * 5) / kVCamHeight);
    const uint8_t g = static_cast<uint8_t>(17 + (y * 8) / kVCamHeight);
    const uint8_t b = static_cast<uint8_t>(23 + (y * 13) / kVCamHeight);
    const size_t dib_y = static_cast<size_t>(kVCamHeight - 1 - y);
    uint8_t* row = bgr24 + dib_y * static_cast<size_t>(kVCamStride);
    for (int32_t x = 0; x < kVCamWidth; ++x) {
      row[x * 3 + 0] = b;
      row[x * 3 + 1] = g;
      row[x * 3 + 2] = r;
    }
  }
  // Centered rounded studio card (560x300) with border and top accent strip.
  for (int32_t y = 210; y < 510; ++y) {
    for (int32_t x = 360; x < 920; ++x) {
      if (!InsideRoundedRect(x, y, 360, 210, 920, 510, 24)) continue;
      if (!InsideRoundedRect(x, y, 362, 212, 918, 508, 22)) {
        SetBottomUpPixel(bgr24, x, y, 42, 52, 70);
      } else if (y < 218) {
        SetBottomUpPixel(bgr24, x, y, ac_r, ac_g, ac_b);
      } else {
        SetBottomUpPixel(bgr24, x, y, 21, 27, 36);
      }
    }
  }
  // Geometric camera body, lens hood, circular lens ring, and banner pill.
  for (int32_t y = 290; y <= 386; ++y) {
    for (int32_t x = 562; x <= 682; ++x) {
      if (InsideRoundedRect(x, y, 562, 290, 682, 386, 14)) {
        SetBottomUpPixel(bgr24, x, y, 216, 226, 238);
      }
    }
  }
  for (int32_t y = 304; y <= 372; ++y) {
    const int32_t inset = (y < 320) ? (320 - y) : (y > 356 ? (y - 356) : 0);
    for (int32_t x = 686; x <= 724 - inset / 2; ++x) {
      SetBottomUpPixel(bgr24, x, y, ac_r, ac_g, ac_b);
    }
  }
  for (int32_t dy = -26; dy <= 26; ++dy) {
    for (int32_t dx = -26; dx <= 26; ++dx) {
      const int32_t d2 = dx * dx + dy * dy;
      if (d2 <= 676 && d2 >= 256) {
        SetBottomUpPixel(bgr24, 622 + dx, 338 + dy, 21, 27, 36);
      } else if (d2 <= 144) {
        SetBottomUpPixel(bgr24, 622 + dx, 338 + dy, ac_r, ac_g, ac_b);
      }
    }
  }
  for (int32_t y = 428; y < 444; ++y) {
    for (int32_t x = 490; x < 790; ++x) {
      if (InsideRoundedRect(x, y, 490, 428, 790, 444, 8)) {
        SetBottomUpPixel(bgr24, x, y, ac_r, ac_g, ac_b);
      }
    }
  }
  if (paused) {
    for (int32_t t = -52; t <= 52; ++t) {
      for (int32_t w = -4; w <= 4; ++w) {
        SetBottomUpPixel(bgr24, 624 + t + w, 338 - t, ac_r, ac_g, ac_b);
      }
    }
  }
}

class VCamSharedMem {
 public:
  VCamSharedMem() = default;
  ~VCamSharedMem() { Close(); }
  VCamSharedMem(const VCamSharedMem&) = delete;
  VCamSharedMem& operator=(const VCamSharedMem&) = delete;

  bool Open(bool write_access, bool create_if_missing) {
    if (view_ != nullptr && write_access == writable_) return true;
    Close();
    writable_ = write_access;
    mutex_ = create_if_missing
                 ? ::CreateMutexW(nullptr, FALSE, kVCamMutexName)
                 : ::OpenMutexW(SYNCHRONIZE, FALSE, kVCamMutexName);
    const DWORD access =
        write_access ? (FILE_MAP_READ | FILE_MAP_WRITE) : FILE_MAP_READ;
    mapping_ = create_if_missing
                   ? ::CreateFileMappingW(
                         INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0,
                         static_cast<DWORD>(sizeof(VCamSharedFrame)),
                         kVCamSharedMemName)
                   : ::OpenFileMappingW(access, FALSE, kVCamSharedMemName);
    if (mapping_ == nullptr) {
      Close();
      return false;
    }
    view_ = static_cast<VCamSharedFrame*>(
        ::MapViewOfFile(mapping_, access, 0, 0, sizeof(VCamSharedFrame)));
    if (view_ == nullptr) {
      Close();
      return false;
    }
    return true;
  }

  void Close() {
    if (view_ != nullptr) ::UnmapViewOfFile(view_);
    if (mapping_ != nullptr) ::CloseHandle(mapping_);
    if (mutex_ != nullptr) ::CloseHandle(mutex_);
    view_ = nullptr;
    mapping_ = nullptr;
    mutex_ = nullptr;
    writable_ = false;
  }

  bool Lock(DWORD timeout_ms = 16) const {
    if (mutex_ == nullptr) return true;
    const DWORD wait = ::WaitForSingleObject(mutex_, timeout_ms);
    return wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED;
  }

  void Unlock() const {
    if (mutex_ != nullptr) ::ReleaseMutex(mutex_);
  }

  VCamSharedFrame* View() const { return view_; }

 private:
  HANDLE mapping_ = nullptr;
  HANDLE mutex_ = nullptr;
  VCamSharedFrame* view_ = nullptr;
  bool writable_ = false;
};

}  // namespace p2s_vcam

#endif  // RUNNER_VCAM_SHARED_MEM_H_
