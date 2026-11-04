#ifndef FLCLASHX_PROXY_SETTINGS_H_
#define FLCLASHX_PROXY_SETTINGS_H_

#include <windows.h>
#include <wininet.h>
#include <ras.h>
#include <raserror.h>

#pragma comment(lib, "user32.lib")

#include <array>
#include <condition_variable>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace proxy {

/// Runs WinInet/RAS mutations in strict FIFO order on a single background
/// thread so `InternetSetOptionW(INTERNET_OPTION_SETTINGS_CHANGED / REFRESH)`
/// and `RasEnumEntriesW` never block Flutter's Win32 UI message pump.
class SerialTaskRunner {
 public:
  SerialTaskRunner() = default;
  SerialTaskRunner(const SerialTaskRunner&) = delete;
  SerialTaskRunner& operator=(const SerialTaskRunner&) = delete;

  ~SerialTaskRunner() { Shutdown(); }

  template <typename Fn>
  void Post(Fn&& fn) {
    using Decayed = typename std::decay<Fn>::type;
    auto task = std::unique_ptr<Task>(new TaskImpl<Decayed>(std::forward<Fn>(fn)));
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (stopping_) return;
      if (!started_) {
        done_event_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
        started_ = true;
        worker_ = std::thread([this]() { RunLoop(); });
      }
      queue_.push_back(std::move(task));
    }
    cv_.notify_one();
  }

  void Shutdown() {
    bool join_worker = false;
    HANDLE done_event = nullptr;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (!stopping_) {
        stopping_ = true;
        join_worker = started_;
        done_event = done_event_;
      }
    }
    if (join_worker) {
      cv_.notify_all();
      if (done_event != nullptr) {
        for (;;) {
          const DWORD wait_rc = MsgWaitForMultipleObjects(
              1, &done_event, FALSE, INFINITE, QS_SENDMESSAGE);
          if (wait_rc == WAIT_OBJECT_0 + 1) {
            // Dispatch inbound inter-thread SendMessage calls (such as
            // WM_SETTINGCHANGE broadcast by InternetSetOptionW on worker_)
            // without removing posted input/paint messages from the UI queue.
            MSG msg{};
            PeekMessageW(&msg, nullptr, 0, 0, PM_NOREMOVE | PM_QS_SENDMESSAGE);
            continue;
          }
          break;
        }
      }
      if (worker_.joinable()) {
        worker_.join();
      }
      if (done_event != nullptr) {
        CloseHandle(done_event);
        done_event_ = nullptr;
      }
    }
  }

 private:
  struct Task {
    virtual ~Task() = default;
    virtual void Run() = 0;
  };

  template <typename Fn>
  struct TaskImpl final : Task {
    explicit TaskImpl(Fn&& fn) : fn_(std::move(fn)) {}
    explicit TaskImpl(const Fn& fn) : fn_(fn) {}
    void Run() override { fn_(); }
    Fn fn_;
  };

  void RunLoop() {
    for (;;) {
      std::unique_ptr<Task> next;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        cv_.wait(lock, [this]() { return stopping_ || !queue_.empty(); });
        if (queue_.empty()) {
          const HANDLE done = done_event_;
          lock.unlock();
          if (done != nullptr) {
            SetEvent(done);
          }
          return;
        }
        next = std::move(queue_.front());
        queue_.pop_front();
      }
      next->Run();
    }
  }

  std::mutex mutex_;
  std::condition_variable cv_;
  std::deque<std::unique_ptr<Task>> queue_;
  std::thread worker_;
  HANDLE done_event_ = nullptr;
  bool started_ = false;
  bool stopping_ = false;
};

/// Coalesces rapid state transitions onto a single pending slot behind the
/// active worker execution so intermediate superseded proxy toggles collapse to
/// O(1) WinInet broadcasts while completing every caller's callback cleanly.
template <typename State, typename Outcome>
class CoalescingStateRunner {
 public:
  using ApplyFn = std::function<Outcome(const State&)>;
  using CompleteFn = std::function<void(const Outcome&)>;

  explicit CoalescingStateRunner(ApplyFn apply) : apply_(std::move(apply)) {}
  CoalescingStateRunner(const CoalescingStateRunner&) = delete;
  CoalescingStateRunner& operator=(const CoalescingStateRunner&) = delete;

  ~CoalescingStateRunner() { Shutdown(); }

  void Submit(State state, CompleteFn on_complete) {
    bool need_schedule = false;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (stopping_) return;
      pending_state_ = std::move(state);
      has_pending_ = true;
      pending_callbacks_.push_back(std::move(on_complete));
      if (!scheduled_) {
        scheduled_ = true;
        need_schedule = true;
      }
    }
    if (need_schedule) {
      runner_.Post([this]() { DrainLatest(); });
    }
  }

  void Shutdown() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      stopping_ = true;
    }
    runner_.Shutdown();
  }

 private:
  void DrainLatest() {
    for (;;) {
      State current{};
      std::vector<CompleteFn> callbacks;
      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!has_pending_) {
          scheduled_ = false;
          return;
        }
        current = std::move(pending_state_);
        callbacks = std::move(pending_callbacks_);
        has_pending_ = false;
      }
      const Outcome outcome = apply_(current);
      for (auto& cb : callbacks) {
        if (cb) {
          cb(outcome);
        }
      }
    }
  }

  ApplyFn apply_;
  SerialTaskRunner runner_;
  std::mutex mutex_;
  State pending_state_{};
  std::vector<CompleteFn> pending_callbacks_;
  bool has_pending_ = false;
  bool scheduled_ = false;
  bool stopping_ = false;
};

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
