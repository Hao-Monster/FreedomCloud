import Foundation
import Network
import Darwin

struct StrictProxyError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct StrictApplicationPolicy: Codable {
    let signingIdentifier: String
    let codeDirectoryHash: String
    let action: String
    let port: UInt16
    let username: String
    let password: String

    func validate() throws {
        guard !signingIdentifier.isEmpty, signingIdentifier.utf8.count <= 255,
              codeDirectoryHash.count >= 40, codeDirectoryHash.count <= 64,
              codeDirectoryHash.allSatisfy({ $0.isHexDigit }),
              action == "proxy" || action == "block",
              action == "block" || (port > 0 && !username.isEmpty && !password.isEmpty &&
                username.utf8.count <= 255 && password.utf8.count <= 255) else {
            throw StrictProxyError(message: "Invalid exact application policy")
        }
    }
}

/// One bounded SOCKS session per intercepted flow; no direct destination socket.
final class StrictSOCKSConnection {
    private let control: NWConnection
    private let queue = DispatchQueue(label: "FreedomCloud.StrictSOCKS")
    private var datagrams: NWConnection?
    private var timeout: DispatchWorkItem?
    private let policy: StrictApplicationPolicy

    init(policy: StrictApplicationPolicy) {
        self.policy = policy
        self.control = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: policy.port)!, using: .tcp)
    }
    func close() {
        timeout?.cancel()
        control.cancel()
        datagrams?.cancel()
    }
    deinit { close() }

    private func ready(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            connection.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume()
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: error)
                case .cancelled:
                    resumed = true
                    continuation.resume(throwing: StrictProxyError(message: "Connection cancelled"))
                default: break
                }
            }
            connection.start(queue: self.queue)
        }
    }
    private func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error { c.resume(throwing: error) } else { c.resume() }
            })
        }
    }
    private func exact(_ count: Int) async throws -> Data {
        var data = Data()
        while data.count < count {
            let part: Data = try await withCheckedThrowingContinuation { c in
                control.receive(minimumIncompleteLength: 1, maximumLength: count - data.count) { bytes, _, done, error in
                    if let error = error { c.resume(throwing: error) }
                    else if let bytes = bytes, !bytes.isEmpty { c.resume(returning: bytes) }
                    else { c.resume(throwing: StrictProxyError(message: done ? "SOCKS closed" : "Empty SOCKS response")) }
                }
            }
            data.append(part)
        }
        return data
    }
    static func address(host: String, port: UInt16) throws -> Data {
        let name = Data(host.utf8)
        guard !name.isEmpty, name.count <= 255 else { throw StrictProxyError(message: "Invalid destination") }
        return Data([3, UInt8(name.count)]) + name + Data([UInt8(port >> 8), UInt8(port & 255)])
    }
    private func responseAddress() async throws -> (String, UInt16) {
        let header = try await exact(4)
        guard header[0] == 5, header[1] == 0, header[2] == 0 else {
            throw StrictProxyError(message: "SOCKS request rejected")
        }
        var frame = Data([0, 0, 0, header[3]])
        switch header[3] {
        case 1: frame.append(try await exact(6))
        case 4: frame.append(try await exact(18))
        case 3:
            let length = try await exact(1)
            frame.append(length)
            frame.append(try await exact(Int(length[0]) + 2))
        default: throw StrictProxyError(message: "Invalid SOCKS address type")
        }
        let (host, port, _) = try Self.decodeDatagram(frame)
        return (host, port)
    }
    func connect(host: String, port: UInt16, udp: Bool) async throws {
        let deadline = DispatchWorkItem { [weak self] in self?.close() }
        timeout = deadline
        queue.asyncAfter(deadline: .now() + 15, execute: deadline)
        try await ready(control)
        try await send(Data([5, 1, 2]), on: control)
        guard try await exact(2) == Data([5, 2]) else {
            throw StrictProxyError(message: "Authenticated SOCKS required")
        }
        let user = Data(policy.username.utf8), password = Data(policy.password.utf8)
        try await send(Data([1, UInt8(user.count)]) + user + Data([UInt8(password.count)]) + password, on: control)
        guard try await exact(2) == Data([1, 0]) else { throw StrictProxyError(message: "SOCKS authentication failed") }
        let destination = try Self.address(host: udp ? "0.0.0.0" : host, port: udp ? 0 : port)
        try await send(Data([5, udp ? 3 : 1, 0]) + destination, on: control)
        let (relayHost, relayPort) = try await responseAddress()
        if udp {
            guard ["127.0.0.1", "0.0.0.0", "::1", "::"].contains(relayHost), relayPort != 0 else {
                throw StrictProxyError(message: "Non-loopback UDP relay rejected")
            }
            let relay = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: relayPort)!, using: .udp)
            datagrams = relay
            try await ready(relay)
        }
        timeout?.cancel()
    }
    func finishWrite() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            control.send(content: nil, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed { error in
                if let error = error { c.resume(throwing: error) } else { c.resume() }
            })
        }
    }
    func write(_ data: Data) async throws { try await send(data, on: control) }
    func read() async throws -> Data? {
        try await withCheckedThrowingContinuation { c in
            control.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, done, error in
                if let error = error { c.resume(throwing: error) }
                else if let data = data, !data.isEmpty { c.resume(returning: data) }
                else if done { c.resume(returning: nil) }
                else { c.resume(throwing: StrictProxyError(message: "Empty stream read")) }
            }
        }
    }
    func sendDatagram(_ data: Data, host: String, port: UInt16) async throws {
        guard let relay = datagrams, data.count <= 65000 else { throw StrictProxyError(message: "Invalid UDP payload") }
        let frame = try Data([0, 0, 0]) + Self.address(host: host, port: port) + data
        try await send(frame, on: relay)
    }
    func readDatagram() async throws -> (Data, String, UInt16) {
        guard let relay = datagrams else { throw StrictProxyError(message: "No UDP association") }
        let frame: Data = try await withCheckedThrowingContinuation { c in
            relay.receiveMessage { data, _, _, error in
                if let error = error { c.resume(throwing: error) }
                else if let data = data { c.resume(returning: data) }
                else { c.resume(throwing: StrictProxyError(message: "UDP relay closed")) }
            }
        }
        let (host, port, offset) = try Self.decodeDatagram(frame)
        return (frame.subdata(in: offset..<frame.count), host, port)
    }
    private static func decodeDatagram(_ frame: Data) throws -> (String, UInt16, Int) {
        let bytes = [UInt8](frame)
        guard bytes.count >= 4, bytes[0] == 0, bytes[1] == 0, bytes[2] == 0 else {
            throw StrictProxyError(message: "Fragmented or malformed UDP response")
        }
        var offset = 4
        let host: String
        switch bytes[3] {
        case 1, 4:
            let size = bytes[3] == 1 ? 4 : 16
            guard bytes.count >= offset + size + 2 else { throw StrictProxyError(message: "Truncated UDP address") }
            var address = Array(bytes[offset..<(offset + size)])
            var result = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(bytes[3] == 1 ? AF_INET : AF_INET6, &address, &result, socklen_t(result.count)) != nil else {
                throw StrictProxyError(message: "Invalid UDP address")
            }
            host = String(cString: result)
            offset += size
        case 3:
            guard bytes.count > offset else { throw StrictProxyError(message: "Missing UDP name") }
            let size = Int(bytes[offset]); offset += 1
            guard size > 0, bytes.count >= offset + size + 2,
                  let name = String(bytes: bytes[offset..<(offset + size)], encoding: .utf8) else {
                throw StrictProxyError(message: "Invalid UDP name")
            }
            host = name; offset += size
        default: throw StrictProxyError(message: "Unknown UDP address type")
        }
        let port = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
        return (host, port, offset + 2)
    }
}
