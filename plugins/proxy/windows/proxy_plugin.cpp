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

#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>
#include <utility>

#include "proxy_settings.h"

namespace proxy
{

  bool IsValidPacUrl(const std::string& address) {
    return address.size() <= 2048 &&
           (address.rfind("https://", 0) == 0 || address.rfind("http://", 0) == 0) &&
           address.find_first_of("\r\n\t ") == std::string::npos &&
           address.find('\0') == std::string::npos;
  }

  // Use the OS PAC engine. Never evaluate user-provided JavaScript in the UI.
  bool SetPac(const std::string& address) {
    if (!IsValidPacUrl(address)) return false;
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

  namespace {
  ProxyApplyOutcome ApplyDesiredProxyState(const DesiredProxyState& desired) {
    ProxyApplyOutcome outcome;
    outcome.mode = desired.mode;
    switch (desired.mode) {
      case DesiredProxyMode::kPac:
        outcome.pac_ok = SetPac(desired.pac_url);
        break;
      case DesiredProxyMode::kStop:
        outcome.proxy_result = ApplySystemProxy(false, 0, {});
        break;
      case DesiredProxyMode::kSystemProxy:
        outcome.proxy_result =
            ApplySystemProxy(true, desired.port, desired.bypass);
        break;
    }
    return outcome;
  }

  void CompleteMethodResult(
      const std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>& result,
      const ProxyApplyOutcome& outcome) {
    if (!result) return;
    if (outcome.mode == DesiredProxyMode::kPac) {
      if (!outcome.pac_ok) {
        result->Error("pac_failed", "Windows could not apply PAC settings");
        return;
      }
      result->Success(flutter::EncodableValue(true));
      return;
    }
    if (!outcome.proxy_result.ok()) {
      result->Error(
          "proxy_failed", outcome.proxy_result.stage,
          flutter::EncodableValue(static_cast<int64_t>(outcome.proxy_result.error)));
      return;
    }
    result->Success(flutter::EncodableValue(true));
  }
  }  // namespace

  ProxyPlugin::ProxyPlugin() : state_runner_(ApplyDesiredProxyState) {}

  ProxyPlugin::~ProxyPlugin() {
    state_runner_.Shutdown();
  }

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
      DesiredProxyState desired;
      desired.mode = DesiredProxyMode::kPac;
      desired.pac_url = *url;
      std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> shared_result(
          std::move(result));
      state_runner_.Submit(std::move(desired),
                           [shared_result](const ProxyApplyOutcome& outcome) {
                             CompleteMethodResult(shared_result, outcome);
                           });
    }
    else if (method_call.method_name().compare("StopProxy") == 0)
    {
      DesiredProxyState desired;
      desired.mode = DesiredProxyMode::kStop;
      std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> shared_result(
          std::move(result));
      state_runner_.Submit(std::move(desired),
                           [shared_result](const ProxyApplyOutcome& outcome) {
                             CompleteMethodResult(shared_result, outcome);
                           });
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
      DesiredProxyState desired;
      desired.mode = DesiredProxyMode::kSystemProxy;
      desired.port = *port;
      desired.bypass = std::move(bypass);
      std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> shared_result(
          std::move(result));
      state_runner_.Submit(std::move(desired),
                           [shared_result](const ProxyApplyOutcome& outcome) {
                             CompleteMethodResult(shared_result, outcome);
                           });
    }
    else
    {
      result->NotImplemented();
    }
  }
} // namespace proxy
