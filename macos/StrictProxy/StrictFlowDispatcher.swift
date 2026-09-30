import Foundation
import NetworkExtension

struct StrictProxyConfiguration: Codable {
    let generation: UInt64
    let policies: [StrictApplicationPolicy]
    func validate() throws {
        guard generation > 0, policies.count <= 256 else {
            throw StrictProxyError(message: "Invalid policy generation or identity limit")
        }
        var identities = Set<String>()
        for policy in policies {
            try policy.validate()
            guard identities.insert(policy.signingIdentifier).inserted else {
                throw StrictProxyError(message: "Duplicate signing identity")
            }
        }
    }
}

/// Reusable capture dispatch shared by a provisioned app proxy or a future
/// transparent provider with a independently established persistent guard.
/// Does not advertise installed or crash-safe enforcement on its own.
final class StrictFlowDispatcher {
    enum Decision { case unselected, handled }
    private let lock = NSLock()
    private var configuration: StrictProxyConfiguration?
    private var sessions: [UUID: StrictFlowSession] = [:]
    private var stopping = false

    func configure(_ next: StrictProxyConfiguration) throws {
        try next.validate()
        lock.lock()
        guard configuration == nil || next.generation > configuration!.generation else {
            lock.unlock()
            throw StrictProxyError(message: "Stale policy generation")
        }
        configuration = next
        stopping = false
        let previous = Array(sessions.values)
        sessions.removeAll()
        lock.unlock()
        // Policy changes revoke old sessions; a stale target is never retained.
        for session in previous { session.close(StrictProxyError(message: "Policy changed")) }
    }
    func handle(_ flow: NEAppProxyFlow) -> Decision {
        lock.lock()
        guard let configuration = configuration, !stopping else {
            lock.unlock()
            reject(flow, "Policy not ready")
            return .handled
        }
        guard let policy = configuration.policies.first(where: {
            $0.signingIdentifier == flow.metaData.sourceAppSigningIdentifier
        }) else { lock.unlock(); return .unselected }
        guard StrictApplicationIdentity.matches(policy, metadata: flow.metaData),
              policy.action == "proxy", sessions.count < 256 else {
            lock.unlock()
            reject(flow, "Blocked policy, changed identity, or capacity exhausted")
            return .handled
        }
        let id = UUID()
        let session = StrictFlowSession(flow: flow, policy: policy) { [weak self] in
            self?.remove(id)
        }
        sessions[id] = session
        lock.unlock()
        session.start()
        return .handled
    }
    func stop() {
        lock.lock()
        stopping = true
        let previous = Array(sessions.values)
        sessions.removeAll()
        lock.unlock()
        for session in previous { session.close(StrictProxyError(message: "Provider stopped")) }
    }
    var status: [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return ["generation": configuration?.generation ?? 0,
                "identityCount": configuration?.policies.count ?? 0,
                "activeFlows": sessions.count, "stopping": stopping]
    }
    private func remove(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        sessions.removeValue(forKey: id)
    }
    private func reject(_ flow: NEAppProxyFlow, _ message: String) {
        let error = StrictProxyError(message: message)
        flow.closeReadWithError(error)
        flow.closeWriteWithError(error)
    }
}
