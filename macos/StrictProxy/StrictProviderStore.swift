import Foundation
import Security

/// Keychain writes replace the authenticated policy and its replay watermark in
/// one operation. No plaintext policy or transport credentials go to defaults.
final class StrictProviderStore {
    private let account: String
    private let keychain: SecKeychain

    init(account: String) throws {
        guard UUID(uuidString: account) != nil else {
            throw StrictProxyError(message: "Invalid provider keychain configuration")
        }
        self.account = account
        var systemKeychain: SecKeychain?
        let result = SecKeychainOpen("/Library/Keychains/System.keychain", &systemKeychain)
        guard result == errSecSuccess, let systemKeychain = systemKeychain else {
            throw StrictProxyError(message: "System keychain unavailable (\(result))")
        }
        keychain = systemKeychain
    }

    func controlKey(bootstrap: Data?) throws -> Data {
        if let bootstrap = bootstrap, bootstrap.count != 32 {
            throw StrictProxyError(message: "Invalid bootstrap key size")
        }
        if let key = try read(service: "com.freedomcloud.strict.control") {
            guard key.count == 32 else {
                throw StrictProxyError(message: "Stored control key is invalid")
            }
            if let bootstrap = bootstrap {
                var difference: UInt8 = 0
                for (old, new) in zip(key, bootstrap) { difference |= old ^ new }
                guard difference == 0 else {
                    throw StrictProxyError(message: "Control key rotation requires explicit new managed account")
                }
            }
            return key
        }
        guard let bootstrap = bootstrap,
              try read(service: "com.freedomcloud.strict.state") == nil else {
            throw StrictProxyError(message: "Provider control key unavailable")
        }
        var item = attributes(service: "com.freedomcloud.strict.control")
        item[kSecUseKeychain as String] = keychain
        item[kSecValueData as String] = bootstrap
        let result = SecItemAdd(item as CFDictionary, nil)
        guard result == errSecSuccess else {
            throw StrictProxyError(message: "Control key persistence failed (\(result))")
        }
        return bootstrap
    }

    func savedEnvelope() throws -> Data? {
        let value = try read(service: "com.freedomcloud.strict.state")
        guard value == nil || value!.count <= 400000 else {
            throw StrictProxyError(message: "Stored policy exceeds limit")
        }
        return value
    }

    func save(envelope: Data) throws {
        guard envelope.count <= 400000 else {
            throw StrictProxyError(message: "Policy exceeds storage limit")
        }
        var query = attributes(service: "com.freedomcloud.strict.state")
        query[kSecMatchSearchList as String] = [keychain]
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        let updates: [String: Any] = [kSecValueData as String: envelope]
        var result = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if result == errSecItemNotFound {
            var item = attributes(service: "com.freedomcloud.strict.state")
            item[kSecUseKeychain as String] = keychain
            item[kSecValueData as String] = envelope
            result = SecItemAdd(item as CFDictionary, nil)
        }
        guard result == errSecSuccess else {
            throw StrictProxyError(message: "Policy persistence failed (\(result))")
        }
    }

    private func attributes(service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private func read(service: String) throws -> Data? {
        var query = attributes(service: service)
        query[kSecMatchSearchList as String] = [keychain]
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let value = result as? Data else {
            throw StrictProxyError(message: "Keychain read failed (\(status))")
        }
        return value
    }
}
