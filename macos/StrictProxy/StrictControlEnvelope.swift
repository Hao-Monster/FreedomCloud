import Foundation
import CryptoKit

/// Provider messages are authenticated with a 256-bit per-install key from the
/// host keychain, delivered through the OS-owned provider configuration. The
/// provider must persist the accepted generation with that configuration.
struct StrictControlEnvelope: Codable {
    let generation: UInt64
    let body: Data
    let authentication: Data

    private static func payload(generation: UInt64, body: Data) -> Data {
        var number = generation.bigEndian
        return withUnsafeBytes(of: &number) { Data($0) } + body
    }
    static func sign(generation: UInt64, body: Data, key: Data) throws -> Data {
        guard key.count == 32, body.count <= 262144, generation > 0 else {
            throw StrictProxyError(message: "Invalid control envelope")
        }
        let tag = HMAC<SHA256>.authenticationCode(for: payload(generation: generation, body: body), using: SymmetricKey(data: key))
        return try JSONEncoder().encode(StrictControlEnvelope(generation: generation, body: body, authentication: Data(tag)))
    }
    static func open(_ message: Data, key: Data, after previousGeneration: UInt64) throws -> StrictControlEnvelope {
        guard key.count == 32, message.count <= 400000 else {
            throw StrictProxyError(message: "Invalid control message size or key")
        }
        let envelope = try JSONDecoder().decode(Self.self, from: message)
        guard envelope.generation > previousGeneration, envelope.body.count <= 262144,
              HMAC<SHA256>.isValidAuthenticationCode(envelope.authentication,
                authenticating: payload(generation: envelope.generation, body: envelope.body),
                using: SymmetricKey(data: key)) else {
            throw StrictProxyError(message: "Unauthenticated or replayed control message")
        }
        return envelope
    }
}
