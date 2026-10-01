import Foundation
import FlutterMacOS
import NetworkExtension
import Security
import SystemExtensions

/// Controls only an already provisioned per-app VPN. MDM remains the owner of
/// application mappings; stopping the provider must never delete those mappings.
final class ManagedStrictProxyController: NSObject, OSSystemExtensionRequestDelegate {
    private var activationResult: FlutterResult?
    private var busy = false
    private let channel: FlutterMethodChannel
    private var providerID: String { Bundle.main.object(forInfoDictionaryKey: "FCXStrictProviderBundleIdentifier") as? String ?? "" }
    private var accessGroup: String { Bundle.main.object(forInfoDictionaryKey: "FCXStrictKeychainAccessGroup") as? String ?? "" }

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "freedomcloud/managed_strict", binaryMessenger: messenger)
        super.init()
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            self.handle(call, result: result)
        }
    }
    private func fail(_ result: @escaping FlutterResult, _ error: Error) {
        result(FlutterError(code: "MANAGED_STRICT", message: error.localizedDescription, details: nil))
    }
    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "enableBackgroundAgent" || call.method == "disableBackgroundAgent" {
            guard !busy else { result(FlutterError(code: "BUSY", message: "A managed operation is pending", details: nil)); return }
            busy = true
            let home = (call.arguments as? [String: Any])?["home"] as? String
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let reply: [String: Any]
                    if call.method == "enableBackgroundAgent" {
                        guard let home = home else { throw StrictProxyError(message: "Agent home is required") }
                        reply = ManagedAgentLogin.install(home: home)
                    } else {
                        reply = ManagedAgentLogin.uninstall()
                    }
                    guard reply["success"] as? Bool == true else {
                        throw StrictProxyError(message: reply["error"] as? String ?? "Background Agent registration failed")
                    }
                    DispatchQueue.main.async { self.busy = false; result(reply) }
                } catch {
                    DispatchQueue.main.async { self.busy = false; self.fail(result, error) }
                }
            }
            return
        }
        if call.method == "activateExtension" {
            guard activationResult == nil, !providerID.isEmpty else {
                result(FlutterError(code: "BUSY", message: "Extension activation unavailable or pending", details: nil)); return
            }
            activationResult = result
            let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: providerID, queue: .main)
            request.delegate = self
            OSSystemExtensionManager.shared.submitRequest(request)
            return
        }
        if call.method == "exportIdentities" {
            do {
                guard let paths = call.arguments as? [String], !paths.isEmpty, paths.count <= 128 else {
                    throw StrictProxyError(message: "Select 1 to 128 managed executables")
                }
                let applications = try paths.map { path -> [String: String] in
                    var identity = try StrictApplicationIdentity.inspect(executable: URL(fileURLWithPath: path))
                    var directory = URL(fileURLWithPath: path).standardizedFileURL
                    while directory.path != "/" && directory.pathExtension != "app" { directory.deleteLastPathComponent() }
                    guard let bundle = Bundle(url: directory), let identifier = bundle.bundleIdentifier else {
                        throw StrictProxyError(message: "MDM mappings require an application bundle")
                    }
                    identity["identifier"] = identifier
                    return identity
                }
                let extensionURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/SystemExtensions")
                    .appendingPathComponent(providerID + ".systemextension")
                var provider = try StrictApplicationIdentity.inspect(executable: extensionURL)
                provider["identifier"] = providerID
                result(["schemaVersion": 1, "provider": provider, "applications": applications])
            } catch { fail(result, error) }
            return
        }
        if call.method == "inspectIdentity" {
            do {
                guard let path = call.arguments as? String, path.hasPrefix("/"), path.utf8.count <= 4096 else {
                    throw StrictProxyError(message: "An absolute executable path is required")
                }
                result(try StrictApplicationIdentity.inspect(executable: URL(fileURLWithPath: path)))
            } catch { fail(result, error) }
            return
        }
        guard ["profiles", "prepare", "status", "configure", "stop", "quarantineAll"].contains(call.method) else {
            result(FlutterMethodNotImplemented); return
        }
        guard !busy else { result(FlutterError(code: "BUSY", message: "A managed VPN operation is pending", details: nil)); return }
        busy = true
        let finish: FlutterResult = { value in DispatchQueue.main.async { self.busy = false; result(value) } }
        NEAppProxyProviderManager.loadAllFromPreferences { managers, error in
            if let error = error { self.fail(finish, error); return }
            let matching = (managers ?? []).filter {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.providerID
            }
            if call.method == "quarantineAll" {
                self.quarantine(matching, index: 0, result: finish)
                return
            }
            if call.method == "profiles" {
                finish(matching.map { manager -> [String: Any] in
                    let proto = manager.protocolConfiguration as? NETunnelProviderProtocol
                    return ["name": manager.localizedDescription ?? "Managed VPN",
                            "account": proto?.providerConfiguration?["controlKeyAccount"] as? String ?? "",
                            "status": manager.connection.status.rawValue,
                            "identities": manager.appRules.map { $0.matchSigningIdentifier }]
                }); return
            }
            if ["prepare", "configure"].contains(call.method) && matching.count != 1 {
                self.fail(finish, StrictProxyError(message: "Exactly one managed strict profile may own this Core; replace obsolete MDM profiles first")); return
            }
            let args = call.arguments as? [String: Any] ?? [:]
            guard let account = args["account"] as? String, UUID(uuidString: account) != nil,
                  let manager = matching.first(where: {
                      (($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration?["controlKeyAccount"] as? String) == account
                  }), let session = manager.connection as? NETunnelProviderSession else {
                self.fail(finish, StrictProxyError(message: "Install a matching MDM per-app VPN profile with controlKeyAccount first")); return
            }
            do {
                if call.method == "stop" {
                    self.quarantine([manager], index: 0, result: finish)
                    return
                }
                if call.method == "prepare" {
                    let key = try self.key(account: account, create: true)
                    guard manager.isEnabled, manager.isOnDemandEnabled,
                          let rules = manager.onDemandRules, !rules.isEmpty,
                          rules.allSatisfy({ $0 is NEOnDemandRuleConnect }) else {
                        throw StrictProxyError(message: "Managed profile must be enabled with connect-only on-demand rules; bypass/evaluate rules are rejected")
                    }
                    if session.status == .disconnected || session.status == .invalid { try session.startTunnel(options: ["controlKey": key as NSData]) }
                    finish(["startRequested": true]); return
                }
                guard session.status == .connected else { throw StrictProxyError(message: "Managed VPN is not connected; prepare it and refresh status") }
                if call.method == "status" {
                    try self.send(Data("{\"operation\":\"status\"}".utf8), session: session, result: finish); return
                }
                guard manager.isEnabled, manager.isOnDemandEnabled,
                      let demandRules = manager.onDemandRules, !demandRules.isEmpty,
                      demandRules.allSatisfy({ $0 is NEOnDemandRuleConnect }) else {
                    throw StrictProxyError(message: "Managed profile no longer enforces connect-only routing")
                }
                guard let raw = args["configuration"] as? [String: Any] else { throw StrictProxyError(message: "Missing configuration") }
                let body = try JSONSerialization.data(withJSONObject: raw)
                let configuration = try JSONDecoder().decode(StrictProxyConfiguration.self, from: body)
                try configuration.validate()
                let mapped = Set(manager.appRules.map { $0.matchSigningIdentifier })
                let selected = Set(configuration.policies.map { $0.signingIdentifier })
                guard mapped == selected, !mapped.isEmpty else {
                    throw StrictProxyError(message: "MDM application mappings must exactly match the selected strict identities")
                }
                guard let paths = args["paths"] as? [String], paths.count == configuration.policies.count else {
                    throw StrictProxyError(message: "Exact executable paths are required")
                }
                for (index, policy) in configuration.policies.enumerated() {
                    guard let rule = manager.appRules.first(where: { $0.matchSigningIdentifier == policy.signingIdentifier }),
                          (rule.matchDomains ?? []).isEmpty, (rule.matchTools ?? []).isEmpty else {
                        throw StrictProxyError(message: "Domain-limited or helper-only MDM mappings cannot protect the complete selected application")
                    }
                    let selectedURL = URL(fileURLWithPath: paths[index])
                    let url = (Bundle(url: selectedURL)?.executableURL ?? selectedURL).resolvingSymlinksInPath().standardizedFileURL
                    let identity = try StrictApplicationIdentity.inspect(executable: url)
                    guard identity["signingIdentifier"] == policy.signingIdentifier,
                          identity["codeDirectoryHash"] == policy.codeDirectoryHash.lowercased(),
                          rule.matchPath == nil || rule.matchPath == url.path else {
                        throw StrictProxyError(message: "Executable identity does not match the selected MDM rule")
                    }
                    var requirement: SecRequirement?
                    var code: SecStaticCode?
                    guard SecRequirementCreateWithString(rule.matchDesignatedRequirement as CFString, [], &requirement) == errSecSuccess,
                          SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
                          let code = code, let requirement = requirement,
                          SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else {
                        throw StrictProxyError(message: "MDM signing requirement does not match the actual executable")
                    }
                }
                let envelope = try StrictControlEnvelope.sign(generation: configuration.generation, body: body,
                                                              key: self.key(account: account, create: false))
                try self.send(envelope, session: session, result: finish)
            } catch { self.fail(finish, error) }
        }
    }
    private func quarantine(_ managers: [NEAppProxyProviderManager], index: Int, result: @escaping FlutterResult) {
        guard index < managers.count else { result(["ok": true, "managedMappingsRetained": true]); return }
        let manager = managers[index]
        guard let session = manager.connection as? NETunnelProviderSession,
              let account = (manager.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration?["controlKeyAccount"] as? String,
              session.status == .connected else {
            fail(result, StrictProxyError(message: "Start the managed provider before editing policies so the previous policy can be revoked")); return
        }
        do {
            let key = try self.key(account: account, create: false)
            try send(Data("{\"operation\":\"status\"}".utf8), session: session) { response in
                do {
                    guard let status = response as? [String: Any], status["ok"] as? Bool == true,
                          let generation = status["generation"] as? NSNumber, generation.uint64Value < UInt64.max else {
                        throw StrictProxyError(message: "Cannot read provider generation for revocation")
                    }
                    let next = generation.uint64Value + 1
                    let body = try JSONSerialization.data(withJSONObject: ["generation": next, "policies": [], "dnsServers": []])
                    let envelope = try StrictControlEnvelope.sign(generation: next, body: body, key: key)
                    try self.send(envelope, session: session) { reply in
                        guard let acknowledged = reply as? [String: Any], acknowledged["ok"] as? Bool == true else {
                            self.fail(result, StrictProxyError(message: "Provider did not acknowledge policy revocation")); return
                        }
                        self.quarantine(managers, index: index + 1, result: result)
                    }
                } catch { self.fail(result, error) }
            }
        } catch { fail(result, error) }
    }
    private func send(_ message: Data, session: NETunnelProviderSession, result: @escaping FlutterResult) throws {
        var completed = false
        let finish: FlutterResult = { value in
            DispatchQueue.main.async { if !completed { completed = true; result(value) } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            finish(FlutterError(code: "TIMEOUT", message: "Provider did not acknowledge; selected apps remain managed", details: nil))
        }
        do {
            try session.sendProviderMessage(message) { data in
                guard let data = data, data.count <= 65536,
                      let value = try? JSONSerialization.jsonObject(with: data) else {
                    finish(FlutterError(code: "PROVIDER_REPLY", message: "Invalid provider acknowledgement", details: nil)); return
                }
                finish(value)
            }
        } catch {
            finish(FlutterError(code: "PROVIDER_SEND", message: "Cannot send provider message", details: nil))
        }
    }
    private func key(account: String, create: Bool) throws -> Data {
        guard !accessGroup.isEmpty, !accessGroup.contains("$(") else { throw StrictProxyError(message: "Missing signed Keychain access group") }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.freedomcloud.strict.control", kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup, kSecUseDataProtectionKeychain as String: true]
        var lookup = query
        lookup[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecSuccess, let key = item as? Data, key.count == 32 { return key }
        guard status == errSecItemNotFound, create else { throw StrictProxyError(message: "Control Keychain unavailable (\(status))") }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw StrictProxyError(message: "Secure random unavailable") }
        let key = Data(bytes)
        var insert = query
        insert[kSecValueData as String] = key
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(insert as CFDictionary, nil)
        guard added == errSecSuccess else { throw StrictProxyError(message: "Cannot create control key (\(added))") }
        return key
    }
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        channel.invokeMethod("activationNeedsApproval", arguments: nil)
    }
    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction { .replace }
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        activationResult?(["activationCompleted": result == .completed, "rebootRequired": result == .willCompleteAfterReboot])
        activationResult = nil
    }
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        if let result = activationResult { fail(result, error) }
        activationResult = nil
    }
}
