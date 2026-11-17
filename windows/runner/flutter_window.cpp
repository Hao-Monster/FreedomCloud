#include "flutter_window.h"

#include <desktop_multi_window/desktop_multi_window_plugin.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "uia_guard.h"

namespace {

void OnSecondaryFlutterWindowCreated(void* raw_controller) noexcept {
  if (raw_controller == nullptr) {
    return;
  }
  auto* controller = static_cast<flutter::FlutterViewController*>(raw_controller);
  flutter::FlutterView* view = controller->view();
  if (view == nullptr) {
    return;
  }
  HWND view_hwnd = view->GetNativeWindow();
  flclashx::uia_guard::InstallFlutterWindowTreeUiaGuard(view_hwnd);
  HWND root_hwnd = ::GetAncestor(view_hwnd, GA_ROOT);
  if (root_hwnd != nullptr && root_hwnd != view_hwnd) {
    flclashx::uia_guard::InstallFlutterWindowTreeUiaGuard(root_hwnd);
  }
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  DesktopMultiWindowSetWindowCreatedCallback(&OnSecondaryFlutterWindowCreated);

  HWND view_hwnd = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(view_hwnd);
  flclashx::uia_guard::InstallFlutterWindowTreeUiaGuard(GetHandle());
  flclashx::uia_guard::InstallFlutterWindowTreeUiaGuard(view_hwnd);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {

  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  flclashx::uia_guard::UninstallFlutterWindowTreeUiaGuard(GetHandle());

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (flclashx::uia_guard::ShouldInterceptWindowMessageForUiaGuard(
          message, wparam, lparam)) {
    if (message == WM_GETOBJECT) {
      return ::DefWindowProcW(hwnd, message, wparam, lparam);
    }
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
