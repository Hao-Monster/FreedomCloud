#include "../proxy_settings.h"

#include <atomic>
#include <chrono>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>
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

  // Verify SerialTaskRunner executes move-only work off the caller thread in
  // strict FIFO order and drains all queued tasks before Shutdown() returns.
  {
    const auto caller_thread = std::this_thread::get_id();
    std::mutex log_mutex;
    std::vector<int> order;
    std::atomic<bool> ran_off_caller{true};
    {
      proxy::SerialTaskRunner runner;
      for (int i = 0; i < 16; ++i) {
        auto payload = std::make_unique<int>(i);
        runner.Post([&, item = std::move(payload)]() {
          if (std::this_thread::get_id() == caller_thread) {
            ran_off_caller.store(false);
          }
          if (*item == 0) {
            std::this_thread::sleep_for(std::chrono::milliseconds(15));
          }
          std::lock_guard<std::mutex> guard(log_mutex);
          order.push_back(*item);
        });
      }
      runner.Shutdown();
    }
    CHECK(ran_off_caller.load());
    CHECK(order.size() == 16);
    for (int i = 0; i < 16; ++i) {
      CHECK(order[static_cast<size_t>(i)] == i);
    }
  }

  // [CR-PERF-02] Verify Shutdown() on a Win32 UI thread that owns an HWND does
  // not self-deadlock when the background worker broadcasts WM_SETTINGCHANGE via
  // synchronous SendMessageTimeoutW back to that HWND.
  {
    HWND hwnd = CreateWindowExW(
        0, L"STATIC", L"fcx-proxy-shutdown-test", 0, 0, 0, 0, 0,
        nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    CHECK(hwnd != nullptr);

    HANDLE worker_entered = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    CHECK(worker_entered != nullptr);

    std::atomic<BOOL> send_succeeded{FALSE};
    std::atomic<DWORD> send_error{ERROR_SUCCESS};
    const auto start_tick = std::chrono::steady_clock::now();
    {
      proxy::SerialTaskRunner runner;
      runner.Post([&]() {
        SetEvent(worker_entered);
        // Give the UI thread a brief moment to enter runner.Shutdown() so the
        // SendMessageTimeoutW lands while Shutdown() is waiting on the worker.
        std::this_thread::sleep_for(std::chrono::milliseconds(25));
        DWORD_PTR msg_result = 0;
        const LRESULT ok = SendMessageTimeoutW(
            hwnd, WM_SETTINGCHANGE, 0,
            reinterpret_cast<LPARAM>(L"InternetSettings"),
            SMTO_NORMAL, 700, &msg_result);
        send_succeeded.store(ok != 0 ? TRUE : FALSE);
        if (ok == 0) {
          send_error.store(GetLastError());
        }
      });
      CHECK(WaitForSingleObject(worker_entered, 2000) == WAIT_OBJECT_0);
      runner.Shutdown();
    }
    const auto elapsed_ms =
        std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - start_tick)
            .count();

    CloseHandle(worker_entered);
    DestroyWindow(hwnd);

    CHECK(send_succeeded.load() == TRUE);
    CHECK(send_error.load() == ERROR_SUCCESS);
    CHECK(elapsed_ms < 400);
  }

  // Verify CoalescingStateRunner collapses rapid superseded updates while an
  // active apply is running, applying only [initial, latest] and completing all
  // caller callbacks.
  {
    HANDLE first_started = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    HANDLE release_first = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    CHECK(first_started != nullptr && release_first != nullptr);

    std::mutex applied_mu;
    std::vector<int> applied_states;
    std::atomic<int> completed_callbacks{0};
    std::atomic<int> last_callback_outcome{0};

    {
      proxy::CoalescingStateRunner<int, int> coalescer([&](const int& state) {
        {
          std::lock_guard<std::mutex> lock(applied_mu);
          applied_states.push_back(state);
        }
        if (state == 1) {
          SetEvent(first_started);
          WaitForSingleObject(release_first, 2000);
        }
        return state * 10;
      });

      coalescer.Submit(1, [&](const int&) { ++completed_callbacks; });
      CHECK(WaitForSingleObject(first_started, 2000) == WAIT_OBJECT_0);

      for (int s = 2; s <= 9; ++s) {
        coalescer.Submit(s, [&](const int& out) {
          last_callback_outcome.store(out);
          ++completed_callbacks;
        });
      }
      SetEvent(release_first);
      coalescer.Shutdown();
    }

    CloseHandle(first_started);
    CloseHandle(release_first);

    CHECK(applied_states.size() == 2);
    CHECK(applied_states[0] == 1 && applied_states[1] == 9);
    CHECK(completed_callbacks.load() == 9);
    CHECK(last_callback_outcome.load() == 90);
  }

  std::cout << "PASS: Unicode/ASCII/Punycode, start/stop, 2000 RAS failure cycles, "
               "8 write/notify failures, invalid UTF-8/NUL/port, SerialTaskRunner FIFO; "
               "OS settings unchanged\n";
  return 0;
}
