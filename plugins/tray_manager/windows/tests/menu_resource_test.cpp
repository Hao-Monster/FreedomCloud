#include "../tray_menu.h"
#include "../tray_icon_registration.h"

#include <cstdlib>
#include <iostream>
#include <map>
#include <memory>
#include <vector>

namespace {

void Require(bool condition, const char* message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << '\n';
    std::exit(1);
  }
}

struct FakeMenuApi {
  using Handle = int;
  inline static int next_handle = 1;
  inline static int creates = 0;
  inline static int appends = 0;
  inline static int fail_create = 0;
  inline static int fail_append = 0;
  inline static std::map<Handle, std::vector<Handle>> children;

  static void Reset() {
    Require(children.empty(), "previous test leaked a menu");
    creates = appends = fail_create = fail_append = 0;
  }
  static Handle Create() {
    if (++creates == fail_create) return 0;
    const Handle handle = next_handle++;
    children.emplace(handle, std::vector<Handle>());
    return handle;
  }
  static bool Append(Handle parent, const tray_manager::MenuEntry&, Handle child) {
    Require(children.count(parent) == 1, "append used a dead parent");
    if (++appends == fail_append) return false;
    if (child) {
      Require(children.count(child) == 1, "append used a dead child");
      children.at(parent).push_back(child);
    }
    return true;
  }
  static void Destroy(Handle handle) {
    const auto found = children.find(handle);
    Require(found != children.end(), "menu destroyed twice or invalid handle");
    const auto descendants = std::move(found->second);
    children.erase(found);
    for (Handle child : descendants) Destroy(child);
  }
  static unsigned long LastError() { return 8; }
};

using State = tray_manager::MenuState<FakeMenuApi>;
using Owner = tray_manager::OwnedMenu<FakeMenuApi>;

std::vector<tray_manager::MenuEntry> MenuSpec() {
  tray_manager::MenuEntry leaf;
  leaf.id = 1;
  leaf.label = L"node";
  tray_manager::MenuEntry nested;
  nested.kind = tray_manager::MenuEntry::Kind::submenu;
  nested.label = L"group";
  nested.children = {leaf};
  tray_manager::MenuEntry parent = nested;
  parent.label = L"profiles";
  parent.children = {leaf, nested};
  tray_manager::MenuEntry checkbox;
  checkbox.id = 2;
  checkbox.kind = tray_manager::MenuEntry::Kind::checkbox;
  checkbox.checked = true;
  checkbox.disabled = true;
  tray_manager::MenuEntry separator;
  separator.kind = tray_manager::MenuEntry::Kind::separator;
  return {leaf, parent, separator, checkbox};
}

Owner Build() {
  auto built = tray_manager::BuildMenu<FakeMenuApi>(MenuSpec());
  Require(built.error == tray_manager::MenuBuildError::none,
          "unexpected build failure");
  return std::move(built.menu);
}

void RepeatedRefresh() {
  FakeMenuApi::Reset();
  {
    State state;
    for (int i = 0; i < 200; ++i) {
      state.Replace(Build());
      Require(FakeMenuApi::children.size() == 3,
              "refresh retained a previous menu tree");
    }
    state.Clear();
    Require(FakeMenuApi::children.empty(), "clear retained root/child menus");
    state.Clear();
    state.Replace(Build());
  }
  Require(FakeMenuApi::children.empty(), "destructor retained menu tree");
  std::cout << "PASS M02/M03: 200 refreshes, clear, root lifetime\n";
}

void TrackingUpdates() {
  FakeMenuApi::Reset();
  {
    State state;
    state.Replace(Build());
    const auto original = state.Current();
    Require(state.BeginTracking(), "first tracking request rejected");
    Require(!state.BeginTracking(), "nested tracking was allowed");
    auto first = Build();
    const auto first_handle = first.Get();
    state.Replace(std::move(first));
    auto latest = Build();
    const auto latest_handle = latest.Get();
    state.Replace(std::move(latest));
    Require(state.Current() == original &&
                FakeMenuApi::children.count(original) == 1,
            "active popup was replaced/destroyed while tracking");
    Require(FakeMenuApi::children.count(first_handle) == 0 &&
                FakeMenuApi::children.size() == 6,
            "superseded pending tree was retained");
    state.EndTracking();
    Require(state.Current() == latest_handle &&
                FakeMenuApi::children.count(original) == 0 &&
                FakeMenuApi::children.size() == 3,
            "latest pending update was not installed after tracking");
  }
  Require(FakeMenuApi::children.empty(), "tracking state leaked menus");
  std::cout << "PASS M04/M09: deferred updates and reentrant popup guard\n";
}

void ClearDuringTracking() {
  FakeMenuApi::Reset();
  {
    State state;
    Require(!state.BeginTracking(), "empty state allowed tracking");
    state.Replace(Build());
    const auto original = state.Current();
    Require(state.BeginTracking(), "tracking request rejected");
    state.Replace(Build());
    state.Clear();
    Require(state.Current() == original && FakeMenuApi::children.size() == 3,
            "clear destroyed the active tree or retained pending tree");
    state.EndTracking();
    Require(state.Current() == 0 && FakeMenuApi::children.empty(),
            "deferred clear retained a menu");
  }
  std::cout << "PASS M05: clear/destroy deferred until popup finishes\n";
}

void FailureAtEverySite(bool create_failure) {
  const int sites = create_failure ? 3 : 7;
  for (int site = 1; site <= sites; ++site) {
    FakeMenuApi::Reset();
    {
      State state;
      state.Replace(Build());
      const auto original = state.Current();
      FakeMenuApi::creates = FakeMenuApi::appends = 0;
      if (create_failure) FakeMenuApi::fail_create = site;
      else FakeMenuApi::fail_append = site;
      auto failed = tray_manager::BuildMenu<FakeMenuApi>(MenuSpec());
      Require(failed.error == (create_failure ? tray_manager::MenuBuildError::create
                                             : tray_manager::MenuBuildError::append),
              "injected API failure was not reported");
      Require(!failed.menu && failed.platform_error == 8,
              "failure retained a menu or lost the platform error");
      Require(state.Current() == original && FakeMenuApi::children.size() == 3,
              "failed replacement altered the current tree or leaked resources");
    }
    Require(FakeMenuApi::children.empty(), "failed build leaked resources");
  }
  std::cout << "PASS " << (create_failure ? "M06" : "M07")
            << ": injected failure at all " << sites << " API call sites\n";
}

void FailureWhileTracking() {
  FakeMenuApi::Reset();
  {
    State state;
    state.Replace(Build());
    const auto original = state.Current();
    Require(state.BeginTracking(), "tracking request rejected");
    auto pending = Build();
    const auto pending_handle = pending.Get();
    state.Replace(std::move(pending));
    FakeMenuApi::fail_append = FakeMenuApi::appends + 3;
    auto failed = tray_manager::BuildMenu<FakeMenuApi>(MenuSpec());
    Require(failed.error == tray_manager::MenuBuildError::append && !failed.menu,
            "background build failure was not reported");
    Require(state.Current() == original && FakeMenuApi::children.size() == 6,
            "failed background build invalidated active/pending menus");
    state.EndTracking();
    Require(state.Current() == pending_handle && FakeMenuApi::children.size() == 3,
            "failed build discarded the last successful pending update");
  }
  Require(FakeMenuApi::children.empty(), "failed background update leaked menus");
  std::cout << "PASS M08: failed update preserves active/latest successful tree\n";
}

void OwnerDestroyedWhileTracking() {
  FakeMenuApi::Reset();
  auto owner = std::make_shared<tray_manager::MenuLifetime<FakeMenuApi>>();
  Require(owner->Replace(Build()), "live owner rejected menu");
  const auto root = owner->menus.Current();
  const auto tracking_lifetime = owner;
  Require(owner->menus.BeginTracking(), "tracking request rejected");
  owner->Dispose();
  owner.reset();
  Require(tracking_lifetime->disposed &&
              FakeMenuApi::children.count(root) == 1 &&
              FakeMenuApi::children.size() == 3,
          "owner destruction invalidated the displayed tree");
  Require(!tracking_lifetime->Replace(Build()) &&
              FakeMenuApi::children.size() == 3,
          "disposed owner accepted a late update or leaked its rejected tree");
  tracking_lifetime->menus.EndTracking();
  Require(FakeMenuApi::children.empty(), "disposed owner retained menu tree");
  std::cout << "PASS B07: stack lifetime survives disposed/reset owner; late "
               "updates rejected and root freed after tracking\n";
}

void IconRegistrationFailures() {
  using Operation = tray_manager::IconOperation;
  const auto check = [](bool initially_registered, std::vector<bool> replies,
                        std::vector<Operation> expected, bool succeeds) {
    bool registered = initially_registered;
    std::vector<Operation> calls;
    const bool result = tray_manager::RefreshIconRegistration(
        registered, [&](Operation operation) {
          Require(calls.size() < replies.size(), "unexpected Shell operation");
          const bool reply = replies[calls.size()];
          calls.push_back(operation);
          return reply;
        });
    Require(calls == expected && result == succeeds && registered == succeeds,
            "icon registration claimed success or used wrong recovery sequence");
  };
  check(false, {true}, {Operation::add}, true);
  check(true, {true}, {Operation::modify}, true);
  check(true, {false, true}, {Operation::modify, Operation::add}, true);
  check(true, {false, false, true},
        {Operation::modify, Operation::add, Operation::modify}, true);
  check(false, {false, false}, {Operation::add, Operation::modify}, false);
  check(true, {false, false, false},
        {Operation::modify, Operation::add, Operation::modify}, false);
  check(false, {false, true}, {Operation::add, Operation::modify}, true);
  std::cout << "PASS B08: 7 icon registration sequences, failed add/modify "
               "and missing/duplicate identity recovery\n";
}

}  // namespace

int main() {
  RepeatedRefresh();
  TrackingUpdates();
  ClearDuringTracking();
  FailureAtEverySite(true);
  FailureAtEverySite(false);
  FailureWhileTracking();
  OwnerDestroyedWhileTracking();
  IconRegistrationFailures();
  std::cout << "PASS: 8 test groups; no live menu handles, no double destruction\n";
  return 0;
}
