#ifndef TRAY_MANAGER_WINDOWS_TRAY_MENU_H_
#define TRAY_MANAGER_WINDOWS_TRAY_MENU_H_

#include <cstdint>
#include <string>
#include <utility>
#include <vector>

namespace tray_manager {

struct MenuEntry {
  enum class Kind { item, separator, checkbox, submenu };
  Kind kind = Kind::item;
  std::uintptr_t id = 0;
  std::wstring label;
  bool disabled = false;
  bool checked = false;
  std::vector<MenuEntry> children;
};

// A successfully appended submenu belongs to its parent. Until then, the
// builder owns it so that every failure path can release the incomplete tree.
template <typename Api>
class OwnedMenu {
 public:
  using Handle = typename Api::Handle;
  explicit OwnedMenu(Handle handle = Handle{}) : handle_(handle) {}
  ~OwnedMenu() { Reset(); }
  OwnedMenu(const OwnedMenu&) = delete;
  OwnedMenu& operator=(const OwnedMenu&) = delete;
  OwnedMenu(OwnedMenu&& other) noexcept : handle_(other.Release()) {}
  OwnedMenu& operator=(OwnedMenu&& other) noexcept {
    if (this != &other) {
      Reset();
      handle_ = other.Release();
    }
    return *this;
  }

  Handle Get() const { return handle_; }
  explicit operator bool() const { return handle_ != Handle{}; }
  Handle Release() {
    const Handle handle = handle_;
    handle_ = Handle{};
    return handle;
  }
  void Reset() {
    if (handle_ != Handle{}) {
      Api::Destroy(handle_);
      handle_ = Handle{};
    }
  }

 private:
  Handle handle_;
};

enum class MenuBuildError { none, create, append };

template <typename Api>
struct MenuBuildResult {
  OwnedMenu<Api> menu;
  MenuBuildError error = MenuBuildError::none;
  unsigned long platform_error = 0;
};

template <typename Api>
MenuBuildResult<Api> BuildMenu(const std::vector<MenuEntry>& entries) {
  MenuBuildResult<Api> result;
  result.menu = OwnedMenu<Api>(Api::Create());
  if (!result.menu) {
    result.error = MenuBuildError::create;
    result.platform_error = Api::LastError();
    return result;
  }

  for (const auto& entry : entries) {
    OwnedMenu<Api> child;
    if (entry.kind == MenuEntry::Kind::submenu) {
      auto child_result = BuildMenu<Api>(entry.children);
      if (child_result.error != MenuBuildError::none) {
        result.error = child_result.error;
        result.platform_error = child_result.platform_error;
        result.menu.Reset();
        return result;
      }
      child = std::move(child_result.menu);
    }
    if (!Api::Append(result.menu.Get(), entry, child.Get())) {
      result.error = MenuBuildError::append;
      result.platform_error = Api::LastError();
      result.menu.Reset();
      return result;
    }
    // Append succeeded: the native parent now owns the whole child tree.
    child.Release();
  }
  return result;
}

template <typename Api>
class MenuState {
 public:
  using Handle = typename Api::Handle;
  Handle Current() const { return current_.Get(); }

  void Replace(OwnedMenu<Api> menu) {
    if (tracking_) {
      pending_ = std::move(menu);
      pending_update_ = true;
    } else {
      current_ = std::move(menu);
    }
  }
  void Clear() { Replace(OwnedMenu<Api>()); }

  bool BeginTracking() {
    if (tracking_ || !current_) return false;
    tracking_ = true;
    return true;
  }
  void EndTracking() {
    tracking_ = false;
    if (pending_update_) {
      current_ = std::move(pending_);
      pending_update_ = false;
    }
  }

 private:
  OwnedMenu<Api> current_;
  OwnedMenu<Api> pending_;
  bool tracking_ = false;
  bool pending_update_ = false;
};

// TrackPopupMenu can process WM_DESTROY inside its nested message loop. The
// caller keeps this lifetime on its stack even after the Flutter plugin dies.
template <typename Api>
struct MenuLifetime {
  MenuState<Api> menus;
  bool disposed = false;

  void Dispose() {
    disposed = true;
    menus.Clear();
  }
  bool Replace(OwnedMenu<Api> menu) {
    if (disposed) return false;
    menus.Replace(std::move(menu));
    return true;
  }
};

}  // namespace tray_manager

#endif  // TRAY_MANAGER_WINDOWS_TRAY_MENU_H_
