#include <windows.h>

#include <iostream>
#include <string>

int main() {
  const auto desktop_name =
      L"FlClashMenuQA-" + std::to_wstring(GetCurrentProcessId());
  const HDESK original_desktop = GetThreadDesktop(GetCurrentThreadId());
  HDESK isolated_desktop = CreateDesktopW(
      desktop_name.c_str(), nullptr, nullptr, 0, GENERIC_ALL, nullptr);
  if (!isolated_desktop || !SetThreadDesktop(isolated_desktop)) {
    std::cerr << "NOT RUN: private desktop unavailable: " << GetLastError()
              << '\n';
    if (isolated_desktop) CloseDesktop(isolated_desktop);
    return 3;
  }

  HMENU root = CreatePopupMenu();
  HMENU child = CreatePopupMenu();
  HMENU grandchild = CreatePopupMenu();
  bool prepared = root && child && grandchild;
  if (prepared) {
    prepared = AppendMenuW(grandchild, MF_STRING, 1, L"leaf") &&
               AppendMenuW(child, MF_POPUP,
                           reinterpret_cast<UINT_PTR>(grandchild), L"nested") &&
               AppendMenuW(root, MF_POPUP,
                           reinterpret_cast<UINT_PTR>(child), L"parent");
  }
  if (!prepared) {
    std::cerr << "NOT RUN: Win32 menu construction unavailable: "
              << GetLastError() << '\n';
    if (root && IsMenu(root)) DestroyMenu(root);
    if (child && IsMenu(child)) DestroyMenu(child);
    if (grandchild && IsMenu(grandchild)) DestroyMenu(grandchild);
    SetThreadDesktop(original_desktop);
    CloseDesktop(isolated_desktop);
    return 3;
  }

  // This is the original tray_manager 0.5.2 refresh cleanup operation.
  const bool removed = RemoveMenu(root, 0, MF_BYPOSITION) != FALSE;
  DestroyMenu(root);
  const bool orphan_child = IsMenu(child) != FALSE;
  const bool orphan_grandchild = IsMenu(grandchild) != FALSE;
  std::cout << "legacy_remove_succeeded=" << removed
            << " orphan_child=" << orphan_child
            << " orphan_grandchild=" << orphan_grandchild << '\n';

  // Clean the deliberately demonstrated orphan; never leave QA resources.
  if (orphan_child) DestroyMenu(child);
  if (IsMenu(grandchild)) DestroyMenu(grandchild);
  const bool cleaned = !IsMenu(child) && !IsMenu(grandchild);
  SetThreadDesktop(original_desktop);
  CloseDesktop(isolated_desktop);
  if (removed && orphan_child && orphan_grandchild && cleaned) {
    std::cerr << "RED: old refresh leaves both submenu handles alive. "
                 "QA resources explicitly cleaned.\n";
    return 2;
  }
  std::cerr << "FAIL: legacy defect was not reproduced.\n";
  return 1;
}
