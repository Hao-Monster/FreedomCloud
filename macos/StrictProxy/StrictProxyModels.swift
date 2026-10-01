import Foundation
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
    let generation: UInt64?
    let udpPort: UInt16?

    func validate() throws {
        guard !signingIdentifier.isEmpty, signingIdentifier.utf8.count <= 255,
              codeDirectoryHash.count >= 40, codeDirectoryHash.count <= 64,
              codeDirectoryHash.allSatisfy({ $0.isHexDigit }),
              action == "proxy" || action == "block",
              action == "block" || (port > 0 && (udpPort ?? 0) > 0 && (generation ?? 0) > 0 &&
                username.count == 64 && password.count == 64 &&
                username.allSatisfy({ $0.isASCII && $0.isHexDigit }) &&
                password.allSatisfy({ $0.isASCII && $0.isHexDigit })) else {
            throw StrictProxyError(message: "Invalid exact application policy")
        }
    }
}

struct StrictProxyConfiguration: Codable {
    let generation: UInt64
    let policies: [StrictApplicationPolicy]
    let dnsServers: [String]
    func validate() throws {
        guard generation > 0, policies.count <= 256, dnsServers.count <= 4,
              !policies.contains(where: { $0.action == "proxy" }) || !dnsServers.isEmpty else {
            throw StrictProxyError(message: "Invalid policy generation or identity limit")
        }
        for server in dnsServers {
            var ipv4 = in_addr()
            var ipv6 = in6_addr()
            guard server.utf8.count <= 45,
                  inet_pton(AF_INET, server, &ipv4) == 1 || inet_pton(AF_INET6, server, &ipv6) == 1 else {
                throw StrictProxyError(message: "An explicit DNS server IP address is required")
            }
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

