#ifndef FLCLASHX_PROXY_SETTINGS_H_
#define FLCLASHX_PROXY_SETTINGS_H_

#include <windows.h>
#include <wininet.h>
#include <ras.h>
#include <raserror.h>

#include <array>
#include <string>
#include <vector>

namespace proxy {

struct ProxyResult {
  DWORD error = ERROR_SUCCESS;
  const char* stage = "";
  bool ok() const { return error == ERROR_SUCCESS; }
};

inline bool Utf8ToWide(const std::string& value, std::wstring* wide) {
  if (value.size() > 1024 * 1024 || value.find('\0') != std::string::npos) return false;
  if (value.empty()) { wide->clear(); return true; }
  const int size = static_cast<int>(value.size());
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                        value.data(), size, nullptr, 0);
  if (length <= 0) return false;
  wide->resize(length);
  return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), size,
                             wide->data(), length) == length;
}

struct WindowsProxyApi {
  static DWORD Enumerate(RASENTRYNAMEW* entries, DWORD* bytes, DWORD* count) {
    return RasEnumEntriesW(nullptr, nullptr, entries, bytes, count);
  }
  static bool SetOption(DWORD option, void* value, DWORD bytes) {
    return InternetSetOptionW(nullptr, option, value, bytes) != FALSE;
  }
  static DWORD Error() { return GetLastError(); }
};

template <typename Api = WindowsProxyApi>
ProxyResult ApplySystemProxy(bool enabled, int port,
                             const std::vector<std::string>& bypass) {
  if (enabled && (port <= 0 || port > 65535)) {
    return {ERROR_INVALID_PARAMETER, "port"};
  }
  std::wstring bypass_list;
  if (bypass.size() > 4096) return {ERROR_INVALID_PARAMETER, "bypass"};
  for (const auto& domain : bypass) {
    std::wstring wide;
    if (!Utf8ToWide(domain, &wide) ||
        bypass_list.size() + wide.size() + 1 > 1024 * 1024) {
      return {ERROR_INVALID_PARAMETER, "bypass_utf8"};
    }
    if (!bypass_list.empty()) bypass_list += L';';
    bypass_list += wide;
  }

  // Discover every target before mutating the default connection. A RAS
  // failure cannot leave a partially applied default setting without notice.
  std::vector<RASENTRYNAMEW> entries(1);
  DWORD count = 0;
  DWORD error = ERROR_BUFFER_TOO_SMALL;
  for (int attempt = 0; attempt < 3; ++attempt) {
    entries[0].dwSize = sizeof(RASENTRYNAMEW);
    DWORD bytes = static_cast<DWORD>(entries.size() * sizeof(RASENTRYNAMEW));
    error = Api::Enumerate(entries.data(), &bytes, &count);
    if (error != ERROR_BUFFER_TOO_SMALL) break;
    const size_t needed =
        (static_cast<size_t>(bytes) + sizeof(RASENTRYNAMEW) - 1) / sizeof(RASENTRYNAMEW);
    if (needed == 0 || needed > 4096) return {ERROR_NOT_ENOUGH_MEMORY, "ras_budget"};
    entries.resize(needed);
  }
  if (error != ERROR_SUCCESS) return {error, "ras_enumeration"};
  if (count > entries.size()) return {ERROR_INVALID_DATA, "ras_count"};

  std::wstring address = L"127.0.0.1:" + std::to_wstring(port);
  std::array<INTERNET_PER_CONN_OPTIONW, 3> options{};
  options[0].dwOption = INTERNET_PER_CONN_FLAGS;
  options[0].Value.dwValue = enabled ? PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY : PROXY_TYPE_DIRECT;
  options[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
  options[1].Value.pszValue = address.data();
  options[2].dwOption = INTERNET_PER_CONN_PROXY_BYPASS;
  options[2].Value.pszValue = bypass_list.data();
  INTERNET_PER_CONN_OPTION_LISTW list{};
  list.dwSize = sizeof(list);
  list.dwOptionCount = enabled ? 3 : 1;
  list.pOptions = options.data();

  ProxyResult result;
  auto set = [&](DWORD option, void* value, DWORD bytes, const char* stage) {
    if (!Api::SetOption(option, value, bytes) && result.ok()) {
      const DWORD last_error = Api::Error();
      result = {last_error == ERROR_SUCCESS ? ERROR_GEN_FAILURE : last_error, stage};
    }
  };
  set(INTERNET_OPTION_PER_CONNECTION_OPTION, &list, sizeof(list), "default_connection");
  for (DWORD i = 0; i < count; ++i) {
    list.pszConnection = entries[i].szEntryName;
    set(INTERNET_OPTION_PER_CONNECTION_OPTION, &list, sizeof(list), "ras_connection");
  }
  // Even a failed API call may have applied part of the requested state.
  // Attempt both notifications, preserving the first meaningful failure.
  set(INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0, "settings_changed");
  set(INTERNET_OPTION_REFRESH, nullptr, 0, "refresh");
  return result;
}

}  // namespace proxy
#endif  // FLCLASHX_PROXY_SETTINGS_H_
