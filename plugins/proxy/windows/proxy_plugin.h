#ifndef FLUTTER_PLUGIN_PROXY_PLUGIN_H_
#define FLUTTER_PLUGIN_PROXY_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

#include "proxy_settings.h"

namespace proxy {

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
  SerialTaskRunner worker_;
};

}  // namespace proxy

#endif  // FLUTTER_PLUGIN_PROXY_PLUGIN_H_
