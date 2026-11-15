#ifndef RUNNER_VCAM_PIN_H_
#define RUNNER_VCAM_PIN_H_

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#pragma warning(push, 3)
#include <dshow.h>
#include <objbase.h>
#pragma warning(pop)

#include <cstdint>
#include <vector>

#include "vcam_shared_mem.h"

namespace p2s_vcam {

class VCamFilter;

// DirectShow output capture pin exposing 1280x720@30fps RGB24 frames from
// `Local\Phone2ScreenVCamSharedV1` with procedural standby/privacy slates.
class VCamPin final : public IPin,
                      public IQualityControl,
                      public IAMStreamConfig,
                      public IKsPropertySet {
 public:
  explicit VCamPin(VCamFilter* filter);
  ~VCamPin();

  VCamPin(const VCamPin&) = delete;
  VCamPin& operator=(const VCamPin&) = delete;

  HRESULT Active();
  HRESULT Inactive();

  // IUnknown (delegates refcounting to owning VCamFilter aggregate)
  STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override;
  STDMETHODIMP_(ULONG) AddRef() override;
  STDMETHODIMP_(ULONG) Release() override;

  // IPin
  STDMETHODIMP Connect(IPin* pReceivePin, const AM_MEDIA_TYPE* pmt) override;
  STDMETHODIMP ReceiveConnection(IPin*, const AM_MEDIA_TYPE*) override {
    return E_UNEXPECTED;
  }
  STDMETHODIMP Disconnect() override;
  STDMETHODIMP ConnectedTo(IPin** pPin) override;
  STDMETHODIMP ConnectionMediaType(AM_MEDIA_TYPE* pmt) override;
  STDMETHODIMP QueryPinInfo(PIN_INFO* pInfo) override;
  STDMETHODIMP QueryDirection(PIN_DIRECTION* d) override {
    if (d == nullptr) return E_POINTER;
    *d = PINDIR_OUTPUT;
    return S_OK;
  }
  STDMETHODIMP QueryId(LPWSTR* Id) override;
  STDMETHODIMP QueryAccept(const AM_MEDIA_TYPE* pmt) override;
  STDMETHODIMP EnumMediaTypes(IEnumMediaTypes** ppEnum) override;
  STDMETHODIMP QueryInternalConnections(IPin**, ULONG*) override {
    return E_NOTIMPL;
  }
  STDMETHODIMP EndOfStream() override { return E_UNEXPECTED; }
  STDMETHODIMP BeginFlush() override { return E_UNEXPECTED; }
  STDMETHODIMP EndFlush() override { return E_UNEXPECTED; }
  STDMETHODIMP NewSegment(REFERENCE_TIME, REFERENCE_TIME, double) override {
    return E_UNEXPECTED;
  }

  // IQualityControl
  STDMETHODIMP Notify(IBaseFilter*, Quality) override { return S_OK; }
  STDMETHODIMP SetSink(IQualityControl* piqc) override;

  // IAMStreamConfig
  STDMETHODIMP SetFormat(AM_MEDIA_TYPE* pmt) override;
  STDMETHODIMP GetFormat(AM_MEDIA_TYPE** ppmt) override;
  STDMETHODIMP GetNumberOfCapabilities(int* piCount, int* piSize) override {
    if (piCount == nullptr || piSize == nullptr) return E_POINTER;
    *piCount = 1;
    *piSize = sizeof(VIDEO_STREAM_CONFIG_CAPS);
    return S_OK;
  }
  STDMETHODIMP GetStreamCaps(int iIndex, AM_MEDIA_TYPE** ppmt,
                             BYTE* pSCC) override;

  // IKsPropertySet
  STDMETHODIMP Set(REFGUID, DWORD, LPVOID, DWORD, LPVOID, DWORD) override {
    return E_NOTIMPL;
  }
  STDMETHODIMP Get(REFGUID guidPropSet, DWORD dwPropID, LPVOID, DWORD,
                   LPVOID pPropData, DWORD cbPropData,
                   DWORD* pcbReturned) override;
  STDMETHODIMP QuerySupported(REFGUID guidPropSet, DWORD dwPropID,
                              DWORD* pTypeSupport) override;

 private:
  static DWORD WINAPI StaticThreadProc(LPVOID param);
  void ThreadLoop();
  void FillFrameBuffer(uint8_t* dst, uint32_t* retry_counter);

  VCamFilter* filter_ = nullptr;
  IPin* connected_pin_ = nullptr;
  IMemInputPin* mem_input_pin_ = nullptr;
  IMemAllocator* allocator_ = nullptr;
  IQualityControl* quality_sink_ = nullptr;
  AM_MEDIA_TYPE configured_mt_{};
  AM_MEDIA_TYPE current_mt_{};
  HANDLE stop_event_ = nullptr;
  HANDLE thread_handle_ = nullptr;
  DWORD thread_id_ = 0;
  VCamSharedMem shared_mem_;
  std::vector<uint8_t> standby_slate_;
  std::vector<uint8_t> paused_slate_;
};

}  // namespace p2s_vcam

#endif  // RUNNER_VCAM_PIN_H_
