#ifndef TRAY_MANAGER_WINDOWS_TRAY_ICON_REGISTRATION_H_
#define TRAY_MANAGER_WINDOWS_TRAY_ICON_REGISTRATION_H_

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

}  // namespace tray_manager

#endif  // TRAY_MANAGER_WINDOWS_TRAY_ICON_REGISTRATION_H_
