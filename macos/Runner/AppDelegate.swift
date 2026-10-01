import Cocoa
import CryptoKit
import Darwin
import FlutterMacOS
import window_ext
import LaunchAtLogin

@main
class AppDelegate: FlutterAppDelegate {
    var statusBarController: StatusBarController?
    var managedStrictController: ManagedStrictProxyController?
    var zashboardChannel: FlutterMethodChannel?
    var zashboardWindowController: ZashboardWindowController?

    var flutterUIPopover = NSPopover.init()
    
    override init() {
        super.init()
        flutterUIPopover.behavior = NSPopover.Behavior.transient
    }
    
    override func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSLog("AppDelegate: applicationDidFinishLaunching called")
        
        setupCoreInApplicationSupport()
        
        
        guard let mainController = mainFlutterWindow?.contentViewController as? FlutterViewController else {
            NSLog("ERROR: Could not get FlutterViewController from mainFlutterWindow")
            return
        }
        
        
        let popoverContainer = PopoverContainerViewController(flutterViewController: mainController)
        
        flutterUIPopover.contentSize = NSSize(width: 375, height: 600)
        
        flutterUIPopover.contentViewController = popoverContainer
        
        statusBarController = StatusBarController.init(flutterUIPopover)
        
        managedStrictController = ManagedStrictProxyController(messenger: mainController.engine.binaryMessenger)
        setupStatusBarChannel(flutterViewController: mainController)
        setupZashboardChannel(flutterViewController: mainController)

        super.applicationDidFinishLaunching(aNotification)
        
        mainFlutterWindow?.close()
    }
    
    func setupStatusBarChannel(flutterViewController: FlutterViewController) {
        let channel = FlutterMethodChannel(
            name: "status_bar_icon",
            binaryMessenger: flutterViewController.engine.binaryMessenger
        )
        
        statusBarController?.menuChannel = channel
        channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            switch call.method {
            case "updateIcon":
                if let args = call.arguments as? [String: Any],
                   let isConnected = args["isConnected"] as? Bool {
                    self?.statusBarController?.updateIcon(isVpnConnected: isConnected)
                    result(true)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
                }
            case "updateMenu":
                guard let args = call.arguments as? [String: Any] else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Menu required", details: nil))
                    return
                }
                self?.statusBarController?.updateMenu(args)
                result(nil)
            case "updateRates":
                self?.statusBarController?.updateRates(call.arguments as? String ?? "")
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        
        NSLog("StatusBar channel set up successfully")
    }

    func setupZashboardChannel(flutterViewController: FlutterViewController) {
        let channel = FlutterMethodChannel(
            name: "zashboard_window",
            binaryMessenger: flutterViewController.engine.binaryMessenger
        )
        zashboardChannel = channel

        channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            guard let self = self else { result(nil); return }
            switch call.method {
            case "open":
                guard let args = call.arguments as? [String: Any],
                      let url = args["url"] as? String else {
                    result(FlutterError(code: "INVALID_ARGS", message: "url required", details: nil))
                    return
                }
                if self.zashboardWindowController == nil {
                    self.zashboardWindowController = ZashboardWindowController(onClosed: { [weak self] in
                        self?.zashboardChannel?.invokeMethod("onClosed", arguments: nil)
                    })
                }
                self.zashboardWindowController?.show(urlString: url)
                result(true)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        NSLog("Zashboard channel set up successfully")
    }

    private func coreDigest(_ path: String) throws -> String {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = handle.readData(ofLength: 65536)
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func signingCommand(_ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "FlClashX.Core", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "Signed application/core verification failed"])
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func shellQuote(_ value: String) -> String {
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func setupCoreInApplicationSupport() {
        let bundle = Bundle.main.bundleURL.path
        let source = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/FlClashCore").path
        let destination = "/Library/Application Support/FlClashX/Core/FlClashCore"
        do {
            _ = try signingCommand(["--verify", "--deep", "--strict", bundle])
            let identity = try signingCommand(["-dv", "--verbose=4", bundle])
            let lines = identity.components(separatedBy: "\n")
            let team = lines.first(where: { $0.hasPrefix("TeamIdentifier=") })
                .map { String($0.dropFirst("TeamIdentifier=".count)) } ?? ""
            let hasTeam = team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil
            let localDevelopment = !hasTeam && lines.contains("Signature=adhoc")
            let requirement: String?
            if hasTeam {
                let releaseRequirement = "anchor apple generic and certificate leaf[subject.OU] = \"" + team + "\""
                requirement = releaseRequirement
                _ = try signingCommand(["--verify", "--strict", "-R", releaseRequirement, source])
            } else if localDevelopment {
                // Ad-hoc signatures establish local bundle integrity, not a
                // trusted publisher. Only explicit local administrator consent
                // can authorize this exact development Core for privileged use.
                _ = try signingCommand(["--verify", "--strict", source])
                let coreIdentity = try signingCommand(["-dv", "--verbose=4", source])
                guard coreIdentity.components(separatedBy: "\n").contains("Signature=adhoc") else {
                    throw NSError(domain: "FlClashX.Core", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "Local development requires valid ad-hoc signatures on both the app and Core"])
                }
                requirement = nil
            } else {
                throw NSError(domain: "FlClashX.Core", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Application must have a valid team signature or an explicit ad-hoc development signature"])
            }
            let expected = try coreDigest(source)
            let protectedDirectories = ["/Library/Application Support/FlClashX", "/Library/Application Support/FlClashX/Core"]
            let protectedPath = protectedDirectories.allSatisfy { path in
                guard URL(fileURLWithPath: path).resolvingSymlinksInPath().path == path,
                      let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                      let owner = attrs[.ownerAccountID] as? NSNumber,
                      let mode = attrs[.posixPermissions] as? NSNumber else { return false }
                return owner.intValue == 0 && mode.intValue == 0o755
            }
            if protectedPath, URL(fileURLWithPath: destination).resolvingSymlinksInPath().path == destination,
               let current = try? coreDigest(destination), current == expected,
               let attributes = try? FileManager.default.attributesOfItem(atPath: destination),
               let owner = attributes[.ownerAccountID] as? NSNumber,
               let permissions = attributes[.posixPermissions] as? NSNumber,
               owner.intValue == 0, permissions.intValue == 0o4755 {
                return
            }
            if localDevelopment {
                let consent = NSAlert()
                consent.messageText = "Authorize local development network core"
                consent.informativeText = "This is a local ad-hoc development build, not a trusted publisher release. Installing this exact Core grants it administrator capabilities. SHA-256: " + expected
                consent.addButton(withTitle: "Install local development Core")
                consent.addButton(withTitle: "Quit")
                guard consent.runModal() == .alertFirstButtonReturn else { Darwin.exit(EXIT_FAILURE) }
            }
            let stagedVerification: String
            if let requirement = requirement {
                stagedVerification = "/usr/bin/codesign --verify --strict -R " + shellQuote(requirement) + " \"$staged/FlClashCore\""
            } else {
                stagedVerification = "/usr/bin/codesign --verify --strict \"$staged/FlClashCore\"\n/usr/bin/codesign -dv --verbose=4 \"$staged/FlClashCore\" 2>&1 | /usr/bin/grep -Fx 'Signature=adhoc' >/dev/null"
            }
            // Only the immutable executable moves. Credentials, subscriptions,
            // Agent tokens and profiles keep their existing per-user paths.
            let command = """
            set -eu
            for d in '/Library' '/Library/Application Support'; do
              test ! -L "$d"
              test "$(/usr/bin/stat -f %u "$d")" = 0
            done
            base='/Library/Application Support/FlClashX'
            for d in "$base" "$base/Core"; do
              if test -e "$d"; then
                test ! -L "$d"
                test "$(/usr/bin/stat -f %u "$d")" = 0
              else
                /bin/mkdir -m 755 "$d"
              fi
              /bin/chmod 755 "$d"
            done
            test ! -L "$base/Core/FlClashCore"
            staged=$(/usr/bin/mktemp -d "$base/Core/.update.XXXXXX")
            trap '/bin/rm -f "$staged/FlClashCore"; /bin/rmdir "$staged"' EXIT
            /bin/cp \(shellQuote(source)) "$staged/FlClashCore"
            test "$(/usr/bin/shasum -a 256 "$staged/FlClashCore" | /usr/bin/cut -d ' ' -f 1)" = \(shellQuote(expected))
            \(stagedVerification)
            /usr/sbin/chown root:wheel "$staged/FlClashCore"
            /bin/chmod 4755 "$staged/FlClashCore"
            /bin/mv -f "$staged/FlClashCore" "$base/Core/FlClashCore"
            """
            let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            var error: NSDictionary?
            let authorizationPrompt = localDevelopment ? "Install this local development Core; publisher trust is not verified." : "Install the verified FlClashX network core."
            guard let script = NSAppleScript(source: "do shell script \"" + escaped + "\" with administrator privileges with prompt \"" + authorizationPrompt + "\"") else {
                throw NSError(domain: "FlClashX.Core", code: 3)
            }
            script.executeAndReturnError(&error)
            if let error = error { throw NSError(domain: "FlClashX.Core", code: 4, userInfo: error as? [String: Any]) }
            guard try coreDigest(destination) == expected else { throw NSError(domain: "FlClashX.Core", code: 5) }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Verified network core could not be installed"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            // Startup must not proceed with an unverified or stale privileged
            // executable. Flutter's window delegate can cancel terminate().
            Darwin.exit(EXIT_FAILURE)
        }
    }

    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        WindowExtPlugin.instance?.handleShouldTerminate()
        return .terminateCancel
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
      return true
    }
    
    override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let controller = statusBarController {
            if !flutterUIPopover.isShown {
                controller.showPopover(self)
            }
        }
        return true
    }
}
