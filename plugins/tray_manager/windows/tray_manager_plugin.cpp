#include "include/tray_manager/tray_manager_plugin.h"

// This must be included before many other Windows headers.
#include <stdio.h>
#include <windows.h>

#include <shellapi.h>
#include <strsafe.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <codecvt>
#include <map>
#include <memory>
#include <limits>
#include <sstream>

#include "tray_menu_win32.h"
#include "tray_icon_registration.h"

#define WM_MYMESSAGE (WM_USER + 1)

namespace {

const flutter::EncodableValue* ValueOrNull(const flutter::EncodableMap& map,
                                           const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) {
    return nullptr;
  }
  return &(it->second);
}
std::unique_ptr<
    flutter::MethodChannel<flutter::EncodableValue>,
    std::default_delete<flutter::MethodChannel<flutter::EncodableValue>>>
    channel = nullptr;

class TrayManagerPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  TrayManagerPlugin(flutter::PluginRegistrarWindows* registrar);

  virtual ~TrayManagerPlugin();

 private:
  flutter::PluginRegistrarWindows* registrar;
  NOTIFYICONDATA nid{};
  NOTIFYICONIDENTIFIER niif{};
  std::shared_ptr<tray_manager::MenuLifetime<tray_manager::Win32MenuApi>> menu_lifetime =
      std::make_shared<tray_manager::MenuLifetime<tray_manager::Win32MenuApi>>();
  bool tray_icon_setted = false;
  UINT windows_taskbar_created_message_id = 0;

  // The ID of the WindowProc delegate registration.
  int window_proc_id = -1;

  bool TrayManagerPlugin::_ParseMenu(
      const flutter::EncodableMap& args,
      std::vector<tray_manager::MenuEntry>* entries);
  void TrayManagerPlugin::_DestroyIcon();
  bool TrayManagerPlugin::_ApplyIcon();

  // Called for top-level WindowProc delegation.
  std::optional<LRESULT> TrayManagerPlugin::HandleWindowProc(HWND hwnd,
                                                             UINT message,
                                                             WPARAM wparam,
                                                             LPARAM lparam);
  HWND TrayManagerPlugin::GetMainWindow();
  void TrayManagerPlugin::Destroy(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void TrayManagerPlugin::SetIcon(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void TrayManagerPlugin::SetToolTip(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void TrayManagerPlugin::SetContextMenu(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void TrayManagerPlugin::PopUpContextMenu(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void TrayManagerPlugin::GetBounds(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

static bool plugin_already_registered = false;

// static
void TrayManagerPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  if (plugin_already_registered) {
    // Skip registration in subwindow
    return;
  }

  plugin_already_registered = true;

  channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "tray_manager",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<TrayManagerPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

TrayManagerPlugin::TrayManagerPlugin(flutter::PluginRegistrarWindows* registrar)
    : registrar(registrar) {
  window_proc_id = registrar->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowProc(hwnd, message, wparam, lparam);
      });
  windows_taskbar_created_message_id = RegisterWindowMessage(L"TaskbarCreated");
}

TrayManagerPlugin::~TrayManagerPlugin() {
  menu_lifetime->Dispose();
  _DestroyIcon();
  registrar->UnregisterTopLevelWindowProcDelegate(window_proc_id);
}

bool TrayManagerPlugin::_ParseMenu(
    const flutter::EncodableMap& args,
    std::vector<tray_manager::MenuEntry>* entries) {
  const auto* items = std::get_if<flutter::EncodableList>(ValueOrNull(args, "items"));
  if (!items) return false;
  entries->reserve(items->size());
  for (const auto& item_value : *items) {
    const auto* item_map = std::get_if<flutter::EncodableMap>(&item_value);
    if (!item_map) return false;
    const auto* id = std::get_if<int>(ValueOrNull(*item_map, "id"));
    const auto* type = std::get_if<std::string>(ValueOrNull(*item_map, "type"));
    const auto* label = std::get_if<std::string>(ValueOrNull(*item_map, "label"));
    const auto* disabled = std::get_if<bool>(ValueOrNull(*item_map, "disabled"));
    if (!id || !type || !label || !disabled ||
        label->size() > static_cast<size_t>((std::numeric_limits<int>::max)())) {
      return false;
    }
    tray_manager::MenuEntry entry;
    entry.id = *id;
    if (!label->empty()) {
      const int source_size = static_cast<int>(label->size());
      const int wide_size = MultiByteToWideChar(
          CP_UTF8, MB_ERR_INVALID_CHARS, label->data(), source_size, nullptr, 0);
      if (!wide_size) return false;
      entry.label.resize(wide_size);
      if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, label->data(),
                              source_size, entry.label.data(), wide_size) != wide_size) {
        return false;
      }
    }
    const auto* checked = std::get_if<bool>(ValueOrNull(*item_map, "checked"));
    entry.checked = checked && *checked;
    entry.disabled = *disabled;
    if (type->compare("separator") == 0) {
      entry.kind = tray_manager::MenuEntry::Kind::separator;
    } else if (type->compare("checkbox") == 0) {
      entry.kind = tray_manager::MenuEntry::Kind::checkbox;
    } else if (type->compare("submenu") == 0) {
      entry.kind = tray_manager::MenuEntry::Kind::submenu;
      const auto* submenu = std::get_if<flutter::EncodableMap>(
          ValueOrNull(*item_map, "submenu"));
      if (!submenu || !_ParseMenu(*submenu, &entry.children)) return false;
    }
    entries->push_back(std::move(entry));
  }
  return true;
}

void TrayManagerPlugin::_DestroyIcon() {
  // A previous failed registration may still leave an existing Shell entry.
  if (nid.cbSize != 0 && nid.hWnd != nullptr) Shell_NotifyIcon(NIM_DELETE, &nid);
  if (nid.hIcon != nullptr) {
    DestroyIcon(nid.hIcon);
    nid.hIcon = nullptr;
  }
  tray_icon_setted = false;
}

std::optional<LRESULT> TrayManagerPlugin::HandleWindowProc(HWND hWnd,
                                                           UINT message,
                                                           WPARAM wParam,
                                                           LPARAM lParam) {
  std::optional<LRESULT> result;
  if (message == WM_DESTROY) {
    _DestroyIcon();
    menu_lifetime->Dispose();
  } else if (message == WM_COMMAND) {
    flutter::EncodableMap eventData = flutter::EncodableMap();
    eventData[flutter::EncodableValue("id")] =
        flutter::EncodableValue((int)wParam);

    channel->InvokeMethod("onTrayMenuItemClick",
                          std::make_unique<flutter::EncodableValue>(eventData));
  } else if (message == WM_MYMESSAGE) {
    switch (lParam) {
      case WM_LBUTTONUP:
        channel->InvokeMethod("onTrayIconMouseDown",
                              std::make_unique<flutter::EncodableValue>());
        break;
      case WM_RBUTTONUP:
        channel->InvokeMethod("onTrayIconRightMouseDown",
                              std::make_unique<flutter::EncodableValue>());
        break;
      default:
        return DefWindowProc(hWnd, message, wParam, lParam);
    };
  } else if (message == windows_taskbar_created_message_id) {
    if (windows_taskbar_created_message_id != 0 && nid.hIcon != nullptr &&
        !menu_lifetime->disposed) {
      // restore the icon with the existing resource.
      tray_icon_setted = false;
      _ApplyIcon();
    }
  } else if (message == WM_POWERBROADCAST) {
    // Handle power management events (sleep/wake)
    switch (wParam) {
      case PBT_APMRESUMEAUTOMATIC:
      case PBT_APMRESUMESUSPEND:
        // System is resuming from sleep/hibernation
        if (nid.hIcon != nullptr && !menu_lifetime->disposed) {
          // Restore the tray icon after system wakes up
          tray_icon_setted = false;
          _ApplyIcon();
        }
        break;
      default:
        break;
    }
  }
  return result;
}

HWND TrayManagerPlugin::GetMainWindow() {
  return ::GetAncestor(registrar->GetView()->GetNativeWindow(), GA_ROOT);
}

void TrayManagerPlugin::Destroy(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  _DestroyIcon();

  result->Success(flutter::EncodableValue(true));
}

void TrayManagerPlugin::SetIcon(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const flutter::EncodableMap& args =
      std::get<flutter::EncodableMap>(*method_call.arguments());

  std::string iconPath =
      std::get<std::string>(args.at(flutter::EncodableValue("iconPath")));

  std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>> converter;

  HICON new_icon = static_cast<HICON>(
      LoadImage(nullptr, (LPCWSTR)(converter.from_bytes(iconPath).c_str()),
                IMAGE_ICON, GetSystemMetrics(SM_CXSMICON),
                GetSystemMetrics(SM_CYSMICON), LR_LOADFROMFILE));
  if (new_icon == nullptr) {
    result->Error("icon_load_failed", "LoadImage failed.",
                  flutter::EncodableValue(static_cast<int64_t>(GetLastError())));
    return;
  }
  HICON old_icon = nid.hIcon;
  nid.hIcon = new_icon;

  if (!_ApplyIcon()) {
    const DWORD error = GetLastError();
    if (old_icon != nullptr) {
      nid.hIcon = old_icon;
      DestroyIcon(new_icon);
    }
    // On first registration failure, retain the loaded icon for a later
    // TaskbarCreated/resume retry; cleanup still owns and releases this HICON.
    result->Error("icon_registration_failed", "Shell_NotifyIcon failed.",
                  flutter::EncodableValue(static_cast<int64_t>(error)));
    return;
  }
  if (old_icon != nullptr) DestroyIcon(old_icon);

  result->Success(flutter::EncodableValue(true));
}

bool TrayManagerPlugin::_ApplyIcon() {
  HICON hIconBackup = nid.hIcon;
  WCHAR szTipBackup[128]{};
  StringCchCopy(szTipBackup, _countof(szTipBackup), nid.szTip);

  ZeroMemory(&nid, sizeof(NOTIFYICONDATA));
  nid.cbSize = sizeof(NOTIFYICONDATA);
  nid.hWnd = GetMainWindow();
  nid.uID = 1;
  nid.hIcon = hIconBackup;
  StringCchCopy(nid.szTip, _countof(nid.szTip), szTipBackup);
  nid.uCallbackMessage = WM_MYMESSAGE;
  nid.uFlags = NIF_MESSAGE | NIF_ICON;
  if (nid.szTip[0] != '\0') nid.uFlags |= NIF_TIP;
  if (!tray_manager::RefreshIconRegistration(
          tray_icon_setted, [this](tray_manager::IconOperation operation) {
            SetLastError(ERROR_SUCCESS);
            return Shell_NotifyIcon(operation == tray_manager::IconOperation::add
                                        ? NIM_ADD : NIM_MODIFY, &nid) != FALSE;
          })) {
    return false;
  }

  niif.cbSize = sizeof(NOTIFYICONIDENTIFIER);
  niif.hWnd = nid.hWnd;
  niif.uID = nid.uID;
  niif.guidItem = GUID_NULL;

  return true;
}

void TrayManagerPlugin::SetToolTip(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const flutter::EncodableMap& args =
      std::get<flutter::EncodableMap>(*method_call.arguments());

  std::string toolTip =
      std::get<std::string>(args.at(flutter::EncodableValue("toolTip")));

  std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>> converter;
  nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  StringCchCopy(nid.szTip, _countof(nid.szTip),
                converter.from_bytes(toolTip).c_str());
  Shell_NotifyIcon(NIM_MODIFY, &nid);

  result->Success(flutter::EncodableValue(true));
}

void TrayManagerPlugin::SetContextMenu(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto lifetime = menu_lifetime;
  if (lifetime->disposed) {
    result->Error("menu_unavailable", "Menu owner has been destroyed.");
    return;
  }
  const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
  const auto* menu = args ? std::get_if<flutter::EncodableMap>(
                                ValueOrNull(*args, "menu")) : nullptr;
  std::vector<tray_manager::MenuEntry> entries;
  if (!menu || !_ParseMenu(*menu, &entries)) {
    result->Error("invalid_menu", "Invalid menu arguments or UTF-8 label.");
    return;
  }
  auto replacement = tray_manager::BuildMenu<tray_manager::Win32MenuApi>(entries);
  if (replacement.error != tray_manager::MenuBuildError::none) {
    const bool create_failed =
        replacement.error == tray_manager::MenuBuildError::create;
    result->Error(create_failed ? "menu_creation_failed" : "menu_append_failed",
                  create_failed ? "CreatePopupMenu failed." : "AppendMenu failed.",
                  flutter::EncodableValue(
                      static_cast<int64_t>(replacement.platform_error)));
    return;
  }
  if (!lifetime->Replace(std::move(replacement.menu))) {
    result->Error("menu_unavailable", "Menu owner has been destroyed.");
    return;
  }

  result->Success(flutter::EncodableValue(true));
}

void TrayManagerPlugin::PopUpContextMenu(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto lifetime = menu_lifetime;
  const flutter::EncodableMap& args =
      std::get<flutter::EncodableMap>(*method_call.arguments());

  bool bringAppToFront =
      std::get<bool>(args.at(flutter::EncodableValue("bringAppToFront")));

  HWND hWnd = GetMainWindow();

  double x, y;

  // RECT rect;
  // Shell_NotifyIconGetRect(&niif, &rect);

  // x = rect.left + ((rect.right - rect.left) / 2);
  // y = rect.top + ((rect.bottom - rect.top) / 2);

  POINT cursorPos;
  GetCursorPos(&cursorPos);
  x = cursorPos.x;
  y = cursorPos.y;

  if (bringAppToFront) {
    SetForegroundWindow(hWnd);
  }
  if (lifetime->disposed || !lifetime->menus.BeginTracking()) {
    result->Error("menu_unavailable", "Menu is not configured or already being displayed.");
    return;
  }
  const UINT selected_id = TrackPopupMenu(
      lifetime->menus.Current(),
      TPM_BOTTOMALIGN | TPM_LEFTALIGN | TPM_RETURNCMD | TPM_NONOTIFY,
      static_cast<int>(x), static_cast<int>(y), 0, hWnd, NULL);
  lifetime->menus.EndTracking();
  // No member access or engine reply after the nested loop destroys the owner.
  if (lifetime->disposed) return;
  result->Success(flutter::EncodableValue(static_cast<int>(selected_id)));
}

void TrayManagerPlugin::GetBounds(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const flutter::EncodableMap& args =
      std::get<flutter::EncodableMap>(*method_call.arguments());

  if (!tray_icon_setted) {
    result->Success();
    return;
  }

  double devicePixelRatio =
      std::get<double>(args.at(flutter::EncodableValue("devicePixelRatio")));

  RECT rect;
  Shell_NotifyIconGetRect(&niif, &rect);
  flutter::EncodableMap resultMap = flutter::EncodableMap();

  double x = rect.left / devicePixelRatio * 1.0f;
  double y = rect.top / devicePixelRatio * 1.0f;
  double width = (rect.right - rect.left) / devicePixelRatio * 1.0f;
  double height = (rect.bottom - rect.top) / devicePixelRatio * 1.0f;

  resultMap[flutter::EncodableValue("x")] = flutter::EncodableValue(x);
  resultMap[flutter::EncodableValue("y")] = flutter::EncodableValue(y);
  resultMap[flutter::EncodableValue("width")] = flutter::EncodableValue(width);
  resultMap[flutter::EncodableValue("height")] =
      flutter::EncodableValue(height);

  result->Success(flutter::EncodableValue(resultMap));
}

void TrayManagerPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("destroy") == 0) {
    Destroy(method_call, std::move(result));
  } else if (method_call.method_name().compare("setIcon") == 0) {
    SetIcon(method_call, std::move(result));
  } else if (method_call.method_name().compare("setToolTip") == 0) {
    SetToolTip(method_call, std::move(result));
  } else if (method_call.method_name().compare("setContextMenu") == 0) {
    SetContextMenu(method_call, std::move(result));
  } else if (method_call.method_name().compare("popUpContextMenu") == 0) {
    PopUpContextMenu(method_call, std::move(result));
  } else if (method_call.method_name().compare("getBounds") == 0) {
    GetBounds(method_call, std::move(result));
  } else {
    result->NotImplemented();
  }
}

}  // namespace

void TrayManagerPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  TrayManagerPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
