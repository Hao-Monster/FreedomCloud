#include "../tray_menu_win32.h"

#include <cstdlib>
#include <iostream>
#include <memory>
#include <string>

void Require(bool condition, const char* message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << '\n';
    std::exit(1);
  }
}

int main() {
  const auto desktop_name =
      L"FlClashMenuQA-" + std::to_wstring(GetCurrentProcessId());
  const HDESK original_desktop = GetThreadDesktop(GetCurrentThreadId());
  HDESK isolated_desktop = CreateDesktopW(
      desktop_name.c_str(), nullptr, nullptr, 0, GENERIC_ALL, nullptr);
  if (!isolated_desktop || !SetThreadDesktop(isolated_desktop)) {
    std::cerr << "NOT RUN: private desktop unavailable: " << GetLastError() << '\n';
    if (isolated_desktop) CloseDesktop(isolated_desktop);
    return 3;
  }
  const auto baseline = GetGuiResources(GetCurrentProcess(), GR_USEROBJECTS);
  tray_manager::MenuEntry leaf;
  leaf.id = 1;
  leaf.label = L"node";
  tray_manager::MenuEntry nested;
  nested.kind = tray_manager::MenuEntry::Kind::submenu;
  nested.children = {leaf};
  tray_manager::MenuEntry parent = nested;
  parent.children = {leaf, nested};
  const std::vector<tray_manager::MenuEntry> spec{parent};
  using Api = tray_manager::Win32MenuApi;
  {
    tray_manager::MenuState<Api> state;
    for (int i = 0; i < 200; ++i) {
      const HMENU previous = state.Current();
      auto built = tray_manager::BuildMenu<Api>(spec);
      Require(built.error == tray_manager::MenuBuildError::none,
              "real Win32 menu build failed");
      const HMENU child = GetSubMenu(built.menu.Get(), 0);
      const HMENU grandchild = GetSubMenu(child, 1);
      Require(IsMenu(child) && IsMenu(grandchild), "nested menus missing");
      state.Replace(std::move(built.menu));
      Require(!previous || !IsMenu(previous), "previous root retained after update");
      if (i == 0) {
        Require(state.BeginTracking(), "cannot mark active menu");
        auto pending = tray_manager::BuildMenu<Api>(spec);
        Require(pending.error == tray_manager::MenuBuildError::none,
                "pending menu build failed");
        const HMENU active = state.Current();
        state.Replace(std::move(pending.menu));
        Require(IsMenu(active) && IsMenu(child) && IsMenu(grandchild),
                "active menu destroyed during tracking");
        state.EndTracking();
        Require(!IsMenu(active) && !IsMenu(child) && !IsMenu(grandchild),
                "old submenu tree survived replacement");
      }
    }
    state.Clear();
  }
  {
    auto owner = std::make_shared<tray_manager::MenuLifetime<Api>>();
    auto built = tray_manager::BuildMenu<Api>(spec);
    Require(built.error == tray_manager::MenuBuildError::none,
            "owner lifetime menu build failed");
    const HMENU root = built.menu.Get();
    const HMENU child = GetSubMenu(root, 0);
    const HMENU grandchild = GetSubMenu(child, 1);
    Require(owner->Replace(std::move(built.menu)), "live owner rejected menu");
    const auto tracking_lifetime = owner;
    Require(owner->menus.BeginTracking(), "owner tracking request rejected");
    owner->Dispose();
    owner.reset();
    Require(IsMenu(root) && IsMenu(child) && IsMenu(grandchild),
            "owner destruction freed the active Win32 tree too early");
    auto late = tray_manager::BuildMenu<Api>(spec);
    Require(late.error == tray_manager::MenuBuildError::none,
            "late menu build failed");
    const HMENU rejected = late.menu.Get();
    Require(!tracking_lifetime->Replace(std::move(late.menu)) && !IsMenu(rejected),
            "disposed owner accepted or retained a late native menu");
    tracking_lifetime->menus.EndTracking();
    Require(!IsMenu(root) && !IsMenu(child) && !IsMenu(grandchild),
            "disposed owner's tree survived the end of tracking");
  }
  const auto final_count = GetGuiResources(GetCurrentProcess(), GR_USEROBJECTS);
  Require(final_count == baseline, "USER object count did not return to baseline");
  Require(SetThreadDesktop(original_desktop) != FALSE, "cannot restore test desktop");
  Require(CloseDesktop(isolated_desktop) != FALSE, "cannot close test desktop");
  std::cout << "PASS: 200 real Win32 multi-level refreshes; old roots/submenus "
               "invalid after replacement; owner destruction during tracking "
               "and late-update rejection pass; USER baseline="
            << baseline << " final=" << final_count << '\n';
  return 0;
}
