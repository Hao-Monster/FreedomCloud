import Foundation
import NetworkExtension
import Security

/// Both values originate in the kernel-provided flow metadata. A bundle name
/// alone is never sufficient, and an application upgrade requires re-enrollment.
enum StrictApplicationIdentity {
    static func matches(_ policy: StrictApplicationPolicy, metadata: NEFlowMetaData) -> Bool {
        guard metadata.sourceAppSigningIdentifier == policy.signingIdentifier else { return false }
        let hash = metadata.sourceAppUniqueIdentifier.map { String(format: "%02x", $0) }.joined()
        return hash == policy.codeDirectoryHash.lowercased()
    }

    static func inspect(executable: URL) throws -> [String: String] {
        let url = executable.resolvingSymlinksInPath().standardizedFileURL
        var code: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        guard status == errSecSuccess, let code = code else { throw failure(status) }
        status = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil)
        guard status == errSecSuccess else { throw failure(status) }
        var info: CFDictionary?
        status = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        guard status == errSecSuccess, let values = info as? [String: Any],
              let identifier = values[kSecCodeInfoIdentifier as String] as? String,
              let hash = values[kSecCodeInfoUnique as String] as? Data,
              let team = values[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty else {
            throw StrictProxyError(message: "A valid publisher-signed executable is required")
        }
        var requirement: SecRequirement?
        status = SecCodeCopyDesignatedRequirement(code, [], &requirement)
        guard status == errSecSuccess, let requirement = requirement else { throw failure(status) }
        var text: CFString?
        status = SecRequirementCopyString(requirement, [], &text)
        guard status == errSecSuccess, let text = text else { throw failure(status) }
        return ["path": url.path, "signingIdentifier": identifier, "teamIdentifier": team,
                "codeDirectoryHash": hash.map { String(format: "%02x", $0) }.joined(),
                "designatedRequirement": text as String]
    }
    private static func failure(_ status: OSStatus) -> Error {
        StrictProxyError(message: "Signature verification failed (\(status))")
    }
}
