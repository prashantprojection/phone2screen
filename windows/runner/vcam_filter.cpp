#include "vcam_filter.h"

#include <cstring>
#include <new>

#include "vcam_pin.h"
#include "vcam_registry.h"

namespace p2s_vcam {
namespace {

class VCamEnumPins final : public IEnumPins {
 public:
  explicit VCamEnumPins(VCamFilter* filter, ULONG pos = 0)
      : filter_(filter), pos_(pos) {
    if (filter_ != nullptr) filter_->AddRef();
  }
  ~VCamEnumPins() {
    if (filter_ != nullptr) filter_->Release();
  }

  STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
    if (ppv == nullptr) return E_POINTER;
    if (riid == __uuidof(IUnknown) || riid == __uuidof(IEnumPins)) {
      *ppv = static_cast<IEnumPins*>(this);
      AddRef();
      return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
  }

  STDMETHODIMP_(ULONG) AddRef() override {
    return static_cast<ULONG>(::InterlockedIncrement(&ref_count_));
  }

  STDMETHODIMP_(ULONG) Release() override {
    const LONG r = ::InterlockedDecrement(&ref_count_);
    if (r == 0) delete this;
    return static_cast<ULONG>(r);
  }

  STDMETHODIMP Next(ULONG cPins, IPin** ppPins, ULONG* pcFetched) override {
    if (ppPins == nullptr) return E_POINTER;
    if (cPins > 1 && pcFetched == nullptr) return E_POINTER;
    ULONG fetched = 0;
    if (pos_ == 0 && cPins > 0 && filter_ != nullptr &&
        filter_->OutputPin() != nullptr) {
      IPin* pin = static_cast<IPin*>(filter_->OutputPin());
      pin->AddRef();
      ppPins[0] = pin;
      fetched = 1;
      pos_ = 1;
    }
    if (pcFetched != nullptr) *pcFetched = fetched;
    return fetched == cPins ? S_OK : S_FALSE;
  }

  STDMETHODIMP Skip(ULONG cPins) override {
    pos_ += cPins;
    return pos_ <= 1 ? S_OK : S_FALSE;
  }

  STDMETHODIMP Reset() override {
    pos_ = 0;
    return S_OK;
  }

  STDMETHODIMP Clone(IEnumPins** ppEnum) override {
    if (ppEnum == nullptr) return E_POINTER;
    auto* cloned = new (std::nothrow) VCamEnumPins(filter_, pos_);
    if (cloned == nullptr) return E_OUTOFMEMORY;
    *ppEnum = cloned;
    return S_OK;
  }

 private:
  volatile LONG ref_count_ = 1;
  VCamFilter* filter_ = nullptr;
  ULONG pos_ = 0;
};

}  // namespace

VCamFilter::VCamFilter() : name_(kVCamFriendlyName) {
  ::InitializeCriticalSection(&cs_);
  ::InterlockedIncrement(&g_vcam_object_count);
  pin_ = new (std::nothrow) VCamPin(this);
}

VCamFilter::~VCamFilter() {
  if (pin_ != nullptr) {
    pin_->Inactive();
    delete pin_;
    pin_ = nullptr;
  }
  if (clock_ != nullptr) {
    clock_->Release();
    clock_ = nullptr;
  }
  ::DeleteCriticalSection(&cs_);
  ::InterlockedDecrement(&g_vcam_object_count);
}

STDMETHODIMP VCamFilter::QueryInterface(REFIID riid, void** ppv) {
  if (ppv == nullptr) return E_POINTER;
  if (riid == __uuidof(IUnknown) || riid == __uuidof(IPersist) ||
      riid == __uuidof(IMediaFilter) || riid == __uuidof(IBaseFilter)) {
    *ppv = static_cast<IBaseFilter*>(this);
  } else if (riid == __uuidof(IAMFilterMiscFlags)) {
    *ppv = static_cast<IAMFilterMiscFlags*>(this);
  } else {
    *ppv = nullptr;
    return E_NOINTERFACE;
  }
  AddRef();
  return S_OK;
}

STDMETHODIMP_(ULONG) VCamFilter::AddRef() {
  return static_cast<ULONG>(::InterlockedIncrement(&ref_count_));
}

STDMETHODIMP_(ULONG) VCamFilter::Release() {
  const LONG r = ::InterlockedDecrement(&ref_count_);
  if (r == 0) delete this;
  return static_cast<ULONG>(r);
}

STDMETHODIMP VCamFilter::GetClassID(CLSID* pClassID) {
  if (pClassID == nullptr) return E_POINTER;
  *pClassID = kVCamClsid;
  return S_OK;
}

STDMETHODIMP VCamFilter::Stop() {
  Lock();
  state_ = State_Stopped;
  const HRESULT hr = pin_ != nullptr ? pin_->Inactive() : S_OK;
  Unlock();
  return hr;
}

STDMETHODIMP VCamFilter::Pause() {
  Lock();
  HRESULT hr = S_OK;
  if (state_ == State_Stopped && pin_ != nullptr) hr = pin_->Active();
  if (SUCCEEDED(hr)) state_ = State_Paused;
  Unlock();
  return hr;
}

STDMETHODIMP VCamFilter::Run(REFERENCE_TIME tStart) {
  Lock();
  HRESULT hr = S_OK;
  if (state_ == State_Stopped && pin_ != nullptr) hr = pin_->Active();
  if (SUCCEEDED(hr)) {
    start_time_ = tStart;
    state_ = State_Running;
  }
  Unlock();
  return hr;
}

STDMETHODIMP VCamFilter::GetState(DWORD, FILTER_STATE* State) {
  if (State == nullptr) return E_POINTER;
  Lock();
  *State = state_;
  const HRESULT hr = (state_ == State_Paused) ? VFW_S_CANT_CUE : S_OK;
  Unlock();
  return hr;
}

STDMETHODIMP VCamFilter::SetSyncSource(IReferenceClock* pClock) {
  Lock();
  if (clock_ != nullptr) clock_->Release();
  clock_ = pClock;
  if (clock_ != nullptr) clock_->AddRef();
  Unlock();
  return S_OK;
}

STDMETHODIMP VCamFilter::GetSyncSource(IReferenceClock** pClock) {
  if (pClock == nullptr) return E_POINTER;
  Lock();
  *pClock = clock_;
  if (clock_ != nullptr) clock_->AddRef();
  Unlock();
  return S_OK;
}

STDMETHODIMP VCamFilter::EnumPins(IEnumPins** ppEnum) {
  if (ppEnum == nullptr) return E_POINTER;
  auto* e = new (std::nothrow) VCamEnumPins(this);
  if (e == nullptr) return E_OUTOFMEMORY;
  *ppEnum = e;
  return S_OK;
}

STDMETHODIMP VCamFilter::FindPin(LPCWSTR Id, IPin** ppPin) {
  if (Id == nullptr || ppPin == nullptr) return E_POINTER;
  if (::wcscmp(Id, L"Capture") == 0 && pin_ != nullptr) {
    *ppPin = static_cast<IPin*>(pin_);
    (*ppPin)->AddRef();
    return S_OK;
  }
  *ppPin = nullptr;
  return VFW_E_NOT_FOUND;
}

STDMETHODIMP VCamFilter::QueryFilterInfo(FILTER_INFO* pInfo) {
  if (pInfo == nullptr) return E_POINTER;
  Lock();
  ::wcsncpy_s(pInfo->achName, name_.c_str(), _TRUNCATE);
  pInfo->pGraph = graph_;
  if (graph_ != nullptr) graph_->AddRef();
  Unlock();
  return S_OK;
}

STDMETHODIMP VCamFilter::JoinFilterGraph(IFilterGraph* pGraph, LPCWSTR pName) {
  Lock();
  graph_ = pGraph;
  name_ = (pName != nullptr && pName[0] != L'\0') ? pName : kVCamFriendlyName;
  Unlock();
  return S_OK;
}

STDMETHODIMP VCamFilter::QueryVendorInfo(LPWSTR* pVendorInfo) {
  if (pVendorInfo == nullptr) return E_POINTER;
  constexpr wchar_t kVendor[] = L"Phone2Screen";
  *pVendorInfo = static_cast<LPWSTR>(::CoTaskMemAlloc(sizeof(kVendor)));
  if (*pVendorInfo == nullptr) return E_OUTOFMEMORY;
  std::memcpy(*pVendorInfo, kVendor, sizeof(kVendor));
  return S_OK;
}

STDMETHODIMP_(ULONG) VCamFilter::GetMiscFlags() {
  return AM_FILTER_MISC_FLAGS_IS_SOURCE;
}

}  // namespace p2s_vcam
