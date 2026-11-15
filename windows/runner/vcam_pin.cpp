#include "vcam_pin.h"

#include <cstring>

#include "vcam_filter.h"

namespace p2s_vcam {

VCamPin::VCamPin(VCamFilter* filter) : filter_(filter) {
  InitDefaultMediaType(&configured_mt_);
  stop_event_ = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
}

VCamPin::~VCamPin() {
  Inactive();
  if (allocator_ != nullptr) allocator_->Release();
  if (mem_input_pin_ != nullptr) mem_input_pin_->Release();
  if (connected_pin_ != nullptr) connected_pin_->Release();
  if (quality_sink_ != nullptr) quality_sink_->Release();
  FreeMediaTypeFields(&configured_mt_);
  FreeMediaTypeFields(&current_mt_);
  if (stop_event_ != nullptr) ::CloseHandle(stop_event_);
}

STDMETHODIMP VCamPin::QueryInterface(REFIID riid, void** ppv) {
  if (ppv == nullptr) return E_POINTER;
  if (riid == __uuidof(IUnknown) || riid == __uuidof(IPin)) {
    *ppv = static_cast<IPin*>(this);
  } else if (riid == __uuidof(IQualityControl)) {
    *ppv = static_cast<IQualityControl*>(this);
  } else if (riid == __uuidof(IAMStreamConfig)) {
    *ppv = static_cast<IAMStreamConfig*>(this);
  } else if (riid == __uuidof(IKsPropertySet)) {
    *ppv = static_cast<IKsPropertySet*>(this);
  } else {
    *ppv = nullptr;
    return E_NOINTERFACE;
  }
  AddRef();
  return S_OK;
}

STDMETHODIMP_(ULONG) VCamPin::AddRef() { return filter_->AddRef(); }
STDMETHODIMP_(ULONG) VCamPin::Release() { return filter_->Release(); }

STDMETHODIMP VCamPin::Connect(IPin* pReceivePin, const AM_MEDIA_TYPE* pmt) {
  if (!pReceivePin) return E_POINTER;
  filter_->Lock();
  HRESULT hr = S_OK;
  if (connected_pin_) hr = VFW_E_ALREADY_CONNECTED;
  else if (filter_->State() != State_Stopped) hr = VFW_E_NOT_STOPPED;
  else if (!IsSupportedMediaType(pmt, true)) hr = VFW_E_NO_ACCEPTABLE_TYPES;
  if (FAILED(hr)) { filter_->Unlock(); return hr; }

  hr = pReceivePin->ReceiveConnection(this, &configured_mt_);
  IMemInputPin* mem_in = nullptr;
  IMemAllocator* alloc = nullptr;
  if (SUCCEEDED(hr)) {
    hr = pReceivePin->QueryInterface(__uuidof(IMemInputPin), reinterpret_cast<void**>(&mem_in));
  }
  if (SUCCEEDED(hr) && mem_in) {
    if (FAILED(mem_in->GetAllocator(&alloc)) || !alloc) {
      hr = ::CoCreateInstance(CLSID_MemoryAllocator, nullptr, CLSCTX_INPROC_SERVER,
                              __uuidof(IMemAllocator), reinterpret_cast<void**>(&alloc));
    }
    if (SUCCEEDED(hr) && alloc) {
      ALLOCATOR_PROPERTIES req{2, static_cast<long>(kVCamFrameBytes), 1, 0}, act{};
      hr = alloc->SetProperties(&req, &act);
      if (SUCCEEDED(hr) && act.cbBuffer < req.cbBuffer) hr = VFW_E_BADALIGN;
      if (SUCCEEDED(hr)) hr = mem_in->NotifyAllocator(alloc, FALSE);
    }
  }
  if (FAILED(hr) || !mem_in || !alloc) {
    if (alloc) alloc->Release();
    if (mem_in) mem_in->Release();
    if (mem_in || SUCCEEDED(hr)) pReceivePin->Disconnect();
    filter_->Unlock();
    return FAILED(hr) ? hr : E_FAIL;
  }
  CopyMediaTypeFields(&current_mt_, &configured_mt_);
  connected_pin_ = pReceivePin;
  connected_pin_->AddRef();
  mem_input_pin_ = mem_in;
  allocator_ = alloc;
  filter_->Unlock();
  return S_OK;
}

STDMETHODIMP VCamPin::Disconnect() {
  filter_->Lock();
  if (filter_->State() != State_Stopped) { filter_->Unlock(); return VFW_E_NOT_STOPPED; }
  if (!connected_pin_) { filter_->Unlock(); return S_FALSE; }
  if (allocator_) allocator_->Release();
  if (mem_input_pin_) mem_input_pin_->Release();
  connected_pin_->Release();
  allocator_ = nullptr; mem_input_pin_ = nullptr; connected_pin_ = nullptr;
  FreeMediaTypeFields(&current_mt_);
  filter_->Unlock();
  return S_OK;
}

STDMETHODIMP VCamPin::ConnectedTo(IPin** pPin) {
  if (!pPin) return E_POINTER;
  filter_->Lock();
  *pPin = connected_pin_;
  if (connected_pin_) connected_pin_->AddRef();
  const HRESULT hr = connected_pin_ ? S_OK : VFW_E_NOT_CONNECTED;
  filter_->Unlock();
  return hr;
}

STDMETHODIMP VCamPin::ConnectionMediaType(AM_MEDIA_TYPE* pmt) {
  if (!pmt) return E_POINTER;
  filter_->Lock();
  const HRESULT hr = connected_pin_ ? CopyMediaTypeFields(pmt, &current_mt_) : VFW_E_NOT_CONNECTED;
  filter_->Unlock();
  return hr;
}

STDMETHODIMP VCamPin::QueryPinInfo(PIN_INFO* pInfo) {
  if (pInfo == nullptr) return E_POINTER;
  pInfo->pFilter = static_cast<IBaseFilter*>(filter_);
  pInfo->pFilter->AddRef();
  pInfo->dir = PINDIR_OUTPUT;
  ::wcscpy_s(pInfo->achName, L"Capture");
  return S_OK;
}

STDMETHODIMP VCamPin::QueryId(LPWSTR* Id) {
  if (Id == nullptr) return E_POINTER;
  constexpr wchar_t kId[] = L"Capture";
  *Id = static_cast<LPWSTR>(::CoTaskMemAlloc(sizeof(kId)));
  if (*Id == nullptr) return E_OUTOFMEMORY;
  std::memcpy(*Id, kId, sizeof(kId));
  return S_OK;
}

STDMETHODIMP VCamPin::QueryAccept(const AM_MEDIA_TYPE* pmt) {
  return IsSupportedMediaType(pmt, false) ? S_OK : S_FALSE;
}

STDMETHODIMP VCamPin::EnumMediaTypes(IEnumMediaTypes** ppEnum) {
  return CreateEnumMediaTypes(this, ppEnum);
}

STDMETHODIMP VCamPin::SetSink(IQualityControl* piqc) {
  if (quality_sink_ != nullptr) quality_sink_->Release();
  quality_sink_ = piqc;
  if (quality_sink_ != nullptr) quality_sink_->AddRef();
  return S_OK;
}

STDMETHODIMP VCamPin::SetFormat(AM_MEDIA_TYPE* pmt) {
  if (pmt == nullptr) return E_POINTER;
  if (!IsSupportedMediaType(pmt, false)) return VFW_E_INVALIDMEDIATYPE;
  filter_->Lock();
  HRESULT hr = S_OK;
  if (filter_->State() != State_Stopped) hr = VFW_E_NOT_STOPPED;
  else if (connected_pin_ && connected_pin_->QueryAccept(pmt) != S_OK) {
    hr = VFW_E_INVALIDMEDIATYPE;
  } else {
    hr = CopyMediaTypeFields(&configured_mt_, pmt);
  }
  filter_->Unlock();
  return hr;
}

STDMETHODIMP VCamPin::GetFormat(AM_MEDIA_TYPE** ppmt) {
  if (ppmt == nullptr) return E_POINTER;
  *ppmt = AllocMediaType(&configured_mt_);
  return *ppmt != nullptr ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP VCamPin::GetStreamCaps(int iIndex, AM_MEDIA_TYPE** ppmt,
                                    BYTE* pSCC) {
  if (ppmt == nullptr || pSCC == nullptr) return E_POINTER;
  if (iIndex < 0) return E_INVALIDARG;
  if (iIndex > 0) return S_FALSE;
  const HRESULT hr = GetFormat(ppmt);
  if (FAILED(hr)) return hr;
  auto* caps = reinterpret_cast<VIDEO_STREAM_CONFIG_CAPS*>(pSCC);
  std::memset(caps, 0, sizeof(VIDEO_STREAM_CONFIG_CAPS));
  caps->guid = FORMAT_VideoInfo;
  caps->InputSize = caps->MinCroppingSize = caps->MaxCroppingSize = {
      kVCamWidth, kVCamHeight};
  caps->MinOutputSize = caps->MaxOutputSize = {kVCamWidth, kVCamHeight};
  caps->CropGranularityX = caps->CropGranularityY = 1;
  caps->OutputGranularityX = caps->OutputGranularityY = 1;
  caps->MinFrameInterval = caps->MaxFrameInterval = kVCamFrameInterval100Ns;
  caps->MinBitsPerSecond = caps->MaxBitsPerSecond =
      static_cast<LONG>(kVCamFrameBytes * 8u * 30u);
  return S_OK;
}

STDMETHODIMP VCamPin::Get(REFGUID set, DWORD id, LPVOID, DWORD, LPVOID data,
                          DWORD cb, DWORD* ret) {
  if (set != AMPROPSETID_Pin) return E_PROP_SET_UNSUPPORTED;
  if (id != AMPROPERTY_PIN_CATEGORY) return E_PROP_ID_UNSUPPORTED;
  if (data == nullptr && ret == nullptr) return E_POINTER;
  if (ret != nullptr) *ret = sizeof(GUID);
  if (data == nullptr) return S_OK;
  if (cb < sizeof(GUID)) return E_UNEXPECTED;
  *reinterpret_cast<GUID*>(data) = PIN_CATEGORY_CAPTURE;
  return S_OK;
}

STDMETHODIMP VCamPin::QuerySupported(REFGUID set, DWORD id, DWORD* support) {
  if (set != AMPROPSETID_Pin) return E_PROP_SET_UNSUPPORTED;
  if (id != AMPROPERTY_PIN_CATEGORY) return E_PROP_ID_UNSUPPORTED;
  if (support != nullptr) *support = KSPROPERTY_SUPPORT_GET;
  return S_OK;
}

HRESULT VCamPin::Active() {
  if (!connected_pin_ || !mem_input_pin_ || !allocator_ || thread_handle_) return S_OK;
  const HRESULT hr = allocator_->Commit();
  if (FAILED(hr) && hr != VFW_E_ALREADY_COMMITTED) return hr;
  if (stop_event_) ::ResetEvent(stop_event_);
  filter_->AddRef();
  thread_handle_ = ::CreateThread(nullptr, 0, &VCamPin::StaticThreadProc, this, 0, &thread_id_);
  if (thread_handle_) return S_OK;
  filter_->Release();
  return HRESULT_FROM_WIN32(::GetLastError());
}

HRESULT VCamPin::Inactive() {
  if (stop_event_) ::SetEvent(stop_event_);
  if (allocator_) allocator_->Decommit();
  HANDLE h = thread_handle_;
  thread_handle_ = nullptr;
  const DWORD tid = thread_id_;
  thread_id_ = 0;
  if (h) {
    if (::GetCurrentThreadId() != tid) ::WaitForSingleObject(h, 5000);
    ::CloseHandle(h);
  }
  return S_OK;
}

DWORD WINAPI VCamPin::StaticThreadProc(LPVOID param) {
  if (auto* self = static_cast<VCamPin*>(param)) self->ThreadLoop();
  return 0;
}

void VCamPin::FillFrameBuffer(uint8_t* dst, uint32_t* retry_counter) {
  bool copied_live = false;
  uint32_t observed_state = kVCamStateStandby;
  if (!shared_mem_.View() && ((*retry_counter)++ % 15u == 0u)) {
    shared_mem_.Open(false, false);
  }
  if (shared_mem_.View() && shared_mem_.Lock(8)) {
    const VCamSharedFrame* f = shared_mem_.View();
    if (f && f->magic == kVCamMagic && f->version == kVCamVersion) {
      observed_state = f->state;
      const uint64_t now = ::GetTickCount64();
      if (f->state == kVCamStateStreaming &&
          (now < f->timestamp_ms || (now - f->timestamp_ms) <= kVCamStaleTimeoutMs)) {
        std::memcpy(dst, f->bgr24, kVCamFrameBytes);
        copied_live = true;
      }
    }
    shared_mem_.Unlock();
  }
  if (!copied_live) {
    const bool paused = (observed_state == kVCamStatePaused);
    std::vector<uint8_t>& slate = paused ? paused_slate_ : standby_slate_;
    if (slate.size() != kVCamFrameBytes) {
      slate.resize(kVCamFrameBytes);
      RenderVCamSlate(slate.data(), paused);
    }
    std::memcpy(dst, slate.data(), kVCamFrameBytes);
  }
}

void VCamPin::ThreadLoop() {
  const HRESULT co_hr = ::CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  uint64_t next_tick = ::GetTickCount64();
  LONGLONG frame_idx = 0;
  uint32_t retry_counter = 0;
  while (::WaitForSingleObject(stop_event_, 0) != WAIT_OBJECT_0) {
    IMediaSample* sample = nullptr;
    if (FAILED(allocator_->GetBuffer(&sample, nullptr, nullptr, 0)) || !sample) break;
    BYTE* dst = nullptr;
    if (SUCCEEDED(sample->GetPointer(&dst)) && dst &&
        sample->GetSize() >= static_cast<long>(kVCamFrameBytes)) {
      FillFrameBuffer(dst, &retry_counter);
      sample->SetActualDataLength(static_cast<long>(kVCamFrameBytes));
    }
    sample->SetSyncPoint(TRUE);
    sample->SetDiscontinuity(frame_idx == 0 ? TRUE : FALSE);
    REFERENCE_TIME rt0 = frame_idx++ * kVCamFrameInterval100Ns;
    REFERENCE_TIME rt1 = rt0 + kVCamFrameInterval100Ns;
    sample->SetTime(&rt0, &rt1);
    const HRESULT hr = mem_input_pin_->Receive(sample);
    sample->Release();
    if (hr == S_FALSE) break;
    if (FAILED(hr) && ::WaitForSingleObject(stop_event_, 10) == WAIT_OBJECT_0) break;
    next_tick += 33u;
    const uint64_t now = ::GetTickCount64();
    if (now < next_tick) {
      const DWORD ms = static_cast<DWORD>(next_tick - now);
      if (::WaitForSingleObject(stop_event_, ms) == WAIT_OBJECT_0) break;
    } else if (now - next_tick > 200u) {
      next_tick = now;
    }
  }
  shared_mem_.Close();
  if (SUCCEEDED(co_hr)) ::CoUninitialize();
  filter_->Release();
}

}  // namespace p2s_vcam
