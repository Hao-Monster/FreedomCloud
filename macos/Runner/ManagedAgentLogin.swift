import Foundation
import Security
import Darwin

/// Explicit user actions only. Registration never stops a detached Agent.
/// launchd may retry after a singleton-lock conflict until the old Agent exits.
enum ManagedAgentLogin {
    private static let operationLock = NSLock()
    private static let corePath = "/Library/Application Support/FlClashX/Core/FlClashCore"
    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    private struct Context {
        let bundle: String
        let label: String
        let agent: String
        let team: String
        var filename: String { label + ".plist" }
        var service: String { "gui/\(getuid())/\(label)" }
    }

    static func install(home: String) -> [String: Any] {
        operationLock.lock(); defer { operationLock.unlock() }
        do {
            let context = try checkedContext()
            let checkedHome = try userDirectory(home)
            let directory = try launchDirectory(create: true)
            defer { close(directory) }
            let previous = try existing(directory, context: context)
            if let previous = previous { try checkOwned(previous, context: context) }
            let configuration = definition(context, home: checkedHome)
            let encoded = try PropertyListSerialization.data(fromPropertyList: configuration, format: .xml, options: 0)
            // Refuse silently replacing a running job or its launch arguments.
            let loaded = try isLoaded(context)
            if loaded {
                guard let previous = previous,
                      let old = try PropertyListSerialization.propertyList(from: previous, options: [], format: nil) as? NSDictionary,
                      old.isEqual(to: configuration) else {
                    throw Failure(message: "A registered Agent is already loaded with different settings. Unregister it explicitly before replacing it.")
                }
                return ["success": true, "registered": true, "loaded": true, "label": context.label]
            }
            try writeOwned(encoded, previous: previous, directory: directory, context: context)
            let location = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/" + context.filename).path
            let result = try launchctl(["bootstrap", "gui/\(getuid())", location])
            guard result == 0 else {
                throw Failure(message: "launchctl bootstrap failed (\(result)); the registered plist was retained for explicit retry or unregister.")
            }
            guard try isLoaded(context) else {
                throw Failure(message: "launchctl returned success but the job is not loaded; registration is not confirmed.")
            }
            return ["success": true, "registered": true, "loaded": true, "label": context.label,
                    "notice": "Registration is not a health check. An existing detached Agent can hold the singleton lock; exit it through the application before launchd can take over."]
        } catch { return ["success": false, "error": error.localizedDescription] }
    }

    static func uninstall() -> [String: Any] {
        operationLock.lock(); defer { operationLock.unlock() }
        do {
            let context = try checkedContext()
            let directory = try launchDirectory(create: false)
            defer { close(directory) }
            guard let previous = try existing(directory, context: context) else {
                if try isLoaded(context) { throw Failure(message: "A job exists without an owned plist; refusing to remove it.") }
                return ["success": true, "registered": false, "loaded": false]
            }
            try checkOwned(previous, context: context)
            if try isLoaded(context) {
                let result = try launchctl(["bootout", context.service])
                guard result == 0 else { throw Failure(message: "launchctl bootout failed (\(result)); registration retained.") }
                guard try !isLoaded(context) else { throw Failure(message: "Agent remains loaded; registration retained.") }
            }
            guard try existing(directory, context: context) == previous else {
                throw Failure(message: "Registration changed concurrently; refusing to remove it.")
            }
            guard unlinkat(directory, context.filename, 0) == 0 else { throw ioFailure("Remove registration") }
            return ["success": true, "registered": false, "loaded": false]
        } catch { return ["success": false, "error": error.localizedDescription] }
    }

    private static func checkedContext() throws -> Context {
        guard getuid() != 0, getuid() == geteuid(), let identifier = Bundle.main.bundleIdentifier,
              identifier.range(of: "^[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)+$", options: .regularExpression) != nil else {
            throw Failure(message: "Login Agent registration requires the signed app in an ordinary user session.")
        }
        let bundle = Bundle.main.bundleURL
        let agent = bundle.appendingPathComponent("Contents/MacOS/FlClashAgent").path
        let team = try signingTeam(bundle)
        guard try signingTeam(URL(fileURLWithPath: agent)) == team else { throw Failure(message: "Agent publisher does not match the app.") }
        for path in ["/Library", "/Library/Application Support", "/Library/Application Support/FlClashX", "/Library/Application Support/FlClashX/Core"] {
            try secureItem(path, owner: 0, directory: true)
        }
        try secureItem(corePath, owner: 0, directory: false)
        guard try signingTeam(URL(fileURLWithPath: corePath)) == team else { throw Failure(message: "Core publisher does not match the app.") }
        return Context(bundle: identifier, label: identifier + ".strict-agent", agent: agent, team: team)
    }

    private static func signingTeam(_ url: URL) throws -> String {
        guard url.path == url.standardizedFileURL.resolvingSymlinksInPath().path else {
            throw Failure(message: "Signed executable path must not contain symbolic links.")
        }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code = code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode), nil) == errSecSuccess else {
            throw Failure(message: "Application, Agent, or Core signature validation failed.")
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any], let team = values[kSecCodeInfoTeamIdentifier as String] as? String,
              team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else {
            throw Failure(message: "A publisher Team signature is required for managed login registration.")
        }
        var requirement: SecRequirement?
        let expression = "anchor apple generic and certificate leaf[subject.OU] = \"" + team + "\""
        guard SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess,
              let requirement = requirement,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else {
            throw Failure(message: "Publisher signature does not satisfy the Apple trust requirement.")
        }
        return team
    }

    private static func secureItem(_ path: String, owner: uid_t, directory: Bool) throws {
        var info = stat()
        guard URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path == path,
              lstat(path, &info) == 0, info.st_uid == owner,
              (info.st_mode & S_IFMT) == (directory ? S_IFDIR : S_IFREG),
              (info.st_mode & 0o022) == 0, (directory || (info.st_mode & 0o111) != 0) else {
            throw Failure(message: "A required directory or executable has unsafe ownership, permissions, or symbolic links.")
        }
    }

    private static func userDirectory(_ path: String) throws -> String {
        let userHome = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.resolvingSymlinksInPath().path
        guard path.hasPrefix(userHome + "/"), path.utf8.count <= 4096,
              !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
            throw Failure(message: "Agent home must be an existing directory inside the current user's home.")
        }
        try secureItem(path, owner: getuid(), directory: true)
        return path
    }

    private static func launchDirectory(create: Bool) throws -> Int32 {
        let userHome = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.resolvingSymlinksInPath().path
        try secureItem(userHome, owner: getuid(), directory: true)
        let library = userHome + "/Library"
        try secureItem(library, owner: getuid(), directory: true)
        let parent = open(library, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { throw ioFailure("Open user Library") }
        defer { close(parent) }
        if create && mkdirat(parent, "LaunchAgents", 0o700) != 0 && errno != EEXIST { throw ioFailure("Create LaunchAgents") }
        let directory = openat(parent, "LaunchAgents", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw ioFailure("Open LaunchAgents") }
        var info = stat()
        guard fstat(directory, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o022 == 0 else {
            close(directory); throw Failure(message: "LaunchAgents ownership or permissions are unsafe.")
        }
        return directory
    }

    private static func definition(_ context: Context, home: String) -> [String: Any] {
        ["Label": context.label, "ProgramArguments": [context.agent, "--home", home, "--core", corePath],
         "RunAtLoad": true, "KeepAlive": ["SuccessfulExit": false], "ThrottleInterval": 30,
         "ProcessType": "Background", "AssociatedBundleIdentifiers": [context.bundle]]
    }

    private static func existing(_ directory: Int32, context: Context) throws -> Data? {
        let descriptor = openat(directory, context.filename, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT { return nil }
            throw ioFailure("Open existing registration")
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o777 == 0o600, info.st_nlink == 1, info.st_size > 0, info.st_size <= 65536 else {
            throw Failure(message: "Existing registration is not a private owned regular file.")
        }
        var bytes = [UInt8](repeating: 0, count: Int(info.st_size))
        var offset = 0
        while offset < bytes.count {
            let count = bytes.withUnsafeMutableBytes { buffer in
                read(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
            }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw ioFailure("Read registration") }
            offset += count
        }
        return Data(bytes)
    }

    private static func checkOwned(_ data: Data, context: Context) throws {
        guard let contents = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let arguments = contents["ProgramArguments"] as? [String], arguments.count == 5,
              arguments[0] == context.agent, arguments[1] == "--home", arguments[3] == "--core", arguments[4] == corePath else {
            throw Failure(message: "Existing plist does not belong to this installed app; refusing to replace or remove it.")
        }
        let home = try userDirectory(arguments[2])
        guard (contents as NSDictionary).isEqual(to: definition(context, home: home)) else {
            throw Failure(message: "Existing registration has unrecognized content; refusing to replace or remove it.")
        }
    }

    private static func writeOwned(_ data: Data, previous: Data?, directory: Int32, context: Context) throws {
        let temporary = "." + context.label + "." + UUID().uuidString
        let descriptor = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw ioFailure("Create private registration") }
        defer { close(descriptor); _ = unlinkat(directory, temporary, 0) }
        var offset = 0
        while offset < data.count {
            let count = data.withUnsafeBytes { buffer in
                write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
            }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw ioFailure("Write registration") }
            offset += count
        }
        guard fchmod(descriptor, 0o600) == 0, fsync(descriptor) == 0 else { throw ioFailure("Flush registration") }
        guard try existing(directory, context: context) == previous else {
            throw Failure(message: "Registration changed concurrently; refusing to replace it.")
        }
        if previous == nil {
            guard linkat(directory, temporary, directory, context.filename, 0) == 0 else { throw ioFailure("Publish registration") }
        } else {
            guard renameat(directory, temporary, directory, context.filename) == 0 else { throw ioFailure("Replace registration") }
        }
    }

    private static func isLoaded(_ context: Context) throws -> Bool {
        let result = try launchctl(["print", context.service])
        if result == 0 { return true }
        // Distinguish a missing service from a missing/denied GUI domain.
        // launchctl uses ESRCH or its bootstrap unknown-service status (113).
        guard result == ESRCH || result == 113,
              try launchctl(["print", "gui/\(getuid())"]) == 0 else {
            throw Failure(message: "Unable to inspect the login job (launchctl \(result)).")
        }
        return false
    }

    private static func launchctl(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        let done = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in done.signal() }
        try process.run()
        if done.wait(timeout: .now() + 15) == .timedOut {
            if process.isRunning { process.terminate() }
            if done.wait(timeout: .now() + 2) == .timedOut, process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
            _ = done.wait(timeout: .now() + 2)
            throw Failure(message: "launchctl timed out; registration state must be inspected before retrying.")
        }
        guard process.terminationReason == .exit else { throw Failure(message: "launchctl was terminated by a signal.") }
        return process.terminationStatus
    }

    private static func ioFailure(_ operation: String) -> Error {
        Failure(message: operation + " failed (errno \(errno)).")
    }
}
