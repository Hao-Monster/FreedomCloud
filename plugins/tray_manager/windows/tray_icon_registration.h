#ifndef TRAY_MANAGER_WINDOWS_TRAY_ICON_REGISTRATION_H_
#define TRAY_MANAGER_WINDOWS_TRAY_ICON_REGISTRATION_H_

#include <cstddef>
#include <map>
#include <string>

namespace tray_manager {

enum class IconOperation { add, modify };

// A failed modify does not tell us whether Shell still owns the icon. Trying
// add and then modify recovers both missing and already-registered identities.
template <typename Notify>
bool RefreshIconRegistration(bool& registered, Notify notify) {
  const bool was_registered = registered;
  registered = false;
  if ((was_registered && notify(IconOperation::modify)) ||
      notify(IconOperation::add) || notify(IconOperation::modify)) {
    registered = true;
  }
  return registered;
}

template <typename Api, std::size_t kMaxEntries = 16>
class IconHandleCache {
 public:
  using Handle = typename Api::Handle;

  IconHandleCache() = default;
  IconHandleCache(const IconHandleCache&) = delete;
  IconHandleCache& operator=(const IconHandleCache&) = delete;

  ~IconHandleCache() { Clear(); }

  Handle Get(const std::string& path) const {
    const auto found = entries_.find(path);
    return found == entries_.end() ? Api::Null() : found->second;
  }

  bool ContainsHandle(Handle handle) const {
    if (handle == Api::Null()) {
      return false;
    }
    for (const auto& entry : entries_) {
      if (entry.second == handle) {
        return true;
      }
    }
    return false;
  }

  void Put(const std::string& path, Handle icon, Handle active_icon) {
    if (icon == Api::Null()) {
      return;
    }
    auto existing = entries_.find(path);
    if (existing != entries_.end()) {
      if (existing->second != Api::Null() && existing->second != icon &&
          existing->second != active_icon) {
        Api::Destroy(existing->second);
      }
      existing->second = icon;
      return;
    }
    if (entries_.size() >= kMaxEntries) {
      for (auto it = entries_.begin(); it != entries_.end(); ++it) {
        if (it->second != active_icon && it->second != icon) {
          if (it->second != Api::Null()) {
            Api::Destroy(it->second);
          }
          entries_.erase(it);
          break;
        }
      }
    }
    entries_.emplace(path, icon);
  }

  void Clear() {
    for (auto& entry : entries_) {
      if (entry.second != Api::Null()) {
        Api::Destroy(entry.second);
      }
    }
    entries_.clear();
  }

  std::size_t Size() const { return entries_.size(); }

 private:
  std::map<std::string, Handle> entries_;
};

}  // namespace tray_manager

#endif  // TRAY_MANAGER_WINDOWS_TRAY_ICON_REGISTRATION_H_
