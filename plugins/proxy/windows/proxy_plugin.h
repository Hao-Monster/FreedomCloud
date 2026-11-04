#ifndef FLUTTER_PLUGIN_PROXY_PLUGIN_H_
#define FLUTTER_PLUGIN_PROXY_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>
#include <string>
#include <vector>

#include "proxy_settings.h"

namespace proxy {

enum class DesiredProxyMode {
  kStop,
  kSystemProxy,
  kPac,
};

struct DesiredProxyState {
  DesiredProxyMode mode = DesiredProxyMode::kStop;
  int port = 0;
  std::vector<std::string> bypass;
  std::string pac_url;
};

struct ProxyApplyOutcome {
  DesiredProxyMode mode = DesiredProxyMode::kStop;
  ProxyResult proxy_result;
  bool pac_ok = false;
};

class ProxyPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  ProxyPlugin();

  virtual ~ProxyPlugin();

  // Disallow copy and assign.
  ProxyPlugin(const ProxyPlugin&) = delete;
  ProxyPlugin& operator=(const ProxyPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  CoalescingStateRunner<DesiredProxyState, ProxyApplyOutcome> state_runner_;
};

}  // namespace proxy

#endif  // FLUTTER_PLUGIN_PROXY_PLUGIN_H_
