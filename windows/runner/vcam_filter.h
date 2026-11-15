#ifndef RUNNER_VCAM_FILTER_H_
#define RUNNER_VCAM_FILTER_H_

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#pragma warning(push, 3)
#include <dshow.h>
#include <objbase.h>
#pragma warning(pop)

#include <string>

namespace p2s_vcam {

extern volatile LONG g_vcam_object_count;
extern volatile LONG g_vcam_lock_count;

class VCamPin;

void FreeMediaTypeFields(AM_MEDIA_TYPE* mt);
void InitDefaultMediaType(AM_MEDIA_TYPE* mt);
HRESULT CopyMediaTypeFields(AM_MEDIA_TYPE* dst, const AM_MEDIA_TYPE* src);
AM_MEDIA_TYPE* AllocMediaType(const AM_MEDIA_TYPE* src);
bool IsSupportedMediaType(const AM_MEDIA_TYPE* pmt, bool allow_wildcards);
HRESULT CreateEnumMediaTypes(VCamPin* pin, IEnumMediaTypes** ppEnum);

// DirectShow live source filter exposing a single Phone2Screen capture pin.
class VCamFilter final : public IBaseFilter, public IAMFilterMiscFlags {
 public:
  VCamFilter();
  ~VCamFilter();

  VCamFilter(const VCamFilter&) = delete;
  VCamFilter& operator=(const VCamFilter&) = delete;

  void Lock() { ::EnterCriticalSection(&cs_); }
  void Unlock() { ::LeaveCriticalSection(&cs_); }
  FILTER_STATE State() const { return state_; }
  VCamPin* OutputPin() const { return pin_; }

  // IUnknown
  STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override;
  STDMETHODIMP_(ULONG) AddRef() override;
  STDMETHODIMP_(ULONG) Release() override;

  // IPersist
  STDMETHODIMP GetClassID(CLSID* pClassID) override;

  // IMediaFilter
  STDMETHODIMP Stop() override;
  STDMETHODIMP Pause() override;
  STDMETHODIMP Run(REFERENCE_TIME tStart) override;
  STDMETHODIMP GetState(DWORD dwMilliSecsTimeout, FILTER_STATE* State) override;
  STDMETHODIMP SetSyncSource(IReferenceClock* pClock) override;
  STDMETHODIMP GetSyncSource(IReferenceClock** pClock) override;

  // IBaseFilter
  STDMETHODIMP EnumPins(IEnumPins** ppEnum) override;
  STDMETHODIMP FindPin(LPCWSTR Id, IPin** ppPin) override;
  STDMETHODIMP QueryFilterInfo(FILTER_INFO* pInfo) override;
  STDMETHODIMP JoinFilterGraph(IFilterGraph* pGraph, LPCWSTR pName) override;
  STDMETHODIMP QueryVendorInfo(LPWSTR* pVendorInfo) override;

  // IAMFilterMiscFlags
  STDMETHODIMP_(ULONG) GetMiscFlags() override;

 private:
  volatile LONG ref_count_ = 1;
  CRITICAL_SECTION cs_{};
  FILTER_STATE state_ = State_Stopped;
  REFERENCE_TIME start_time_ = 0;
  IReferenceClock* clock_ = nullptr;
  IFilterGraph* graph_ = nullptr;  // Weak reference per DirectShow rules.
  std::wstring name_;
  VCamPin* pin_ = nullptr;
};

}  // namespace p2s_vcam

#endif  // RUNNER_VCAM_FILTER_H_
