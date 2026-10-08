#ifndef TRAY_MANAGER_WINDOWS_TRAY_MENU_WIN32_H_
#define TRAY_MANAGER_WINDOWS_TRAY_MENU_WIN32_H_

#include <windows.h>

#include "tray_menu.h"

namespace tray_manager {

struct Win32MenuApi {
  using Handle = HMENU;
  static Handle Create() {
    SetLastError(ERROR_SUCCESS);
    return CreatePopupMenu();
  }
  static bool Append(Handle parent, const MenuEntry& entry, Handle child) {
    UINT flags = MF_STRING;
    UINT_PTR id = static_cast<UINT_PTR>(entry.id);
    if (entry.disabled) flags |= MF_GRAYED;
    if (entry.kind == MenuEntry::Kind::separator) {
      flags = MF_SEPARATOR;
    } else if (entry.kind == MenuEntry::Kind::checkbox) {
      flags |= entry.checked ? MF_CHECKED : MF_UNCHECKED;
    } else if (entry.kind == MenuEntry::Kind::submenu) {
      flags |= MF_POPUP;
      id = reinterpret_cast<UINT_PTR>(child);
    }
    SetLastError(ERROR_SUCCESS);
    return AppendMenuW(parent, flags, id,
                       entry.kind == MenuEntry::Kind::separator
                           ? nullptr
                           : entry.label.c_str()) != FALSE;
  }
  static void Destroy(Handle handle) { DestroyMenu(handle); }
  static unsigned long LastError() { return GetLastError(); }
};

}  // namespace tray_manager

#endif  // TRAY_MANAGER_WINDOWS_TRAY_MENU_WIN32_H_
