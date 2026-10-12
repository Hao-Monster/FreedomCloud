#include "proxy_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <WinInet.h>
#include <Ras.h>
#include <RasError.h>
#include <vector>
#include <iostream>

#pragma comment(lib, "wininet")
#pragma comment(lib, "Rasapi32")

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>

#include "proxy_settings.h"

namespace proxy
{

  // Use the OS PAC engine. Never evaluate user-provided JavaScript in the UI.
  bool SetPac(const std::string& address) {
    if (address.size() > 2048 ||
        (address.rfind("https://", 0) != 0 && address.rfind("http://", 0) != 0) ||
        address.find_first_of("\r\n\t ") != std::string::npos ||
        address.find('\0') != std::string::npos) return false;
    std::wstring wide;
    if (!Utf8ToWide(address, &wide)) return false;
    INTERNET_PER_CONN_OPTIONW options[2]{};
    options[0].dwOption = INTERNET_PER_CONN_FLAGS;
    options[0].Value.dwValue = PROXY_TYPE_AUTO_PROXY_URL;
    options[1].dwOption = INTERNET_PER_CONN_AUTOCONFIG_URL;
    options[1].Value.pszValue = wide.data();
    INTERNET_PER_CONN_OPTION_LISTW list{};
    list.dwSize = sizeof(list);
    list.dwOptionCount = 2;
    list.pOptions = options;
    if (!InternetSetOptionW(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION,
        &list, sizeof(list))) return false;
    const bool changed = InternetSetOptionW(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0);
    const bool refreshed = InternetSetOptionW(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0);
    return changed && refreshed;
  }

  // static
  void ProxyPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarWindows *registrar)
  {
    auto channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "proxy",
            &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<ProxyPlugin>();

    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto &call, auto result)
        {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
  }

  ProxyPlugin::ProxyPlugin() {}

  ProxyPlugin::~ProxyPlugin() {}

  void ProxyPlugin::HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
  {
    if (method_call.method_name() == "StartPac")
    {
      const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
      if (!args) { result->Error("invalid_arguments", "PAC URL required"); return; }
      const auto entry = args->find(flutter::EncodableValue("url"));
      if (entry == args->end()) { result->Error("invalid_arguments", "PAC URL required"); return; }
      const auto* url = std::get_if<std::string>(&entry->second);
      if (!url) { result->Error("invalid_arguments", "PAC URL must be a string"); return; }
      if (!SetPac(*url)) { result->Error("pac_failed", "Windows could not apply PAC settings"); return; }
      result->Success(true);
    }
    else if (method_call.method_name().compare("StopProxy") == 0)
    {
      const auto applied = ApplySystemProxy(false, 0, {});
      if (!applied.ok()) {
        result->Error("proxy_failed", applied.stage,
            flutter::EncodableValue(static_cast<int64_t>(applied.error)));
        return;
      }
      result->Success(true);
    }
    else if (method_call.method_name().compare("StartProxy") == 0)
    {
      const auto* arguments = method_call.arguments()
          ? std::get_if<flutter::EncodableMap>(method_call.arguments()) : nullptr;
      if (!arguments) { result->Error("invalid_arguments", "Proxy arguments required"); return; }
      const auto port_entry = arguments->find(flutter::EncodableValue("port"));
      const auto bypass_entry = arguments->find(flutter::EncodableValue("bypassDomain"));
      const auto* port = port_entry == arguments->end() ? nullptr : std::get_if<int>(&port_entry->second);
      const auto* domains = bypass_entry == arguments->end() ? nullptr
          : std::get_if<flutter::EncodableList>(&bypass_entry->second);
      if (!port || !domains) { result->Error("invalid_arguments", "Invalid proxy port or bypass list"); return; }
      if (domains->size() > 4096) { result->Error("invalid_arguments", "Too many bypass entries"); return; }
      std::vector<std::string> bypass;
      bypass.reserve(domains->size());
      for (const auto& domain : *domains) {
        const auto* text = std::get_if<std::string>(&domain);
        if (!text) { result->Error("invalid_arguments", "Bypass entries must be strings"); return; }
        bypass.push_back(*text);
      }
      const auto applied = ApplySystemProxy(true, *port, bypass);
      if (!applied.ok()) {
        result->Error("proxy_failed", applied.stage,
            flutter::EncodableValue(static_cast<int64_t>(applied.error)));
        return;
      }
      result->Success(true);
    }
    else
    {
      result->NotImplemented();
    }
  }
} // namespace proxy
