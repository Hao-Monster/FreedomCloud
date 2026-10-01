import Foundation
import Network
import Darwin
import CryptoKit
import Security

/// One bounded SOCKS session per intercepted flow; no direct destination socket.
final class StrictSOCKSConnection {
    private let control: NWConnection
    private let queue = DispatchQueue(label: "FreedomCloud.StrictSOCKS")
    private var datagrams: NWConnection?
    private var timeout: DispatchWorkItem?
    private let policy: StrictApplicationPolicy
    private var udpAssociation = Data()
    private var udpKeyID = Data()
    private var udpKey: SymmetricKey?
    private var outboundSequence: UInt64 = 0
    private var inboundHighest: UInt64 = 0
    private var inboundWindow: UInt64 = 0
    private let datagramLock = NSLock()

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
        if udp {
            guard let generation = policy.generation, generation > 0,
                  let relayPort = policy.udpPort, relayPort > 0,
                  let user = Self.credential(policy.username),
                  let password = Self.credential(policy.password) else {
                throw StrictProxyError(message: "Authenticated UDP ingress configuration required")
            }
            var association = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, association.count, &association) == errSecSuccess else {
                throw StrictProxyError(message: "Unable to create UDP association")
            }
            udpAssociation = Data(association)
            udpKeyID = Data(user.prefix(16))
            udpKey = SymmetricKey(data: password)
            let relay = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: relayPort)!, using: .udp)
            datagrams = relay
            try await ready(relay)
            timeout?.cancel()
            return
        }
        try await ready(control)
        try await send(Data([5, 1, 2]), on: control)
        guard try await exact(2) == Data([5, 2]) else {
            throw StrictProxyError(message: "Authenticated SOCKS required")
        }
        let user = Data(policy.username.utf8), password = Data(policy.password.utf8)
        try await send(Data([1, UInt8(user.count)]) + user + Data([UInt8(password.count)]) + password, on: control)
        guard try await exact(2) == Data([1, 0]) else { throw StrictProxyError(message: "SOCKS authentication failed") }
        let destination = try Self.address(host: host, port: port)
        try await send(Data([5, 1, 0]) + destination, on: control)
        _ = try await responseAddress()
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
        guard let relay = datagrams, let key = udpKey, let generation = policy.generation,
              !data.isEmpty, data.count <= 16384, port > 0 else { throw StrictProxyError(message: "Invalid UDP payload") }
        var address = [UInt8](repeating: 0, count: 16)
        let family: UInt8
        let version: UInt8
        let payload: Data
        if inet_pton(AF_INET, host, &address) == 1 { family = 4; version = 1; payload = data }
        else if inet_pton(AF_INET6, host, &address) == 1 { family = 6; version = 1; payload = data }
        else {
            let name = try Self.udpDomain(host)
            family = 3; version = 2
            address = [UInt8](repeating: 0, count: 16)
            payload = Data([UInt8(name.count)]) + name + data
        }
        let sequence = try nextUDPSequence()
        var frame = Data(repeating: 0, count: 80)
        frame.replaceSubrange(0..<4, with: Data("FCXD".utf8))
        frame[4] = version; frame[5] = 1
        Self.put(generation, in: &frame, at: 8, count: 8)
        frame.replaceSubrange(16..<32, with: udpKeyID)
        frame.replaceSubrange(32..<48, with: udpAssociation)
        Self.put(sequence, in: &frame, at: 48, count: 8)
        frame[56] = family
        Self.put(UInt64(port), in: &frame, at: 58, count: 2)
        frame.replaceSubrange(60..<76, with: address)
        Self.put(UInt64(payload.count), in: &frame, at: 76, count: 2)
        frame.append(payload)
        let authentication = HMAC<SHA256>.authenticationCode(for: frame, using: key)
        frame.append(contentsOf: authentication)
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
        guard let key = udpKey, let generation = policy.generation,
              frame.count >= 113, frame.count <= 16496,
              frame.prefix(4) == Data("FCXD".utf8), frame[4] == 1, frame[5] == 2,
              frame[6] == 0, frame[7] == 0, frame[57] == 0, frame[78] == 0, frame[79] == 0,
              Self.number(frame, at: 8, count: 8) == generation,
              frame.subdata(in: 16..<32) == udpKeyID,
              frame.subdata(in: 32..<48) == udpAssociation,
              HMAC<SHA256>.isValidAuthenticationCode(frame.suffix(32), authenticating: frame.dropLast(32), using: key),
              Self.number(frame, at: 76, count: 2) == UInt64(frame.count - 112),
              acceptUDPSequence(Self.number(frame, at: 48, count: 8)) else {
            throw StrictProxyError(message: "UDP ingress authentication or replay check failed")
        }
        let family = frame[56]
        guard family == 4 || family == 6,
              family != 4 || frame.subdata(in: 64..<76).allSatisfy({ $0 == 0 }) else {
            throw StrictProxyError(message: "Invalid authenticated UDP source")
        }
        var address = [UInt8](frame.subdata(in: 60..<(family == 4 ? 64 : 76)))
        var result = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(family == 4 ? AF_INET : AF_INET6, &address, &result, socklen_t(result.count)) != nil else {
            throw StrictProxyError(message: "Invalid UDP source address")
        }
        let port = UInt16(Self.number(frame, at: 58, count: 2))
        guard port > 0 else { throw StrictProxyError(message: "Invalid UDP source port") }
        return (frame.subdata(in: 80..<(frame.count - 32)), String(cString: result), port)
    }
    private static func credential(_ hex: String) -> Data? {
        let bytes = Array(hex.utf8)
        guard bytes.count == 64, bytes.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
        var result = Data()
        for offset in stride(from: 0, to: 64, by: 2) {
            guard let value = UInt8(String(bytes: bytes[offset..<(offset + 2)], encoding: .utf8)!, radix: 16) else { return nil }
            result.append(value)
        }
        return result
    }
    /// IDNA conversion belongs to the managed application/NE endpoint. Never
    /// send Unicode or ask the host OS to resolve a destination outside Core.
    private static func udpDomain(_ host: String) throws -> Data {
        let bytes = Array(host.utf8)
        guard !bytes.isEmpty, bytes.count <= 253 else {
            throw StrictProxyError(message: "UDP DNS name exceeds the supported bound")
        }
        let labels = bytes.split(separator: 46, omittingEmptySubsequences: false)
        var numeric = true
        for label in labels {
            guard !label.isEmpty, label.count <= 63, label.first != 45, label.last != 45 else {
                throw StrictProxyError(message: "Invalid UDP DNS label")
            }
            for byte in label {
                guard (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 else {
                    throw StrictProxyError(message: "UDP DNS name must contain ASCII IDNA labels")
                }
                if !(48...57).contains(byte) { numeric = false }
            }
        }
        guard !numeric else { throw StrictProxyError(message: "Numeric UDP addresses must use IP encoding") }
        return Data(bytes.map { (65...90).contains($0) ? $0 + 32 : $0 })
    }
    private static func put(_ value: UInt64, in data: inout Data, at offset: Int, count: Int) {
        for index in 0..<count { data[offset + index] = UInt8(truncatingIfNeeded: value >> ((count - index - 1) * 8)) }
    }
    private static func number(_ data: Data, at offset: Int, count: Int) -> UInt64 {
        data[offset..<(offset + count)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
    private func nextUDPSequence() throws -> UInt64 {
        datagramLock.lock(); defer { datagramLock.unlock() }
        guard outboundSequence < UInt64.max else { throw StrictProxyError(message: "UDP sequence exhausted") }
        outboundSequence += 1
        return outboundSequence
    }
    private func acceptUDPSequence(_ sequence: UInt64) -> Bool {
        datagramLock.lock(); defer { datagramLock.unlock() }
        guard sequence > 0 else { return false }
        if sequence > inboundHighest {
            let shift = sequence - inboundHighest
            inboundWindow = shift >= 64 ? 1 : (inboundWindow << shift) | 1
            inboundHighest = sequence
            return true
        }
        let offset = inboundHighest - sequence
        guard offset < 64 else { return false }
        let bit = UInt64(1) << offset
        guard inboundWindow & bit == 0 else { return false }
        inboundWindow |= bit
        return true
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
