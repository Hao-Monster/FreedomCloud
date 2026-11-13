#include "uia_guard.h"

#include <cstdio>
#include <cstring>

namespace {

constexpr LRESULT kMockUiaProviderSentinel = static_cast<LRESULT>(0x55AA1234L);
constexpr LRESULT kMockSettingChangeSentinel = static_cast<LRESULT>(0x11223344L);
constexpr LRESULT kMockPassthroughSentinel = static_cast<LRESULT>(0x00ABCDEF);
constexpr LPARAM kUiaRootObjectId = static_cast<LPARAM>(-25L);

struct MockEnvState {
  const wchar_t* uia_mode = nullptr;
  const wchar_t* force_uia = nullptr;
  bool screen_reader_active = false;
};

MockEnvState g_mock_env;

struct ProbeWindowState {
  int wm_getobject_hits = 0;
  int wm_settingchange_screenreader_hits = 0;
  int passthrough_hits = 0;
  UINT last_message = 0;
  WPARAM last_wparam = 0;
  LPARAM last_lparam = 0;
};

bool MockReadEnv(const wchar_t* name, wchar_t* buffer, size_t capacity) noexcept {
  if (name == nullptr || buffer == nullptr || capacity == 0) {
    return false;
  }
  const wchar_t* value = nullptr;
  if (::lstrcmpW(name, L"FLCLASHX_UIA_MODE") == 0) {
    value = g_mock_env.uia_mode;
  } else if (::lstrcmpW(name, L"FLCLASHX_FORCE_UIA") == 0) {
    value = g_mock_env.force_uia;
  }
  if (value == nullptr) {
    return false;
  }
  const size_t len = static_cast<size_t>(::lstrlenW(value));
  if (len == 0 || len >= capacity) {
    return false;
  }
  ::memcpy(buffer, value, (len + 1) * sizeof(wchar_t));
  return true;
}

bool MockIsScreenReaderActive() noexcept {
  return g_mock_env.screen_reader_active;
}

const flclashx::uia_guard::UiaPolicyProbes kMockProbes = {
    &MockReadEnv,
    &MockIsScreenReaderActive,
};

LRESULT CALLBACK MockFlutterWindowProc(HWND hwnd,
                                       UINT message,
                                       WPARAM wparam,
                                       LPARAM lparam) noexcept {
  auto* state = reinterpret_cast<ProbeWindowState*>(
      ::GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (state != nullptr) {
    state->last_message = message;
    state->last_wparam = wparam;
    state->last_lparam = lparam;
    if (message == WM_GETOBJECT) {
      state->wm_getobject_hits++;
      return kMockUiaProviderSentinel;
    }
    if (message == WM_SETTINGCHANGE && wparam == SPI_SETSCREENREADER) {
      state->wm_settingchange_screenreader_hits++;
      return kMockSettingChangeSentinel;
    }
    if (message == WM_IME_SETCONTEXT ||
        message == WM_IME_STARTCOMPOSITION ||
        message == WM_IME_COMPOSITION ||
        message == WM_CHAR ||
        message == WM_KEYDOWN ||
        message == WM_MOUSEMOVE ||
        message == WM_MOUSEWHEEL ||
        message == WM_SETFOCUS ||
        message == WM_DPICHANGED ||
        message == WM_SIZE) {
      state->passthrough_hits++;
      return kMockPassthroughSentinel + static_cast<LRESULT>(message);
    }
  }
  return ::DefWindowProcW(hwnd, message, wparam, lparam);
}

bool RegisterProbeWindowClass(HINSTANCE instance, const wchar_t* class_name) noexcept {
  WNDCLASSEXW wc = {};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = &MockFlutterWindowProc;
  wc.hInstance = instance;
  wc.lpszClassName = class_name;
  return ::RegisterClassExW(&wc) != 0 || ::GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

bool ExpectTrue(bool condition, const char* expr, int line) noexcept {
  if (!condition) {
    std::fprintf(stderr, "FAIL line %d: %s\n", line, expr);
    return false;
  }
  return true;
}

#define EXPECT_TRUE(cond)                  \
  do {                                     \
    if (!ExpectTrue((cond), #cond, __LINE__)) { \
      return false;                        \
    }                                      \
  } while (false)

struct ScopedWindowTree {
  HWND root = nullptr;
  HWND child = nullptr;
  ~ScopedWindowTree() {
    if (root != nullptr && ::IsWindow(root)) {
      ::DestroyWindow(root);
      root = nullptr;
      child = nullptr;
    }
  }
};

bool CreateMockFlutterTree(HINSTANCE instance,
                           const wchar_t* class_name,
                           ProbeWindowState* root_state,
                           ProbeWindowState* child_state,
                           ScopedWindowTree* tree) noexcept {
  tree->root = ::CreateWindowExW(
      0, class_name, L"MockRoot", WS_OVERLAPPEDWINDOW,
      0, 0, 320, 240, nullptr, nullptr, instance, nullptr);
  EXPECT_TRUE(tree->root != nullptr);
  ::SetWindowLongPtrW(tree->root, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(root_state));

  tree->child = ::CreateWindowExW(
      0, class_name, L"MockFlutterView", WS_CHILD,
      0, 0, 320, 240, tree->root, nullptr, instance, nullptr);
  EXPECT_TRUE(tree->child != nullptr);
  ::SetWindowLongPtrW(tree->child, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(child_state));
  return true;
}

bool TestCase1DefaultBlocksNonScreenReaderUia(HINSTANCE instance,
                                              const wchar_t* class_name) noexcept {
  g_mock_env = {};
  flclashx::uia_guard::SetUiaPolicyProbesForTesting(&kMockProbes);

  EXPECT_TRUE(flclashx::uia_guard::ResolveUiaModeOverride(&kMockProbes) ==
              flclashx::uia_guard::UiaModeOverride::kAuto);
  EXPECT_TRUE(!flclashx::uia_guard::ShouldAllowFlutterUiaBridge(&kMockProbes));
  EXPECT_TRUE(flclashx::uia_guard::ShouldInterceptWindowMessageForUiaGuard(
      WM_GETOBJECT, 0, kUiaRootObjectId, &kMockProbes));

  ProbeWindowState root_state;
  ProbeWindowState child_state;
  ScopedWindowTree tree;
  EXPECT_TRUE(CreateMockFlutterTree(instance, class_name, &root_state, &child_state, &tree));
  EXPECT_TRUE(flclashx::uia_guard::InstallFlutterWindowTreeUiaGuard(tree.root));

  const LRESULT root_root_id = ::SendMessageW(tree.root, WM_GETOBJECT, 0, kUiaRootObjectId);
  const LRESULT view_root_id = ::SendMessageW(tree.child, WM_GETOBJECT, 0, kUiaRootObjectId);
  const LRESULT view_client_id = ::SendMessageW(
      tree.child, WM_GETOBJECT, 0, static_cast<LPARAM>(OBJID_CLIENT));

  EXPECT_TRUE(root_root_id == 0);
  EXPECT_TRUE(view_root_id == 0);
  EXPECT_TRUE(view_client_id == 0);
  EXPECT_TRUE(root_state.wm_getobject_hits == 0);
  EXPECT_TRUE(child_state.wm_getobject_hits == 0);

  flclashx::uia_guard::UninstallFlutterWindowTreeUiaGuard(tree.root);
  return true;
}

bool TestCase2ScreenReaderActiveAllowsUia(HINSTANCE instance,
                                          const wchar_t* class_name) noexcept {
  g_mock_env = {};
  g_mock_env.screen_reader_active = true;
  flclashx::uia_guard::SetUiaPolicyProbesForTesting(&kMockProbes);

  EXPECT_TRUE(flclashx::uia_guard::ShouldAllowFlutterUiaBridge(&kMockProbes));

  ProbeWindowState root_state;
  ProbeWindowState child_state;
  ScopedWindowTree tree;
  EXPECT_TRUE(CreateMockFlutterTree(instance, class_name, &root_state, &child_state, &tree));
  EXPECT_TRUE(flclashx::uia_guard::InstallFlutterWindowTreeUiaGuard(tree.root));

  const LRESULT view_res = ::SendMessageW(tree.child, WM_GETOBJECT, 0, kUiaRootObjectId);
  EXPECT_TRUE(view_res == kMockUiaProviderSentinel);
  EXPECT_TRUE(child_state.wm_getobject_hits == 1);

  flclashx::uia_guard::UninstallFlutterWindowTreeUiaGuard(tree.root);
  return true;
}

bool TestCase3EnvOverrideMatrix(HINSTANCE instance,
                                const wchar_t* class_name) noexcept {
  flclashx::uia_guard::SetUiaPolicyProbesForTesting(&kMockProbes);

  ProbeWindowState root_state;
  ProbeWindowState child_state;
  ScopedWindowTree tree;
  EXPECT_TRUE(CreateMockFlutterTree(instance, class_name, &root_state, &child_state, &tree));
  EXPECT_TRUE(flclashx::uia_guard::InstallFlutterWindowTreeUiaGuard(tree.root));

  // Force allow even when screen_reader_active == false, including case/whitespace.
  g_mock_env = {L" Allow ", nullptr, false};
  EXPECT_TRUE(flclashx::uia_guard::ResolveUiaModeOverride(&kMockProbes) ==
              flclashx::uia_guard::UiaModeOverride::kForceAllow);
  EXPECT_TRUE(::SendMessageW(tree.child, WM_GETOBJECT, 0, kUiaRootObjectId) ==
              kMockUiaProviderSentinel);
  EXPECT_TRUE(child_state.wm_getobject_hits == 1);

  g_mock_env = {nullptr, L"1", false};
  EXPECT_TRUE(flclashx::uia_guard::ResolveUiaModeOverride(&kMockProbes) ==
              flclashx::uia_guard::UiaModeOverride::kForceAllow);
  EXPECT_TRUE(::SendMessageW(tree.child, WM_GETOBJECT, 0, kUiaRootObjectId) ==
              kMockUiaProviderSentinel);
  EXPECT_TRUE(child_state.wm_getobject_hits == 2);

  // Force block even when screen_reader_active == true, including WM_SETTINGCHANGE.
  g_mock_env = {L"BLOCK", nullptr, true};
  EXPECT_TRUE(flclashx::uia_guard::ResolveUiaModeOverride(&kMockProbes) ==
              flclashx::uia_guard::UiaModeOverride::kForceBlock);
  EXPECT_TRUE(::SendMessageW(tree.child, WM_GETOBJECT, 0, kUiaRootObjectId) == 0);
  EXPECT_TRUE(::SendMessageW(tree.child, WM_SETTINGCHANGE, SPI_SETSCREENREADER, 0) == 0);
  EXPECT_TRUE(child_state.wm_getobject_hits == 2);
  EXPECT_TRUE(child_state.wm_settingchange_screenreader_hits == 0);

  g_mock_env = {nullptr, L"0", true};
  EXPECT_TRUE(flclashx::uia_guard::ResolveUiaModeOverride(&kMockProbes) ==
              flclashx::uia_guard::UiaModeOverride::kForceBlock);
  EXPECT_TRUE(::SendMessageW(tree.child, WM_GETOBJECT, 0, kUiaRootObjectId) == 0);
  EXPECT_TRUE(child_state.wm_getobject_hits == 2);

  // Auto mode forwards SPI_SETSCREENREADER WM_SETTINGCHANGE normally.
  g_mock_env = {L"auto", nullptr, false};
  EXPECT_TRUE(flclashx::uia_guard::ResolveUiaModeOverride(&kMockProbes) ==
              flclashx::uia_guard::UiaModeOverride::kAuto);
  EXPECT_TRUE(::SendMessageW(tree.child, WM_SETTINGCHANGE, SPI_SETSCREENREADER, 0) ==
              kMockSettingChangeSentinel);
  EXPECT_TRUE(child_state.wm_settingchange_screenreader_hits == 1);

  flclashx::uia_guard::UninstallFlutterWindowTreeUiaGuard(tree.root);
  return true;
}

bool TestCase4PassthroughMessagesUntouched(HINSTANCE instance,
                                           const wchar_t* class_name) noexcept {
  g_mock_env = {};
  flclashx::uia_guard::SetUiaPolicyProbesForTesting(&kMockProbes);

  ProbeWindowState root_state;
  ProbeWindowState child_state;
  ScopedWindowTree tree;
  EXPECT_TRUE(CreateMockFlutterTree(instance, class_name, &root_state, &child_state, &tree));
  EXPECT_TRUE(flclashx::uia_guard::InstallFlutterWindowTreeUiaGuard(tree.root));

  struct MsgCase {
    UINT msg;
    WPARAM wp;
    LPARAM lp;
  };
  const MsgCase cases[] = {
      {WM_IME_SETCONTEXT, 1, static_cast<LPARAM>(ISC_SHOWUICOMPOSITIONWINDOW)},
      {WM_IME_STARTCOMPOSITION, 0, 0},
      {WM_IME_COMPOSITION, 0x4E2D, GCS_COMPSTR},
      {WM_CHAR, L'A', 1},
      {WM_KEYDOWN, VK_RETURN, 0x001C0001},
      {WM_MOUSEMOVE, MK_LBUTTON, MAKELPARAM(42, 84)},
      {WM_MOUSEWHEEL, MAKEWPARAM(0, WHEEL_DELTA), MAKELPARAM(100, 120)},
      {WM_SETFOCUS, 0, 0},
      {WM_DPICHANGED, MAKEWPARAM(144, 144), 0},
      {WM_SIZE, SIZE_RESTORED, MAKELPARAM(800, 600)},
  };

  int expected_hits = 0;
  for (const auto& item : cases) {
    const LRESULT res = ::SendMessageW(tree.child, item.msg, item.wp, item.lp);
    expected_hits++;
    EXPECT_TRUE(res == kMockPassthroughSentinel + static_cast<LRESULT>(item.msg));
    EXPECT_TRUE(child_state.passthrough_hits == expected_hits);
    EXPECT_TRUE(child_state.last_message == item.msg);
    EXPECT_TRUE(child_state.last_wparam == item.wp);
    EXPECT_TRUE(child_state.last_lparam == item.lp);
  }

  flclashx::uia_guard::UninstallFlutterWindowTreeUiaGuard(tree.root);
  return true;
}

bool TestCase5IdempotentDynamicChildAndDestroyLifecycle(
    HINSTANCE instance,
    const wchar_t* class_name) noexcept {
  g_mock_env = {};
  flclashx::uia_guard::SetUiaPolicyProbesForTesting(&kMockProbes);

  ProbeWindowState root_state;
  ProbeWindowState child_state;
  ScopedWindowTree tree;
  EXPECT_TRUE(CreateMockFlutterTree(instance, class_name, &root_state, &child_state, &tree));

  // Repeated installation must remain idempotent and never crash.
  EXPECT_TRUE(flclashx::uia_guard::InstallFlutterWindowTreeUiaGuard(tree.root));
  EXPECT_TRUE(flclashx::uia_guard::InstallFlutterWindowTreeUiaGuard(tree.root));
  EXPECT_TRUE(flclashx::uia_guard::InstallFlutterViewUiaGuard(tree.child));

  // Dynamic child window created after initial install triggers WM_PARENTNOTIFY(WM_CREATE).
  ProbeWindowState dynamic_child_state;
  HWND dynamic_child = ::CreateWindowExW(
      0, class_name, L"DynamicFlutterView", WS_CHILD,
      0, 0, 120, 80, tree.root, nullptr, instance, nullptr);
  EXPECT_TRUE(dynamic_child != nullptr);
  ::SetWindowLongPtrW(dynamic_child, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(&dynamic_child_state));

  const LRESULT dyn_res = ::SendMessageW(dynamic_child, WM_GETOBJECT, 0, kUiaRootObjectId);
  EXPECT_TRUE(dyn_res == 0);
  EXPECT_TRUE(dynamic_child_state.wm_getobject_hits == 0);

  // Destruction via DestroyWindow handles WM_NCDESTROY cleanly.
  EXPECT_TRUE(::DestroyWindow(tree.root) != FALSE);
  tree.root = nullptr;
  tree.child = nullptr;
  return true;
}

}  // namespace

int main() {
  HINSTANCE instance = ::GetModuleHandleW(nullptr);
  const wchar_t* kClassName = L"FlClashXUiaGuardProbeWindow";
  if (!RegisterProbeWindowClass(instance, kClassName)) {
    std::fprintf(stderr, "Failed to register test window class\n");
    return 1;
  }

  const bool all_passed =
      TestCase1DefaultBlocksNonScreenReaderUia(instance, kClassName) &&
      TestCase2ScreenReaderActiveAllowsUia(instance, kClassName) &&
      TestCase3EnvOverrideMatrix(instance, kClassName) &&
      TestCase4PassthroughMessagesUntouched(instance, kClassName) &&
      TestCase5IdempotentDynamicChildAndDestroyLifecycle(instance, kClassName);

  flclashx::uia_guard::SetUiaPolicyProbesForTesting(nullptr);
  std::printf("flclashx_uia_guard_test: %s\n", all_passed ? "PASS" : "FAIL");
  return all_passed ? 0 : 1;
}
