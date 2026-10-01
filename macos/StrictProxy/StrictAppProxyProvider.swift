import Foundation
import NetworkExtension

/// Only MDM-selected flows reach this provider. Returning false here would
/// delegate their disposition, so even unknown identities are explicitly closed.
final class StrictAppProxyProvider: NEAppProxyProvider {
    private let controlQueue = DispatchQueue(label: "FreedomCloud.StrictProviderControl")
    private var dispatcher = StrictFlowDispatcher()
    private var store: StrictProviderStore?
    private var key: Data?
    private var generation: UInt64 = 0
    private var started = false
    private var ready = false
    private var applying = false
    private var lifecycle: UInt64 = 0

    override func startProxy(options: [String: Any]? = nil,
                             completionHandler: @escaping (Error?) -> Void) {
        controlQueue.async {
            self.lifecycle &+= 1
            self.applying = false
            self.dispatcher.stop()
            self.dispatcher = StrictFlowDispatcher()
            self.ready = false
            self.started = false
            self.generation = 0
            self.key = nil
            self.store = nil
            do {
                guard let vpn = self.protocolConfiguration as? NETunnelProviderProtocol,
                      let account = vpn.providerConfiguration?["controlKeyAccount"] as? String else {
                    throw StrictProxyError(message: "Managed provider configuration is incomplete")
                }
                if options?["controlKey"] != nil && !(options?["controlKey"] is Data) {
                    throw StrictProxyError(message: "Invalid control key bootstrap")
                }
                let store = try StrictProviderStore(account: account)
                let key = try store.controlKey(bootstrap: options?["controlKey"] as? Data)
                self.store = store
                self.key = key
                self.started = true
                if let saved = try store.savedEnvelope() {
                    let envelope = try StrictControlEnvelope.open(saved, key: key, after: 0)
                    let configuration = try self.decode(envelope)
                    self.generation = envelope.generation
                    self.install(configuration, completion: completionHandler)
                    return
                }
                // First activation intentionally starts blocked until the host
                // delivers a policy through the authenticated provider channel.
                completionHandler(nil)
            } catch {
                self.started = false
                self.key = nil
                self.store = nil
                self.dispatcher.stop()
                completionHandler(StrictProxyError(message: "Managed strict provider could not restore authenticated policy"))
            }
        }
    }

    override func stopProxy(with reason: NEProviderStopReason,
                            completionHandler: @escaping () -> Void) {
        controlQueue.async {
            self.lifecycle &+= 1
            self.applying = false
            self.started = false
            self.ready = false
            self.dispatcher.stop()
            self.key = nil
            self.store = nil
            completionHandler()
        }
    }

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        controlQueue.sync {
            guard started, ready else {
                reject(flow)
                return
            }
            if case .unselected = dispatcher.handle(flow) { reject(flow) }
        }
        return true
    }

    override func handleAppMessage(_ messageData: Data,
                                   completionHandler: ((Data?) -> Void)? = nil) {
        controlQueue.async {
            guard messageData.count <= 400000 else {
                self.reply(completionHandler, ok: false, code: "messageTooLarge")
                return
            }
            if let request = try? JSONSerialization.jsonObject(with: messageData) as? [String: String],
               request.count == 1, request["operation"] == "status" {
                self.reply(completionHandler, ok: true, code: "status")
                return
            }
            guard self.started, let key = self.key, let store = self.store else {
                self.reply(completionHandler, ok: false, code: "providerNotStarted")
                return
            }
            guard !self.applying else {
                self.reply(completionHandler, ok: false, code: "configurationInProgress")
                return
            }
            do {
                let envelope = try StrictControlEnvelope.open(messageData, key: key, after: self.generation)
                let configuration = try self.decode(envelope)
                // Revoke active flows before saving; failed storage leaves a
                // visible blocked state, never an acknowledged transient policy.
                self.ready = false
                self.dispatcher.stop()
                try store.save(envelope: messageData)
                self.generation = envelope.generation
                self.install(configuration) { error in
                    self.reply(completionHandler, ok: error == nil,
                               code: error == nil ? "configured" : "networkSettingsRejected")
                }
            } catch {
                self.reply(completionHandler, ok: false, code: "configurationRejected")
            }
        }
    }

    private func install(_ configuration: StrictProxyConfiguration,
                         completion: @escaping (Error?) -> Void) {
        let revision = lifecycle
        applying = true
        // Both completion paths execute on controlQueue. A lost OS callback must
        // not retain an unbounded host request or later resurrect a timed-out policy.
        var completed = false
        controlQueue.asyncAfter(deadline: .now() + 15) {
            guard !completed else { return }
            completed = true
            if self.lifecycle == revision {
                self.applying = false
                self.ready = false
                self.dispatcher.stop()
            }
            completion(StrictProxyError(message: "Managed network settings timed out"))
        }
        let settings = NETunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        if !configuration.dnsServers.isEmpty {
            let dns = NEDNSSettings(servers: configuration.dnsServers)
            dns.matchDomains = [""]
            dns.matchDomainsNoSearch = true
            settings.dnsSettings = dns
        }
        setTunnelNetworkSettings(settings) { error in
            self.controlQueue.async {
                guard !completed else { return }
                completed = true
                guard self.started, self.lifecycle == revision else {
                    completion(StrictProxyError(message: "Provider stopped during configuration"))
                    return
                }
                self.applying = false
                do {
                    if let error = error { throw error }
                    try self.dispatcher.configure(configuration)
                    self.ready = true
                    completion(nil)
                } catch {
                    self.ready = false
                    self.dispatcher.stop()
                    completion(StrictProxyError(message: "Managed DNS or policy configuration failed"))
                }
            }
        }
    }

    private func decode(_ envelope: StrictControlEnvelope) throws -> StrictProxyConfiguration {
        let configuration = try JSONDecoder().decode(StrictProxyConfiguration.self, from: envelope.body)
        guard configuration.generation == envelope.generation else {
            throw StrictProxyError(message: "Configuration generation mismatch")
        }
        try configuration.validate()
        return configuration
    }

    private func reply(_ handler: ((Data?) -> Void)?, ok: Bool, code: String) {
        var status = dispatcher.status
        status["generation"] = generation
        status["ok"] = ok
        status["code"] = code
        status["ready"] = started && ready
        status["applying"] = applying
        handler?(try? JSONSerialization.data(withJSONObject: status, options: [.sortedKeys]))
    }

    private func reject(_ flow: NEAppProxyFlow) {
        let error = StrictProxyError(message: "Managed application is blocked until exact authenticated policy is ready")
        flow.closeReadWithError(error)
        flow.closeWriteWithError(error)
    }
}
