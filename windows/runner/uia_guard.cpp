#include "uia_guard.h"

#include <commctrl.h>

#include <atomic>

namespace flclashx::uia_guard {

namespace {

constexpr UINT_PTR kUiaGuardSubclassId = 0x46435547u;  // 'FCUG'
constexpr WPARAM kSpiSetScreenReader = SPI_SETSCREENREADER;

std::atomic<const UiaPolicyProbes*> g_test_probes{nullptr};

bool DefaultReadEnv(const wchar_t* name,
                    wchar_t* buffer,
                    size_t capacity) noexcept {
  if (name == nullptr || buffer == nullptr || capacity == 0) {
    return false;
  }
  const DWORD written = ::GetEnvironmentVariableW(
      name, buffer, static_cast<DWORD>(capacity));
  if (written == 0 || written >= capacity) {
    return false;
  }
  buffer[written] = L'\0';
  return true;
}

bool DefaultIsScreenReaderActive() noexcept {
  BOOL active = FALSE;
  if (::SystemParametersInfoW(SPI_GETSCREENREADER, 0, &active, 0) == FALSE) {
    return false;
  }
  return active != FALSE;
}

const UiaPolicyProbes* EffectiveProbes(const UiaPolicyProbes* probes) noexcept {
  return probes != nullptr ? probes : g_test_probes.load(std::memory_order_acquire);
}

bool ReadEnvValue(const wchar_t* name,
                  wchar_t* buffer,
                  size_t capacity,
                  const UiaPolicyProbes* probes) noexcept {
  const UiaPolicyProbes* active_probes = EffectiveProbes(probes);
  if (active_probes != nullptr && active_probes->read_env != nullptr) {
    return active_probes->read_env(name, buffer, capacity);
  }
  return DefaultReadEnv(name, buffer, capacity);
}

bool QueryScreenReaderActive(const UiaPolicyProbes* probes) noexcept {
  const UiaPolicyProbes* active_probes = EffectiveProbes(probes);
  if (active_probes != nullptr &&
      active_probes->is_screen_reader_active != nullptr) {
    return active_probes->is_screen_reader_active();
  }
  return DefaultIsScreenReaderActive();
}

bool IsAsciiWhitespace(wchar_t ch) noexcept {
  return ch == L' ' || ch == L'\t' || ch == L'\r' || ch == L'\n';
}

wchar_t ToAsciiLower(wchar_t ch) noexcept {
  if (ch >= L'A' && ch <= L'Z') {
    return static_cast<wchar_t>(ch + (L'a' - L'A'));
  }
  return ch;
}

bool EqualsNormalized(const wchar_t* begin,
                      size_t length,
                      const wchar_t* literal) noexcept {
  size_t index = 0;
  while (index < length && literal[index] != L'\0') {
    if (ToAsciiLower(begin[index]) != literal[index]) {
      return false;
    }
    ++index;
  }
  return index == length && literal[index] == L'\0';
}

bool TryParseOverrideToken(const wchar_t* raw,
                           UiaModeOverride* out_override) noexcept {
  if (raw == nullptr || out_override == nullptr) {
    return false;
  }
  size_t start = 0;
  while (raw[start] != L'\0' && IsAsciiWhitespace(raw[start])) {
    ++start;
  }
  size_t end = start;
  while (raw[end] != L'\0') {
    ++end;
  }
  while (end > start && IsAsciiWhitespace(raw[end - 1])) {
    --end;
  }
  const size_t length = end - start;
  if (length == 0) {
    return false;
  }
  const wchar_t* token = raw + start;
  if (EqualsNormalized(token, length, L"allow") ||
      EqualsNormalized(token, length, L"1") ||
      EqualsNormalized(token, length, L"true") ||
      EqualsNormalized(token, length, L"on") ||
      EqualsNormalized(token, length, L"force")) {
    *out_override = UiaModeOverride::kForceAllow;
    return true;
  }
  if (EqualsNormalized(token, length, L"block") ||
      EqualsNormalized(token, length, L"0") ||
      EqualsNormalized(token, length, L"false") ||
      EqualsNormalized(token, length, L"off") ||
      EqualsNormalized(token, length, L"disable")) {
    *out_override = UiaModeOverride::kForceBlock;
    return true;
  }
  if (EqualsNormalized(token, length, L"auto") ||
      EqualsNormalized(token, length, L"default")) {
    *out_override = UiaModeOverride::kAuto;
    return true;
  }
  return false;
}

LRESULT CALLBACK FlutterUiaGuardSubclassProc(HWND hwnd,
                                             UINT message,
                                             WPARAM wparam,
                                             LPARAM lparam,
                                             UINT_PTR u_id_subclass,
                                             DWORD_PTR dw_ref_data) noexcept {
  (void)dw_ref_data;
  if (ShouldInterceptWindowMessageForUiaGuard(message, wparam, lparam)) {
    if (message == WM_GETOBJECT) {
      return ::DefWindowProcW(hwnd, message, wparam, lparam);
    }
    return 0;
  }

  if (message == WM_NCDESTROY) {
    ::RemoveWindowSubclass(hwnd, &FlutterUiaGuardSubclassProc, u_id_subclass);
    return ::DefSubclassProc(hwnd, message, wparam, lparam);
  }

  const LRESULT result = ::DefSubclassProc(hwnd, message, wparam, lparam);
  if (message == WM_PARENTNOTIFY && LOWORD(wparam) == WM_CREATE) {
    HWND child_hwnd = reinterpret_cast<HWND>(lparam);
    if (child_hwnd != nullptr && ::IsWindow(child_hwnd) != FALSE) {
      InstallFlutterWindowTreeUiaGuard(child_hwnd);
    }
  }
  return result;
}

BOOL CALLBACK InstallChildUiaGuardProc(HWND child_hwnd, LPARAM lparam) noexcept {
  bool* all_ok = reinterpret_cast<bool*>(lparam);
  if (!InstallFlutterViewUiaGuard(child_hwnd) && all_ok != nullptr) {
    *all_ok = false;
  }
  return TRUE;
}

BOOL CALLBACK UninstallChildUiaGuardProc(HWND child_hwnd, LPARAM lparam) noexcept {
  (void)lparam;
  if (child_hwnd != nullptr && ::IsWindow(child_hwnd) != FALSE) {
    ::RemoveWindowSubclass(child_hwnd, &FlutterUiaGuardSubclassProc,
                           kUiaGuardSubclassId);
  }
  return TRUE;
}

}  // namespace

UiaModeOverride ResolveUiaModeOverride(
    const UiaPolicyProbes* probes) noexcept {
  wchar_t buffer[64] = {};
  if (ReadEnvValue(L"FLCLASHX_UIA_MODE", buffer, sizeof(buffer) / sizeof(buffer[0]),
                   probes)) {
    UiaModeOverride parsed = UiaModeOverride::kAuto;
    if (TryParseOverrideToken(buffer, &parsed)) {
      return parsed;
    }
  }
  if (ReadEnvValue(L"FLCLASHX_FORCE_UIA", buffer, sizeof(buffer) / sizeof(buffer[0]),
                   probes)) {
    UiaModeOverride parsed = UiaModeOverride::kAuto;
    if (TryParseOverrideToken(buffer, &parsed)) {
      return parsed;
    }
  }
  return UiaModeOverride::kAuto;
}

bool ShouldAllowFlutterUiaBridge(const UiaPolicyProbes* probes) noexcept {
  switch (ResolveUiaModeOverride(probes)) {
    case UiaModeOverride::kForceAllow:
      return true;
    case UiaModeOverride::kForceBlock:
      return false;
    case UiaModeOverride::kAuto:
      return QueryScreenReaderActive(probes);
  }
  return false;
}

bool ShouldInterceptWindowMessageForUiaGuard(
    UINT message,
    WPARAM wparam,
    LPARAM lparam,
    const UiaPolicyProbes* probes) noexcept {
  (void)lparam;
  if (message == WM_GETOBJECT) {
    return !ShouldAllowFlutterUiaBridge(probes);
  }
  if (message == WM_SETTINGCHANGE && wparam == kSpiSetScreenReader) {
    return ResolveUiaModeOverride(probes) == UiaModeOverride::kForceBlock;
  }
  return false;
}

void SetUiaPolicyProbesForTesting(const UiaPolicyProbes* probes) noexcept {
  g_test_probes.store(probes, std::memory_order_release);
}

bool InstallFlutterViewUiaGuard(HWND hwnd) noexcept {
  if (hwnd == nullptr || ::IsWindow(hwnd) == FALSE) {
    return false;
  }
  DWORD_PTR existing_ref = 0;
  if (::GetWindowSubclass(hwnd, &FlutterUiaGuardSubclassProc, kUiaGuardSubclassId,
                          &existing_ref) != FALSE) {
    return true;
  }
  return ::SetWindowSubclass(hwnd, &FlutterUiaGuardSubclassProc,
                             kUiaGuardSubclassId, 0) != FALSE;
}

bool InstallFlutterWindowTreeUiaGuard(HWND root_hwnd) noexcept {
  if (!InstallFlutterViewUiaGuard(root_hwnd)) {
    return false;
  }
  bool all_ok = true;
  ::EnumChildWindows(root_hwnd, &InstallChildUiaGuardProc,
                     reinterpret_cast<LPARAM>(&all_ok));
  return all_ok;
}

void UninstallFlutterWindowTreeUiaGuard(HWND root_hwnd) noexcept {
  if (root_hwnd == nullptr || ::IsWindow(root_hwnd) == FALSE) {
    return;
  }
  ::EnumChildWindows(root_hwnd, &UninstallChildUiaGuardProc, 0);
  ::RemoveWindowSubclass(root_hwnd, &FlutterUiaGuardSubclassProc,
                         kUiaGuardSubclassId);
}

}  // namespace flclashx::uia_guard
