#ifndef RUNNER_UIA_GUARD_H_
#define RUNNER_UIA_GUARD_H_

#include <windows.h>

#include <cstddef>

namespace flclashx::uia_guard {

enum class UiaModeOverride {
  kAuto = 0,
  kForceAllow = 1,
  kForceBlock = 2,
};

struct UiaPolicyProbes {
  bool (*read_env)(const wchar_t* name, wchar_t* buffer, size_t capacity) noexcept;
  bool (*is_screen_reader_active)() noexcept;
};

UiaModeOverride ResolveUiaModeOverride(
    const UiaPolicyProbes* probes = nullptr) noexcept;

bool ShouldAllowFlutterUiaBridge(
    const UiaPolicyProbes* probes = nullptr) noexcept;

bool ShouldInterceptWindowMessageForUiaGuard(
    UINT message,
    WPARAM wparam,
    LPARAM lparam,
    const UiaPolicyProbes* probes = nullptr) noexcept;

void SetUiaPolicyProbesForTesting(const UiaPolicyProbes* probes) noexcept;

bool InstallFlutterViewUiaGuard(HWND hwnd) noexcept;

bool InstallFlutterWindowTreeUiaGuard(HWND root_hwnd) noexcept;

void UninstallFlutterWindowTreeUiaGuard(HWND root_hwnd) noexcept;

}  // namespace flclashx::uia_guard

#endif  // RUNNER_UIA_GUARD_H_
