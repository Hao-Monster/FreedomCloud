#include "../proxy_settings.h"

#include <iostream>
#include <string>
#include <vector>

namespace {
struct FakeApi {
  inline static int enumerations = 0;
  inline static int fail_enumeration = 0;
  inline static int fail_option = 0;
  inline static int ras_count = 0;
  inline static std::vector<DWORD> calls;
  inline static std::wstring bypass;
  inline static std::vector<DWORD> flags;
  static void Reset() {
    enumerations = fail_enumeration = fail_option = ras_count = 0;
    calls.clear(); bypass.clear(); flags.clear();
  }
  static DWORD Enumerate(RASENTRYNAMEW* entries, DWORD* bytes, DWORD* count) {
    ++enumerations;
    if (fail_enumeration == enumerations) return ERROR_ACCESS_DENIED;
    *count = static_cast<DWORD>(ras_count);
    if (*bytes < *count * sizeof(RASENTRYNAMEW)) {
      *bytes = *count * sizeof(RASENTRYNAMEW);
      return ERROR_BUFFER_TOO_SMALL;
    }
    for (int i = 0; i < ras_count; ++i) {
      wcscpy_s(entries[i].szEntryName, L"fixture");
    }
    return ERROR_SUCCESS;
  }
  static bool SetOption(DWORD option, void* data, DWORD) {
    calls.push_back(option);
    if (option == INTERNET_OPTION_PER_CONNECTION_OPTION) {
      const auto* list = static_cast<INTERNET_PER_CONN_OPTION_LISTW*>(data);
      flags.push_back(list->pOptions[0].Value.dwValue);
      if (list->dwOptionCount == 3) bypass = list->pOptions[2].Value.pszValue;
    }
    return static_cast<int>(calls.size()) != fail_option;
  }
  static DWORD Error() { return ERROR_ACCESS_DENIED; }
};

#define CHECK(condition) do { if (!(condition)) { \
  std::cerr << "FAIL line " << __LINE__ << ": " << #condition << '\n'; return 1; \
} } while (false)
}

int main() {
  FakeApi::Reset();
  const auto started = proxy::ApplySystemProxy<FakeApi>(true, 7890,
      {"example.com", "xn--fsqu00a.xn--0zwm56d",
       "\xE4\xBE\x8B\xE5\xAD\x90.\xE6\xB5\x8B\xE8\xAF\x95",
       "*.\xE4\xBE\x8B\xE5\xAD\x90", "<local>"});
  CHECK(started.ok());
  CHECK(FakeApi::bypass == L"example.com;xn--fsqu00a.xn--0zwm56d;\u4F8B\u5B50.\u6D4B\u8BD5;*.\u4F8B\u5B50;<local>");
  CHECK(FakeApi::calls.size() == 3);
  CHECK(FakeApi::flags[0] == (PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY));

  FakeApi::Reset();
  FakeApi::ras_count = 3;
  CHECK(proxy::ApplySystemProxy<FakeApi>(false, 0, {}).ok());
  CHECK(FakeApi::enumerations == 2 && FakeApi::calls.size() == 6);
  for (const auto flag : FakeApi::flags) CHECK(flag == PROXY_TYPE_DIRECT);

  for (int fail = 1; fail <= 2; ++fail) {
    for (int repeat = 0; repeat < 1000; ++repeat) {
      FakeApi::Reset();
      FakeApi::ras_count = 3;
      FakeApi::fail_enumeration = fail;
      const auto result = proxy::ApplySystemProxy<FakeApi>(true, 7890, {"example.com"});
      CHECK(!result.ok() && result.error == ERROR_ACCESS_DENIED);
      CHECK(FakeApi::calls.empty());
    }
  }
  for (const bool enabled : {true, false}) {
    for (int fail = 1; fail <= 4; ++fail) {
      FakeApi::Reset();
      FakeApi::ras_count = 1;
      FakeApi::fail_option = fail;
      const auto result = proxy::ApplySystemProxy<FakeApi>(enabled, 7890, {});
      CHECK(!result.ok() && result.error == ERROR_ACCESS_DENIED);
      CHECK(FakeApi::calls.size() == 4);
      CHECK(FakeApi::calls[2] == INTERNET_OPTION_SETTINGS_CHANGED);
      CHECK(FakeApi::calls[3] == INTERNET_OPTION_REFRESH);
    }
  }
  for (const auto& invalid : {std::string("\xFF"), std::string("x\0y", 3)}) {
    FakeApi::Reset();
    CHECK(!proxy::ApplySystemProxy<FakeApi>(true, 7890, {invalid}).ok());
    CHECK(FakeApi::calls.empty() && FakeApi::enumerations == 0);
  }
  FakeApi::Reset();
  CHECK(!proxy::ApplySystemProxy<FakeApi>(true, 0, {}).ok());
  CHECK(FakeApi::calls.empty());
  std::cout << "PASS: Unicode/ASCII/Punycode, start/stop, 2000 RAS failure cycles, "
               "8 write/notify failures, invalid UTF-8/NUL/port; OS settings unchanged\n";
  return 0;
}
