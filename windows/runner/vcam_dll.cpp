#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#pragma warning(push, 3)
#include <dshow.h>
#include <objbase.h>
#include <olectl.h>
#pragma warning(pop)

#include <cstring>
#include <new>
#include <string>

#include "vcam_filter.h"
#include "vcam_pin.h"
#include "vcam_registry.h"
#include "vcam_shared_mem.h"

namespace p2s_vcam {

volatile LONG g_vcam_object_count = 0;
volatile LONG g_vcam_lock_count = 0;

void FreeMediaTypeFields(AM_MEDIA_TYPE* mt) {
  if (mt == nullptr) return;
  if (mt->cbFormat != 0 && mt->pbFormat != nullptr) ::CoTaskMemFree(mt->pbFormat);
  if (mt->pUnk != nullptr) mt->pUnk->Release();
  mt->cbFormat = 0;
  mt->pbFormat = nullptr;
  mt->pUnk = nullptr;
}

void InitDefaultMediaType(AM_MEDIA_TYPE* mt) {
  std::memset(mt, 0, sizeof(AM_MEDIA_TYPE));
  mt->majortype = MEDIATYPE_Video;
  mt->subtype = MEDIASUBTYPE_RGB24;
  mt->bFixedSizeSamples = TRUE;
  mt->lSampleSize = static_cast<ULONG>(kVCamFrameBytes);
  mt->formattype = FORMAT_VideoInfo;
  mt->cbFormat = sizeof(VIDEOINFOHEADER);
  auto* vih = static_cast<VIDEOINFOHEADER*>(::CoTaskMemAlloc(mt->cbFormat));
  if (vih == nullptr) {
    mt->cbFormat = 0;
    return;
  }
  std::memset(vih, 0, sizeof(VIDEOINFOHEADER));
  vih->rcSource = vih->rcTarget = {0, 0, kVCamWidth, kVCamHeight};
  vih->dwBitRate = static_cast<DWORD>(kVCamFrameBytes * 8u * 30u);
  vih->AvgTimePerFrame = kVCamFrameInterval100Ns;
  vih->bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  vih->bmiHeader.biWidth = kVCamWidth;
  vih->bmiHeader.biHeight = kVCamHeight;
  vih->bmiHeader.biPlanes = 1;
  vih->bmiHeader.biBitCount = 24;
  vih->bmiHeader.biCompression = BI_RGB;
  vih->bmiHeader.biSizeImage = static_cast<DWORD>(kVCamFrameBytes);
  mt->pbFormat = reinterpret_cast<BYTE*>(vih);
}

HRESULT CopyMediaTypeFields(AM_MEDIA_TYPE* dst, const AM_MEDIA_TYPE* src) {
  if (dst == nullptr || src == nullptr) return E_POINTER;
  FreeMediaTypeFields(dst);
  *dst = *src;
  dst->pUnk = nullptr;
  dst->pbFormat = nullptr;
  if (src->cbFormat != 0 && src->pbFormat != nullptr) {
    dst->pbFormat = static_cast<BYTE*>(::CoTaskMemAlloc(src->cbFormat));
    if (dst->pbFormat == nullptr) {
      dst->cbFormat = 0;
      return E_OUTOFMEMORY;
    }
    std::memcpy(dst->pbFormat, src->pbFormat, src->cbFormat);
  }
  if (src->pUnk != nullptr) {
    dst->pUnk = src->pUnk;
    dst->pUnk->AddRef();
  }
  return S_OK;
}

AM_MEDIA_TYPE* AllocMediaType(const AM_MEDIA_TYPE* src) {
  auto* mt = static_cast<AM_MEDIA_TYPE*>(::CoTaskMemAlloc(sizeof(AM_MEDIA_TYPE)));
  if (mt == nullptr) return nullptr;
  std::memset(mt, 0, sizeof(AM_MEDIA_TYPE));
  if (FAILED(CopyMediaTypeFields(mt, src))) {
    ::CoTaskMemFree(mt);
    return nullptr;
  }
  return mt;
}

bool IsSupportedMediaType(const AM_MEDIA_TYPE* pmt, bool allow_wildcards) {
  if (pmt == nullptr) return allow_wildcards;
  if (pmt->majortype != MEDIATYPE_Video &&
      (!allow_wildcards || pmt->majortype != GUID_NULL)) {
    return false;
  }
  if (pmt->subtype != MEDIASUBTYPE_RGB24 &&
      (!allow_wildcards || pmt->subtype != GUID_NULL)) {
    return false;
  }
  if (pmt->formattype == GUID_NULL && allow_wildcards) return true;
  if (pmt->formattype != FORMAT_VideoInfo ||
      pmt->cbFormat < sizeof(VIDEOINFOHEADER) || pmt->pbFormat == nullptr) {
    return false;
  }
  const auto& bmi =
      reinterpret_cast<const VIDEOINFOHEADER*>(pmt->pbFormat)->bmiHeader;
  return bmi.biWidth == kVCamWidth && bmi.biHeight == kVCamHeight &&
         bmi.biPlanes == 1 && bmi.biBitCount == 24 &&
         bmi.biCompression == BI_RGB;
}

namespace {

HINSTANCE g_vcam_module = nullptr;

class VCamEnumMediaTypes final : public IEnumMediaTypes {
 public:
  explicit VCamEnumMediaTypes(VCamPin* pin, ULONG pos = 0)
      : pin_(pin), pos_(pos) {
    if (pin_ != nullptr) pin_->AddRef();
  }
  ~VCamEnumMediaTypes() {
    if (pin_ != nullptr) pin_->Release();
  }
  STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
    if (ppv == nullptr) return E_POINTER;
    if (riid != __uuidof(IUnknown) && riid != __uuidof(IEnumMediaTypes)) {
      *ppv = nullptr;
      return E_NOINTERFACE;
    }
    *ppv = static_cast<IEnumMediaTypes*>(this);
    AddRef();
    return S_OK;
  }
  STDMETHODIMP_(ULONG) AddRef() override {
    return static_cast<ULONG>(::InterlockedIncrement(&ref_count_));
  }
  STDMETHODIMP_(ULONG) Release() override {
    const LONG r = ::InterlockedDecrement(&ref_count_);
    if (r == 0) delete this;
    return static_cast<ULONG>(r);
  }
  STDMETHODIMP Next(ULONG c, AM_MEDIA_TYPE** out, ULONG* fetched_out) override {
    if (out == nullptr || (c > 1 && fetched_out == nullptr)) return E_POINTER;
    ULONG fetched = 0;
    if (pos_ == 0 && c > 0 && SUCCEEDED(pin_->GetFormat(&out[0]))) {
      fetched = 1;
      pos_ = 1;
    }
    if (fetched_out != nullptr) *fetched_out = fetched;
    return fetched == c ? S_OK : S_FALSE;
  }
  STDMETHODIMP Skip(ULONG c) override {
    pos_ += c;
    return pos_ <= 1 ? S_OK : S_FALSE;
  }
  STDMETHODIMP Reset() override {
    pos_ = 0;
    return S_OK;
  }
  STDMETHODIMP Clone(IEnumMediaTypes** ppEnum) override {
    if (ppEnum == nullptr) return E_POINTER;
    *ppEnum = new (std::nothrow) VCamEnumMediaTypes(pin_, pos_);
    return *ppEnum != nullptr ? S_OK : E_OUTOFMEMORY;
  }

 private:
  volatile LONG ref_count_ = 1;
  VCamPin* pin_ = nullptr;
  ULONG pos_ = 0;
};

class VCamClassFactory final : public IClassFactory {
 public:
  VCamClassFactory() { ::InterlockedIncrement(&g_vcam_object_count); }
  ~VCamClassFactory() { ::InterlockedDecrement(&g_vcam_object_count); }
  STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
    if (ppv == nullptr) return E_POINTER;
    if (riid != __uuidof(IUnknown) && riid != __uuidof(IClassFactory)) {
      *ppv = nullptr;
      return E_NOINTERFACE;
    }
    *ppv = static_cast<IClassFactory*>(this);
    AddRef();
    return S_OK;
  }
  STDMETHODIMP_(ULONG) AddRef() override {
    return static_cast<ULONG>(::InterlockedIncrement(&ref_count_));
  }
  STDMETHODIMP_(ULONG) Release() override {
    const LONG r = ::InterlockedDecrement(&ref_count_);
    if (r == 0) delete this;
    return static_cast<ULONG>(r);
  }
  STDMETHODIMP CreateInstance(IUnknown* pUnkOuter, REFIID riid,
                              void** ppv) override {
    if (ppv == nullptr) return E_POINTER;
    *ppv = nullptr;
    if (pUnkOuter != nullptr) return CLASS_E_NOAGGREGATION;
    auto* filter = new (std::nothrow) VCamFilter();
    if (filter == nullptr) return E_OUTOFMEMORY;
    const HRESULT hr = filter->QueryInterface(riid, ppv);
    filter->Release();
    return hr;
  }
  STDMETHODIMP LockServer(BOOL fLock) override {
    if (fLock != FALSE) ::InterlockedIncrement(&g_vcam_lock_count);
    else ::InterlockedDecrement(&g_vcam_lock_count);
    return S_OK;
  }

 private:
  volatile LONG ref_count_ = 1;
};

}  // namespace

HRESULT CreateEnumMediaTypes(VCamPin* pin, IEnumMediaTypes** ppEnum) {
  if (ppEnum == nullptr) return E_POINTER;
  *ppEnum = new (std::nothrow) VCamEnumMediaTypes(pin);
  return *ppEnum != nullptr ? S_OK : E_OUTOFMEMORY;
}

}  // namespace p2s_vcam

BOOL APIENTRY DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID) {
  if (fdwReason == DLL_PROCESS_ATTACH) {
    p2s_vcam::g_vcam_module = hinstDLL;
    ::DisableThreadLibraryCalls(hinstDLL);
  }
  return TRUE;
}

STDAPI DllGetClassObject(REFCLSID rclsid, REFIID riid, LPVOID* ppv) {
  if (ppv == nullptr) return E_POINTER;
  *ppv = nullptr;
  if (!IsEqualCLSID(rclsid, p2s_vcam::kVCamClsid)) {
    return CLASS_E_CLASSNOTAVAILABLE;
  }
  auto* factory = new (std::nothrow) p2s_vcam::VCamClassFactory();
  if (factory == nullptr) return E_OUTOFMEMORY;
  const HRESULT hr = factory->QueryInterface(riid, ppv);
  factory->Release();
  return hr;
}

STDAPI DllCanUnloadNow(void) {
  return (p2s_vcam::g_vcam_object_count == 0 &&
          p2s_vcam::g_vcam_lock_count == 0)
             ? S_OK
             : S_FALSE;
}

STDAPI DllRegisterServer(void) {
  const std::wstring path =
      p2s_vcam::ResolveVCamDllPath(p2s_vcam::g_vcam_module);
  if (path.empty()) return SELFREG_E_CLASS;
  return p2s_vcam::RegisterVirtualCamHkcu(path.c_str()) ? S_OK
                                                         : SELFREG_E_CLASS;
}

STDAPI DllUnregisterServer(void) {
  return p2s_vcam::UnregisterVirtualCamHkcu() ? S_OK : SELFREG_E_CLASS;
}
