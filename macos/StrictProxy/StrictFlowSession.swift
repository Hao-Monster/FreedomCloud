import Foundation
import NetworkExtension

/// The provider retains the session until onClosed. Unsupported or failed flows
/// are closed explicitly; this object never returns a direct network fallback.
final class StrictFlowSession {
    private let flow: NEAppProxyFlow
    private let transport: StrictSOCKSConnection
    private let onClosed: () -> Void
    private let lock = NSLock()
    private var closed = false
    private var task: Task<Void, Never>?
    private var idleTimer: DispatchWorkItem?
    private let timerQueue = DispatchQueue(label: "FreedomCloud.StrictFlowTimeout")

    init(flow: NEAppProxyFlow, policy: StrictApplicationPolicy, onClosed: @escaping () -> Void) {
        self.flow = flow
        self.transport = StrictSOCKSConnection(policy: policy)
        self.onClosed = onClosed
    }
    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, task == nil else { return }
        task = Task { [weak self] in
            guard let self = self, !Task.isCancelled else { return }
            do {
                if let tcp = self.flow as? NEAppProxyTCPFlow {
                    guard let endpoint = tcp.remoteEndpoint as? NWHostEndpoint,
                          let port = UInt16(endpoint.port), port > 0 else {
                        throw StrictProxyError(message: "Missing TCP endpoint")
                    }
                    try await self.transport.connect(host: endpoint.hostname, port: port, udp: false)
                    try await self.open()
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask { try await self.tcpOutgoing(tcp) }
                        group.addTask { try await self.tcpIncoming(tcp) }
                        try await group.waitForAll()
                    }
                } else if let udp = self.flow as? NEAppProxyUDPFlow {
                    try await self.transport.connect(host: "0.0.0.0", port: 0, udp: true)
                    try await self.open()
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask { try await self.udpOutgoing(udp) }
                        group.addTask { try await self.udpIncoming(udp) }
                        // Any finished direction closes siblings, including suspended IO.
                        do { _ = try await group.next() }
                        catch { self.close(error); throw error }
                        self.close(nil)
                        group.cancelAll()
                    }
                } else { throw StrictProxyError(message: "Unsupported flow protocol") }
                self.close(nil)
            } catch { self.close(error) }
        }
    }
    func close(_ error: Error?) {
        lock.lock()
        if closed { lock.unlock(); return }
        closed = true
        idleTimer?.cancel()
        lock.unlock()
        transport.close()
        flow.closeReadWithError(error)
        flow.closeWriteWithError(error)
        task?.cancel()
        onClosed()
    }
    private func touch() {
        lock.lock()
        defer { lock.unlock() }
        if closed { return }
        idleTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in self?.close(StrictProxyError(message: "Flow idle timeout")) }
        idleTimer = timer
        timerQueue.asyncAfter(deadline: .now() + 300, execute: timer)
    }
    private func open() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            flow.open(withLocalEndpoint: nil) { error in
                if let error = error { c.resume(throwing: error) } else { c.resume() }
            }
        }
        touch()
    }
    private func tcpOutgoing(_ flow: NEAppProxyTCPFlow) async throws {
        do {
            while !Task.isCancelled {
                let data: Data? = try await withCheckedThrowingContinuation { c in
                    flow.readData { data, error in
                        if let error = error { c.resume(throwing: error) } else { c.resume(returning: data) }
                    }
                }
                guard let data = data, !data.isEmpty else { try await transport.finishWrite(); return }
                try await transport.write(data)
                touch()
            }
        } catch { close(error); throw error }
    }
    private func tcpIncoming(_ flow: NEAppProxyTCPFlow) async throws {
        do {
            while !Task.isCancelled {
                guard let data = try await transport.read() else { flow.closeWriteWithError(nil); return }
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                    flow.write(data) { error in
                        if let error = error { c.resume(throwing: error) } else { c.resume() }
                    }
                }
                touch()
            }
        } catch { close(error); throw error }
    }
    private func udpOutgoing(_ flow: NEAppProxyUDPFlow) async throws {
        while !Task.isCancelled {
            let batch: ([Data], [NWEndpoint]) = try await withCheckedThrowingContinuation { c in
                flow.readDatagrams { data, endpoints, error in
                    if let error = error { c.resume(throwing: error) }
                    else { c.resume(returning: (data ?? [], endpoints ?? [])) }
                }
            }
            if batch.0.isEmpty { return }
            guard batch.0.count == batch.1.count, batch.0.count <= 1024 else {
                throw StrictProxyError(message: "Invalid UDP batch")
            }
            for (data, endpoint) in zip(batch.0, batch.1) {
                guard let host = endpoint as? NWHostEndpoint, let port = UInt16(host.port), port > 0 else {
                    throw StrictProxyError(message: "Invalid UDP destination")
                }
                try await transport.sendDatagram(data, host: host.hostname, port: port)
                touch()
            }
        }
    }
    private func udpIncoming(_ flow: NEAppProxyUDPFlow) async throws {
        while !Task.isCancelled {
            let (data, host, port) = try await transport.readDatagram()
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                flow.writeDatagrams([data], sentBy: [NWHostEndpoint(hostname: host, port: String(port))]) { error in
                    if let error = error { c.resume(throwing: error) } else { c.resume() }
                }
            }
            touch()
        }
    }
}
