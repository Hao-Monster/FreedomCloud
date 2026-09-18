// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart';
import 'package:crypto/crypto.dart';

enum Target {
  windows,
  linux,
  android,
  macos,
}

extension TargetExt on Target {
  String get os {
    if (this == Target.macos) {
      return "darwin";
    }
    return name;
  }

  bool get same {
    if (this == Target.android) {
      return true;
    }
    if (Platform.isWindows && this == Target.windows) {
      return true;
    }
    if (Platform.isLinux && this == Target.linux) {
      return true;
    }
    if (Platform.isMacOS && this == Target.macos) {
      return true;
    }
    return false;
  }

  String get dynamicLibExtensionName {
    final String extensionName;
    switch (this) {
      case Target.android || Target.linux:
        extensionName = ".so";
        break;
      case Target.windows:
        extensionName = ".dll";
        break;
      case Target.macos:
        extensionName = ".dylib";
        break;
    }
    return extensionName;
  }

  String get executableExtensionName {
    final String extensionName;
    switch (this) {
      case Target.windows:
        extensionName = ".exe";
        break;
      default:
        extensionName = "";
        break;
    }
    return extensionName;
  }
}

enum Mode { core, lib }

enum Arch { amd64, arm64, arm }

class BuildItem {
  Target target;
  Arch? arch;
  String? archName;

  BuildItem({
    required this.target,
    this.arch,
    this.archName,
  });

  @override
  String toString() =>
      'BuildLibItem{target: $target, arch: $arch, archName: $archName}';
}

class Build {
  static List<BuildItem> get buildItems => [
        BuildItem(
          target: Target.macos,
          arch: Arch.arm64,
        ),
        BuildItem(
          target: Target.macos,
          arch: Arch.amd64,
        ),
        BuildItem(
          target: Target.linux,
          arch: Arch.arm64,
        ),
        BuildItem(
          target: Target.linux,
          arch: Arch.amd64,
        ),
        BuildItem(
          target: Target.windows,
          arch: Arch.amd64,
        ),
        BuildItem(
          target: Target.windows,
          arch: Arch.arm64,
        ),
        BuildItem(
          target: Target.android,
          arch: Arch.arm,
          archName: 'armeabi-v7a',
        ),
        BuildItem(
          target: Target.android,
          arch: Arch.arm64,
          archName: 'arm64-v8a',
        ),
        BuildItem(
          target: Target.android,
          arch: Arch.amd64,
          archName: 'x86_64',
        ),
      ];

  static String get appName => "FlClashX";

  static String get coreName => "FlClashCore";

  static String get libName => "libclash";

  static String get outDir => join(current, libName);

  static String get _coreDir => join(current, "core");

  static String get _servicesDir => join(current, "services", "helper");

  static String get _agentDir => join(current, "services", "agent");

  static String get distPath => join(current, "dist");

  // Full release version for the User-Agent, taken from the CI tag
  // (GITHUB_REF_NAME, e.g. "v0.4.1-pre.18"), baked in via --dart-define=APP_VERSION.
  // Only a version tag counts — a branch name (e.g. "dev") is ignored, so local
  // and branch builds fall back to the pubspec version at runtime.
  static String get appVersion {
    final ref = Platform.environment["GITHUB_REF_NAME"]?.trim() ?? "";
    return RegExp(r'^v\d').hasMatch(ref) ? ref : "";
  }

  /// Resolve the Flutter executable used by all desktop build steps.
  ///
  /// CI normally exposes `flutter` on PATH.  Local Windows checkouts often
  /// have an SDK installed without modifying PATH, so honour an explicit
  /// executable/root first and then check a small set of conventional SDK
  /// locations before falling back to PATH resolution.
  static String get flutterExecutable {
    final environment = Platform.environment;
    final override = environment["FLUTTER_EXECUTABLE"]?.trim();
    if (override != null && override.isNotEmpty) return override;

    final root = environment["FLUTTER_ROOT"]?.trim();
    if (root != null && root.isNotEmpty) {
      final candidate = join(
        root,
        "bin",
        Platform.isWindows ? "flutter.bat" : "flutter",
      );
      if (File(candidate).existsSync()) return candidate;
    }

    if (Platform.isWindows) {
      final candidates = <String>[
        join(
            environment["LOCALAPPDATA"] ?? "", "flutter", "bin", "flutter.bat"),
        join(environment["USERPROFILE"] ?? "", "develop", "flutter", "bin",
            "flutter.bat"),
        r"C:\src\flutter\bin\flutter.bat",
      ];
      for (final candidate in candidates) {
        if (File(candidate).existsSync()) return candidate;
      }
    }

    return Platform.isWindows ? "flutter.bat" : "flutter";
  }

  /// Return the framework version embedded in the SDK, without making a
  /// successful build depend on a particular output format.
  static Future<String> resolveFlutterVersion() async {
    final override = Platform.environment["FLUTTER_VERSION"]?.trim();
    if (override != null && override.isNotEmpty) return override;
    try {
      final result = await Process.run(
        flutterExecutable,
        ["--version", "--machine"],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        try {
          final decoded = jsonDecode(result.stdout.toString());
          if (decoded is Map && decoded["frameworkVersion"] is String) {
            return decoded["frameworkVersion"] as String;
          }
        } catch (_) {
          final match = RegExp(r"Flutter\s+([0-9][^\s]*)")
              .firstMatch(result.stdout.toString());
          if (match != null) return match.group(1)!;
        }
      }
    } catch (_) {
      // Metadata must never turn a completed binary build into a failed one.
    }
    return "unavailable";
  }

  static String _getCc(BuildItem buildItem) {
    final environment = Platform.environment;
    if (buildItem.target == Target.android) {
      final ndk = environment["ANDROID_NDK"];
      assert(ndk != null);
      final prebuiltDir =
          Directory(join(ndk!, "toolchains", "llvm", "prebuilt"));
      final prebuiltDirList = prebuiltDir.listSync();
      final map = {
        "armeabi-v7a": "armv7a-linux-androideabi21-clang",
        "arm64-v8a": "aarch64-linux-android21-clang",
        "x86": "i686-linux-android21-clang",
        "x86_64": "x86_64-linux-android21-clang"
      };
      return join(
        prebuiltDirList.first.path,
        "bin",
        map[buildItem.archName],
      );
    }
    return "gcc";
  }

  static String tagsFor(Target target) =>
      target == Target.android ? "with_gvisor,cmfa" : "with_gvisor";

  static Future<void> exec(
    List<String> executable, {
    String? name,
    Map<String, String>? environment,
    String? workingDirectory,
    bool runInShell = true,
  }) async {
    if (name != null) print("run $name");
    final process = await Process.start(
      executable[0],
      executable.sublist(1),
      environment: environment,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
    );
    process.stdout.listen((data) {
      print(utf8.decode(data, allowMalformed: true));
    });
    process.stderr.listen((data) {
      print(utf8.decode(data, allowMalformed: true));
    });
    final exitCode = await process.exitCode;
    if (exitCode != 0 && name != null) throw "$name error";
  }

  static Future<String> calcSha256(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw "File not exists";
    }
    // Digest chunks as they arrive. Concatenating every chunk with `a + b`
    // repeatedly copied the complete Core and made hashing O(n²): a 47 MiB
    // Windows Core drove the build VM above 1.5 GiB before packaging began.
    return (await sha256.bind(file.openRead()).first).toString();
  }

  static Future<String> resolveSourceCommit() async {
    final environmentCommit = Platform.environment["GITHUB_SHA"]?.trim() ??
        Platform.environment["GIT_COMMIT"]?.trim() ??
        Platform.environment["SOURCE_COMMIT"]?.trim() ??
        "";
    if (RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(environmentCommit)) {
      return environmentCommit.toLowerCase();
    }
    try {
      final result = await Process.run(
        "git",
        ["rev-parse", "HEAD"],
        workingDirectory: current,
        runInShell: false,
      );
      final repositoryCommit = result.stdout.toString().trim();
      if (result.exitCode == 0 &&
          RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(repositoryCommit)) {
        return repositoryCommit.toLowerCase();
      }
    } catch (_) {
      throw "Unable to resolve an immutable source commit for the test package";
    }
    throw "Unable to resolve an immutable source commit for the test package";
  }

  static Future<String> _resolveSourceCommit() => resolveSourceCommit();

  static Future<String> resolveSourceBranch() async {
    final headRef = Platform.environment["GITHUB_HEAD_REF"]?.trim() ?? "";
    if (headRef.isNotEmpty) {
      return headRef;
    }
    final refType = Platform.environment["GITHUB_REF_TYPE"]?.trim() ?? "";
    final refName = Platform.environment["GITHUB_REF_NAME"]?.trim() ?? "";
    if (refType == "branch" && refName.isNotEmpty) {
      return refName;
    }
    if (refType == "tag") {
      return "detached";
    }
    final envBranch = Platform.environment["GIT_BRANCH"]?.trim() ??
        Platform.environment["SOURCE_BRANCH"]?.trim() ??
        "";
    if (envBranch.isNotEmpty) {
      if (envBranch == "HEAD" || envBranch.toLowerCase() == "detached") {
        return "detached";
      }
      return envBranch.replaceFirst(RegExp(r'^refs/heads/'), '');
    }

    try {
      final showCurrent = await Process.run(
        "git",
        ["branch", "--show-current"],
        workingDirectory: current,
        runInShell: false,
      );
      if (showCurrent.exitCode == 0) {
        final branch = showCurrent.stdout.toString().trim();
        if (branch.isNotEmpty) {
          return branch;
        }
        final headVerify = await Process.run(
          "git",
          ["rev-parse", "--verify", "HEAD"],
          workingDirectory: current,
          runInShell: false,
        );
        if (headVerify.exitCode == 0) {
          return "detached";
        }
      } else {
        final abbrevRef = await Process.run(
          "git",
          ["rev-parse", "--abbrev-ref", "HEAD"],
          workingDirectory: current,
          runInShell: false,
        );
        if (abbrevRef.exitCode == 0) {
          final ref = abbrevRef.stdout.toString().trim();
          if (ref == "HEAD") {
            return "detached";
          } else if (ref.isNotEmpty) {
            return ref;
          }
        }
      }
    } catch (_) {
      throw "Unable to resolve source branch or detached state for the test package";
    }
    throw "Unable to resolve source branch or detached state for the test package";
  }

  static Future<String> _resolveSourceBranch() => resolveSourceBranch();

  static Future<String> resolveSourceTreeState() async {
    final rawEnvState = Platform.environment["SOURCE_TREE_STATE"] ??
        Platform.environment["GIT_TREE_STATE"];
    final envState = rawEnvState?.trim().toLowerCase();
    if (envState == "clean" || envState == "dirty" || envState == "unknown") {
      return envState!;
    }

    try {
      final result = await Process.run(
        "git",
        ["status", "--porcelain", "-uall"],
        workingDirectory: current,
        runInShell: false,
      );
      if (result.exitCode != 0) {
        return "unknown";
      }
      final statusOutput = result.stdout.toString().trim();
      return statusOutput.isEmpty ? "clean" : "dirty";
    } catch (_) {
      return "unknown";
    }
  }

  static Future<String> _resolveSourceTreeState() => resolveSourceTreeState();

  static Future<int> resolveSourceDateEpoch(String commit) async {
    final override = Platform.environment["SOURCE_DATE_EPOCH"];
    String raw;
    if (override != null) {
      raw = override;
    } else {
      final result = await Process.run(
        "git", ["show", "-s", "--format=%ct", commit],
        workingDirectory: current, runInShell: false,
      );
      if (result.exitCode != 0) throw "Unable to resolve source commit time";
      raw = result.stdout.toString().trim();
    }
    final epoch = int.tryParse(raw);
    if (!RegExp(r'^\d+$').hasMatch(raw) || epoch == null ||
        epoch < 0 || epoch > 4354819198) {
      throw "SOURCE_DATE_EPOCH must be Unix seconds in the ZIP range (through 2107)";
    }
    return epoch;
  }

  static Future<String> toolVersion(String command, List<String> arguments) async {
    try {
      final result = await Process.run(command, arguments, runInShell: true);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim().replaceAll(RegExp(r'[\r\n]+'), '; ');
      }
    } on ProcessException {
      // Unavailable metadata is explicit; never invent a toolchain identity.
    }
    return "unavailable";
  }

  static Future<String> windowsToolchainIdentity(String buildDir) async {
    final lines = <String>[
      "Go: ${await toolVersion('go', ['version'])}",
      "Rust: ${await toolVersion('rustc', ['--version'])}",
      "Cargo: ${await toolVersion('cargo', ['--version'])}",
      "CMake: ${await toolVersion('cmake', ['--version'])}",
    ];
    final cmakeDir = Directory(join(dirname(dirname(buildDir)), "CMakeFiles"));
    var compilerRecorded = false;
    if (cmakeDir.existsSync()) {
      final compilerFiles = cmakeDir.listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => basename(file.path) == "CMakeCXXCompiler.cmake")
          .toList()..sort((a, b) => a.path.compareTo(b.path));
      for (final file in compilerFiles) {
        final content = await file.readAsString();
        final version = RegExp(r'set\(CMAKE_CXX_COMPILER_VERSION "([^"]+)"\)')
            .firstMatch(content)?.group(1);
        if (version != null) {
          lines.add("MSVC compiler: $version");
          compilerRecorded = true;
        }
      }
    }
    if (!compilerRecorded) lines.add("MSVC compiler: unavailable");
    final project = File(join(dirname(buildDir), "${appName}.vcxproj"));
    final sdk = project.existsSync()
        ? RegExp(r'<WindowsTargetPlatformVersion>([^<]+)</WindowsTargetPlatformVersion>')
            .firstMatch(await project.readAsString())?.group(1)
        : null;
    lines.add("Windows SDK: ${sdk ?? 'unavailable'}");
    lines.add("WDK: ${Platform.environment['FLCLASH_WDK_VERSION'] ?? 'external signed driver input; not invoked'}");
    for (final path in ["pubspec.lock", "core/go.sum", "services/helper/Cargo.lock",
      "services/agent/Cargo.lock", "services/strict-broker/Cargo.lock"]) {
      final file = File(join(current, path));
      lines.add("Input SHA256 $path: ${file.existsSync() ? await calcSha256(file.path) : 'missing'}");
    }
    return lines.join('\n');
  }

  static Future<void> writeArtifactChecksum(String artifact) async {
    await File("$artifact.sha256").writeAsString(
      "${await calcSha256(artifact)}  ${basename(artifact)}\n", flush: true,
    );
  }

  static Future<void> createDeterministicZip({
    required String sourceDirectory,
    required String outputZip,
    required int sourceDateEpoch,
  }) async {
    final helper = join(current, "engineering", "m3-test-package",
        "New-DeterministicZip.ps1");
    if (!File(helper).existsSync()) {
      throw "Deterministic ZIP helper is missing";
    }
    await exec([
      "powershell", "-NoProfile", "-File", helper,
      "-SourceDirectory", sourceDirectory,
      "-OutputZip", outputZip,
      "-SourceDateEpoch", sourceDateEpoch.toString(),
      "-Force",
    ], name: "create deterministic zip", runInShell: false);
  }

  /// Only fixed generated files may be removed; never traverse a directory/link.
  static Future<void> prepareWindowsPackageMode(String buildDir, {required bool strict}) async {
    for (final name in ["FlClashStrictCallout.sys", "FlClashStrictBroker.exe",
      "strict-package-manifest.json"]) {
      final path = join(buildDir, name);
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (strict) {
        if (type != FileSystemEntityType.file) throw "Strict package is missing regular file $name";
      } else if (type == FileSystemEntityType.file) {
        await File(path).delete();
      } else if (type != FileSystemEntityType.notFound) {
        throw "Refusing to remove non-file package artifact $name";
      }
    }
  }

  static Future<void> writeWindowsTestPackageMetadata(
    String buildDir, {
    String? commit,
    String? branch,
    String? treeState,
    DateTime? builtAt,
    String? flutterVersion,
    String toolchain = "unavailable",
    bool strict = false,
    String architecture = "amd64",
  }) async {
    final sourceCommit = commit ?? await resolveSourceCommit();
    if (!RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(sourceCommit)) {
      throw "Invalid source commit for the test package";
    }

    final sourceBranch = branch ?? await resolveSourceBranch();
    if (sourceBranch.trim().isEmpty) {
      throw "Invalid source branch for the test package";
    }

    final rawTreeState = treeState ?? await resolveSourceTreeState();
    final normalizedTreeState = rawTreeState.trim().toLowerCase();
    final String resolvedTreeState;
    if (normalizedTreeState == "clean" ||
        normalizedTreeState == "dirty" ||
        normalizedTreeState == "unknown") {
      resolvedTreeState = normalizedTreeState;
    } else {
      throw "Invalid source tree state for the test package";
    }

    final templateDir = join(current, "engineering", "test-package");
    final buildInfoTemplate = File(join(templateDir, "BUILD-INFO.txt.in"));
    final vmChecklist = File(join(templateDir, "WINDOWS-VM-CHECKLIST.md"));
    final logCollector = File(join(templateDir, "Collect-FlClashXLogs.ps1"));
    if (!buildInfoTemplate.existsSync() ||
        !vmChecklist.existsSync() ||
        !logCollector.existsSync()) {
      throw "Windows test-package metadata is incomplete";
    }

    final workingTreeDescription = switch (resolvedTreeState) {
      "clean" => "clean (source identity verified; binary reproducibility requires matching toolchain and inputs)",
      "dirty" =>
        "dirty (NON-REPRODUCIBLE: build includes uncommitted tracked or untracked changes)",
      _ => "unknown (NON-REPRODUCIBLE: unable to verify git working tree state)",
    };

    final timestamp = builtAt ?? DateTime.fromMillisecondsSinceEpoch(
      (await resolveSourceDateEpoch(sourceCommit)) * 1000, isUtc: true,
    );
    final buildTime = timestamp.toUtc().toIso8601String();
    final buildInfo = (await buildInfoTemplate.readAsString())
        .replaceAll("{{GIT_COMMIT}}", sourceCommit.toLowerCase())
        .replaceAll("{{GIT_BRANCH}}", sourceBranch.trim())
        .replaceAll("{{SOURCE_BRANCH}}", sourceBranch.trim())
        .replaceAll("{{BUILD_TIME_UTC}}", buildTime)
        .replaceAll("{{FLUTTER_VERSION}}", flutterVersion ?? "unavailable")
        .replaceAll("{{TOOLCHAIN}}", toolchain)
        .replaceAll("{{ARCHITECTURE}}", architecture)
        .replaceAll("{{PACKAGE_TYPE}}", strict ? "strict VM qualification package (signed inputs required)" : "unsigned local VM acceptance build")
        .replaceAll("{{STRICT_STATUS}}", strict
            ? "Strict artifact inputs are present. Run New-M3SignedVmBundle.ps1 to validate Authenticode, manifest digests and Broker embedding before qualification."
            : "Strict WFP capture is not enabled by this unsigned package; signed driver/Broker artifacts are not included.")
        .replaceAll("{{WORKING_TREE_STATE}}", workingTreeDescription)
        .replaceAll("{{WORKING_TREE}}", workingTreeDescription)
        .replaceAll("{{SOURCE_TREE_STATE}}", resolvedTreeState)
        .replaceAll("{{TREE_STATE}}", resolvedTreeState);
    if (buildInfo.contains("{{")) {
      throw "Windows test-package metadata contains unresolved placeholders";
    }
    await File(join(buildDir, "BUILD-INFO.txt")).writeAsString(
      buildInfo,
      flush: true,
    );
    await vmChecklist.copy(join(buildDir, "WINDOWS-VM-CHECKLIST.md"));
    await logCollector.copy(join(buildDir, "Collect-FlClashXLogs.ps1"));
  }

  /// Write a sorted, privacy-safe manifest for every file in the portable
  /// package. The manifest deliberately excludes itself to avoid a recursive
  /// hash and uses forward-slash paths so Windows and CI produce the same
  /// verification format.
  static Future<void> writeWindowsPackageChecksums(String buildDir) async {
    final root = Directory(buildDir);
    if (!root.existsSync()) throw "Windows package directory does not exist";
    final files = <File>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is Link) throw "Package checksum inventory cannot contain links";
      if (entity is File && relative(entity.path, from: buildDir) != "SHA256SUMS.txt") {
        files.add(entity);
      }
    }
    files.sort((a, b) => relative(a.path, from: buildDir)
        .replaceAll('\\', '/')
        .compareTo(relative(b.path, from: buildDir)
            .replaceAll('\\', '/')));
    final manifest = StringBuffer();
    for (final file in files) {
      final path = relative(file.path, from: buildDir).replaceAll('\\', '/');
      manifest.writeln("${await calcSha256(file.path)}  $path");
    }
    await File(join(buildDir, "SHA256SUMS.txt"))
        .writeAsString(manifest.toString(), flush: true);
  }

  static void bundleWindowsMsvcRuntime(String buildDir, String winArch) {
    final roots = [
      r'C:\Program Files\Microsoft Visual Studio',
      r'C:\Program Files (x86)\Microsoft Visual Studio',
    ];
    final candidates = <Directory>[];
    for (final root in roots) {
      final directory = Directory(root);
      if (!directory.existsSync()) continue;
      for (final entity
          in directory.listSync(recursive: true, followLinks: false)) {
        if (entity is Directory &&
            entity.path.toLowerCase().contains('\\vc\\redist\\msvc\\') &&
            RegExp(r'\\' + RegExp.escape(winArch) + r'\\microsoft\.vc\d+\.crt$')
                .hasMatch(entity.path.toLowerCase())) {
          candidates.add(entity);
        }
      }
    }
    candidates.sort((a, b) => b.path.compareTo(a.path));
    final source = candidates.cast<Directory?>().firstWhere(
          (directory) => directory!.listSync().any(
                (entity) =>
                    entity is File &&
                    entity.path.toLowerCase().endsWith('\\msvcp140.dll'),
              ),
          orElse: () => null,
        );
    if (source == null) {
      throw '官方 MSVC $winArch 运行库未找到，已停止生成不完整的 Windows 包';
    }
    final runtimeFiles = source.listSync().whereType<File>().where((file) {
      final name = basename(file.path).toLowerCase();
      return name.endsWith('.dll') &&
          (name.startsWith('msvcp140') ||
              name.startsWith('vcruntime140') ||
              name == 'concrt140.dll');
    });
    for (final file in runtimeFiles) {
      File(join(buildDir, basename(file.path)))
          .writeAsBytesSync(file.readAsBytesSync());
    }
    print('✅ Bundled MSVC runtime from ${source.path}');
  }

  /// Reads mihomo version from [core/go.mod] (single source of truth).
  static Future<String> extractCoreVersion() async {
    final goMod = File(join("core", "go.mod"));
    if (!await goMod.exists()) {
      throw "core/go.mod file not found";
    }
    final content = await goMod.readAsString();
    final match =
        RegExp(r'github\.com/metacubex/mihomo\s+(v[\d.]+)').firstMatch(content);
    if (match == null) {
      throw "Could not extract mihomo version from core/go.mod";
    }
    return match.group(1)!;
  }

  /// Writes [lib/core_version.dart] so Flutter can show the same version without dart-define.
  static Future<void> syncCoreVersionDartFile() async {
    final v = await extractCoreVersion();
    final out = File(join(current, "lib", "core_version.dart"));
    await out.writeAsString(
      "// GENERATED by setup.dart from core/constant/version.go — do not edit by hand\n"
      "// ignore_for_file: constant_identifier_names\n"
      "\n"
      "/// Embedded mihomo version (see core/constant/version.go).\n"
      "const String kCoreVersionFromSource = '$v';\n",
    );
  }

  static Future<List<String>> buildCore({
    required Mode mode,
    required Target target,
    required String coreVersion,
    Arch? arch,
  }) async {
    final isLib = mode == Mode.lib;

    final items = buildItems
        .where(
          (element) =>
              element.target == target &&
              (arch == null ? true : element.arch == arch),
        )
        .toList();

    final List<String> corePaths = [];

    final targetOutFilePath = join(outDir, target.name);
    final targetOutFile = File(targetOutFilePath);
    if (await targetOutFile.exists()) {
      await targetOutFile.delete(recursive: true);
      await Directory(targetOutFilePath).create(recursive: true);
    }

    for (final item in items) {
      final outFilePath = join(targetOutFilePath, item.archName);
      final file = File(outFilePath);
      if (file.existsSync()) {
        file.deleteSync(recursive: true);
      }

      final fileName = isLib
          ? "$libName${item.target.dynamicLibExtensionName}"
          : "$coreName${item.target.executableExtensionName}";
      final realOutPath = join(outFilePath, fileName);
      corePaths.add(realOutPath);

      final Map<String, String> env = {};
      env["GOOS"] = item.target.os;
      if (item.arch != null) {
        env["GOARCH"] = item.arch!.name;
      }
      if (isLib) {
        env["CGO_ENABLED"] = "1";
        env["CC"] = _getCc(item);
        env["CFLAGS"] = "-O3 -Werror";
      } else {
        env["CGO_ENABLED"] = "0";
      }

      final execLines = [
        "go",
        "build",
        "-trimpath",
        "-mod=readonly",
        "-ldflags=-w -s -X github.com/metacubex/mihomo/constant.Version=$coreVersion",
        "-tags=${tagsFor(target)}",
        if (isLib) "-buildmode=c-shared",
        "-o",
        realOutPath,
      ];
      await exec(
        execLines,
        name: "build core",
        environment: env,
        workingDirectory: _coreDir,
      );
      if (isLib && item.archName != null) {
        await adjustLibOut(
          targetOutFilePath: targetOutFilePath,
          outFilePath: outFilePath,
          archName: item.archName!,
        );
      }
    }

    return corePaths;
  }

  static Future<void> adjustLibOut({
    required String targetOutFilePath,
    required String outFilePath,
    required String archName,
  }) async {
    final includesPath = join(targetOutFilePath, "includes");
    final realOutPath = join(includesPath, archName);
    await Directory(realOutPath).create(recursive: true);
    final targetOutFiles = Directory(outFilePath).listSync();
    final coreFiles = Directory(_coreDir).listSync();
    for (final file in [...targetOutFiles, ...coreFiles]) {
      if (!file.path.endsWith('.h')) {
        continue;
      }
      final targetFilePath = join(realOutPath, basename(file.path));
      final realFile = File(file.path);
      await realFile.copy(targetFilePath);
      if (coreFiles.contains(file)) {
        continue;
      }
      await realFile.delete();
    }
  }

  static buildHelper(Target target, String token, {Arch? arch}) async {
    final List<String> buildArgs = [
      "cargo",
      "build",
      "--release",
      "--locked",
      "--features",
      "windows-service",
    ];

    // Add target for cross-compilation
    if (arch == Arch.arm64 && target == Target.windows) {
      buildArgs.addAll(["--target", "aarch64-pc-windows-msvc"]);
    }

    await exec(
      buildArgs,
      environment: {
        "TOKEN": token,
      },
      name: "build helper",
      workingDirectory: _servicesDir,
    );

    // Determine output path based on architecture
    final String releasePath;
    if (arch == Arch.arm64 && target == Target.windows) {
      releasePath =
          join(_servicesDir, "target", "aarch64-pc-windows-msvc", "release");
    } else {
      releasePath = join(_servicesDir, "target", "release");
    }

    final outPath = join(
      releasePath,
      "helper${target.executableExtensionName}",
    );
    final targetPath = join(
      outDir,
      target.name,
      "FlClashHelperService${target.executableExtensionName}",
    );
    await File(outPath).copy(targetPath);
  }

  static Future<void> buildAgent(Target target, {Arch? arch}) async {
    final buildArgs = <String>["cargo", "build", "--release", "--locked"];
    if (arch == Arch.arm64 && target == Target.windows) {
      buildArgs.addAll(["--target", "aarch64-pc-windows-msvc"]);
    }
    await exec(
      buildArgs,
      name: "build agent",
      workingDirectory: _agentDir,
    );

    final releasePath = arch == Arch.arm64 && target == Target.windows
        ? join(_agentDir, "target", "aarch64-pc-windows-msvc", "release")
        : join(_agentDir, "target", "release");
    final sourcePath = join(
      releasePath,
      "flclash-agent${target.executableExtensionName}",
    );
    final targetPath = join(
      outDir,
      target.name,
      "FlClashAgent${target.executableExtensionName}",
    );
    await File(sourcePath).copy(targetPath);
  }

  /// Strict mode artifacts are deliberately opt-in.  Release driver signing
  /// and the package manifest are external inputs; a normal desktop build
  /// must never silently ship the old `strict_capture` skeleton or an
  /// unsigned substitute.  Set FLCLASH_STRICT_PACKAGE=1 and provide the
  /// signed driver/manifest paths to assemble the strict package.
  static bool get strictPackageEnabled {
    final value = Platform.environment["FLCLASH_STRICT_PACKAGE"]
        ?.trim()
        .toLowerCase();
    return value == "1" || value == "true" || value == "yes";
  }

  static String _requiredStrictInput(String name) {
    final value = Platform.environment[name]?.trim();
    if (value == null || value.isEmpty) {
      throw "$name is required when FLCLASH_STRICT_PACKAGE is enabled";
    }
    final file = File(value);
    if (FileSystemEntity.typeSync(value, followLinks: false) !=
        FileSystemEntityType.file) {
      throw "$name does not point to a regular file";
    }
    return file.absolute.path;
  }

  /// Build the production-host Broker only when a caller explicitly opts in.
  /// A prebuilt path is preferred because release manifests pin the exact
  /// signed Broker/driver set.  Local compilation remains useful for VM
  /// qualification and embeds the supplied manifest through Cargo.
  static Future<String> buildStrictBroker(Target target, {Arch? arch}) async {
    final prebuilt = Platform.environment["FLCLASH_STRICT_BROKER_PATH"]?.trim();
    if (prebuilt != null && prebuilt.isNotEmpty) {
      final file = File(prebuilt);
      if (FileSystemEntity.typeSync(prebuilt, followLinks: false) !=
          FileSystemEntityType.file) {
        throw "FLCLASH_STRICT_BROKER_PATH does not point to a regular file";
      }
      return file.absolute.path;
    }

    final manifest = _requiredStrictInput("FLCLASH_STRICT_PACKAGE_MANIFEST");
    final args = <String>["cargo", "build", "--release", "--locked", "--features", "production-host"];
    if (target == Target.windows && arch == Arch.arm64) {
      args.addAll(["--target", "aarch64-pc-windows-msvc"]);
    }
    await exec(
      args,
      name: "build strict broker",
      environment: {"FLCLASH_STRICT_PACKAGE_MANIFEST": manifest},
      workingDirectory: join(current, "services", "strict-broker"),
    );
    final releasePath = target == Target.windows && arch == Arch.arm64
        ? join(current, "services", "strict-broker", "target", "aarch64-pc-windows-msvc", "release")
        : join(current, "services", "strict-broker", "target", "release");
    final output = join(releasePath, "FlClashStrictBroker.exe");
    if (!File(output).existsSync()) throw "strict Broker build output is missing";
    return File(output).absolute.path;
  }

  /// Copy signed strict artifacts into the portable root.  The installer
  /// consumes these same root names, while the service entries below place
  /// the Broker/driver/manifest under the protected service directory.
  static Future<void> bundleWindowsStrictArtifacts(
    String buildDir, {
    required String brokerPath,
  }) async {
    if (!strictPackageEnabled) return;
    final driver = _requiredStrictInput("FLCLASH_STRICT_DRIVER_PATH");
    final manifest = _requiredStrictInput("FLCLASH_STRICT_PACKAGE_MANIFEST");
    final files = <String, String>{
      driver: "FlClashStrictCallout.sys",
      brokerPath: "FlClashStrictBroker.exe",
      manifest: "strict-package-manifest.json",
    };
    for (final entry in files.entries) {
      await File(entry.key).copy(join(buildDir, entry.value));
    }
  }

  static List<String> getExecutable(String command) => command.split(" ");

  static String readVersion() {
    final pubspec = File(join(current, "pubspec.yaml")).readAsStringSync();
    final match = RegExp(r'version:\s*(.+)').firstMatch(pubspec);
    return match?.group(1)?.split('+').first ?? "0.0.0";
  }

  static copyFile(String sourceFilePath, String destinationFilePath) {
    final sourceFile = File(sourceFilePath);
    if (!sourceFile.existsSync()) {
      throw "SourceFilePath not exists";
    }
    final destinationFile = File(destinationFilePath);
    final destinationDirectory = destinationFile.parent;
    if (!destinationDirectory.existsSync()) {
      destinationDirectory.createSync(recursive: true);
    }
    try {
      sourceFile.copySync(destinationFilePath);
      print("File copied successfully!");
    } catch (e) {
      print("Failed to copy file: $e");
    }
  }
}

class BuildCommand extends Command {
  Target target;

  BuildCommand({
    required this.target,
  }) {
    if (target == Target.android || target == Target.linux) {
      argParser.addOption(
        "arch",
        valueHelp: arches.map((e) => e.name).join(','),
        help: 'The $name build desc',
      );
    } else {
      argParser.addOption(
        "arch",
        help: 'The $name build archName',
      );
    }
    argParser.addOption(
      "out",
      valueHelp: [
        if (target.same) "app",
        "core",
      ].join(','),
      help: 'The $name build arch',
    );
    argParser.addOption(
      "env",
      valueHelp: [
        "pre",
        "stable",
      ].join(','),
      help: 'The $name build env',
    );
    if (target == Target.windows) {
      argParser.addFlag(
        "msix",
        help: "Build MSIX package for Microsoft Store",
        defaultsTo: false,
      );
    }
  }

  @override
  String get description => "build $name application";

  @override
  String get name => target.name;

  List<Arch> get arches => Build.buildItems
      .where((element) => element.target == target && element.arch != null)
      .map((e) => e.arch!)
      .toList();

  _getLinuxDependencies(Arch arch) async {
    await Build.exec(
      Build.getExecutable("sudo apt update -y"),
    );
    await Build.exec(
      Build.getExecutable("sudo apt install -y ninja-build libgtk-3-dev"),
    );
    await Build.exec(
      Build.getExecutable("sudo apt install -y libayatana-appindicator3-dev"),
    );
    await Build.exec(
      Build.getExecutable("sudo apt-get install -y libkeybinder-3.0-dev"),
    );
    await Build.exec(
      Build.getExecutable("sudo apt install -y locate"),
    );
    if (arch == Arch.amd64) {
      await Build.exec(
        Build.getExecutable("sudo apt install -y rpm patchelf"),
      );
      await Build.exec(
        Build.getExecutable("sudo apt install -y libfuse2"),
      );

      final downloadName = arch == Arch.amd64 ? "x86_64" : "aarch64";
      await Build.exec(
        Build.getExecutable(
          "wget -O appimagetool https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-$downloadName.AppImage",
        ),
      );
      await Build.exec(
        Build.getExecutable(
          "chmod +x appimagetool",
        ),
      );
      await Build.exec(
        Build.getExecutable(
          "sudo mv appimagetool /usr/local/bin/",
        ),
      );
    }
  }

  _getMacosDependencies() async {
    await Build.exec(
      Build.getExecutable("npm install -g create-dmg"),
    );
  }

  _buildMacosApp({
    required Arch arch,
    required String env,
    required String coreVersion,
  }) async {
    await Build.exec(
      name: "flutter build macos",
      [
        Build.flutterExecutable,
        "build",
        "macos",
        "--release",
        "--dart-define=APP_ENV=$env",
        "--dart-define=CORE_VERSION=$coreVersion",
        "--dart-define=APP_VERSION=${Build.appVersion}",
      ],
    );

    final pubspecFile = File(join(current, "pubspec.yaml"));
    final pubspecContent = pubspecFile.readAsStringSync();
    final versionMatch = RegExp(r'version:\s*(.+)').firstMatch(pubspecContent);
    final version = versionMatch?.group(1)?.split('+').first ?? "0.0.0";

    final appName = Build.appName;
    final appPath = join(current, "build", "macos", "Build", "Products",
        "Release", "$appName.app");

    final distDir = Directory(Build.distPath);
    if (!distDir.existsSync()) {
      distDir.createSync(recursive: true);
    }

    print("Creating DMG with create-dmg...");

    await Build.exec(
      name: "create-dmg",
      [
        "create-dmg",
        "--overwrite",
        "--dmg-title",
        appName,
        appPath,
        Build.distPath,
      ],
    );

    final createdDmgName = "$appName $version.dmg";
    final createdDmgPath = join(Build.distPath, createdDmgName);
    final targetDmgName = "$appName-macos-${arch.name}.dmg";
    final targetDmgPath = join(Build.distPath, targetDmgName);

    final createdDmg = File(createdDmgPath);
    if (createdDmg.existsSync()) {
      final targetDmg = File(targetDmgPath);
      if (targetDmg.existsSync()) {
        targetDmg.deleteSync();
      }

      createdDmg.renameSync(targetDmgPath);
      print("✅ DMG created: $targetDmgPath");
    } else {
      throw "DMG file not created: $createdDmgPath";
    }
  }

  _buildWindowsApp({
    required Arch arch,
    required String env,
    required String coreVersion,
    required String token,
    String? strictBrokerPath,
    bool msix = false,
  }) async {
    await Build.exec(
      name: "flutter build windows",
      [
        Build.flutterExecutable,
        "build",
        "windows",
        "--release",
        "--dart-define=APP_ENV=$env",
        "--dart-define=CORE_SHA256=$token",
        "--dart-define=CORE_VERSION=$coreVersion",
        "--dart-define=APP_VERSION=${Build.appVersion}",
      ],
    );

    final winArch = arch == Arch.arm64 ? "arm64" : "x64";
    final buildDir =
        join(current, "build", "windows", winArch, "runner", "Release");
    Build.bundleWindowsMsvcRuntime(buildDir, winArch);
    if (Build.strictPackageEnabled) {
      final broker = strictBrokerPath;
      if (broker == null) throw "strict Broker path was not prepared";
      await Build.bundleWindowsStrictArtifacts(buildDir, brokerPath: broker);
    }
    await Build.prepareWindowsPackageMode(
      buildDir, strict: Build.strictPackageEnabled,
    );
    final commit = await Build.resolveSourceCommit();
    final branch = await Build.resolveSourceBranch();
    final treeState = await Build.resolveSourceTreeState();
    final sourceDateEpoch = await Build.resolveSourceDateEpoch(commit);
    await Build.writeWindowsTestPackageMetadata(
      buildDir,
      commit: commit,
      branch: branch,
      treeState: treeState,
      flutterVersion: await Build.resolveFlutterVersion(),
      builtAt: DateTime.fromMillisecondsSinceEpoch(sourceDateEpoch * 1000,
          isUtc: true),
      toolchain: await Build.windowsToolchainIdentity(buildDir),
      strict: Build.strictPackageEnabled,
      architecture: arch.name,
    );
    await Build.writeWindowsPackageChecksums(buildDir);

    final version = Build.readVersion();
    final distDir = Directory(Build.distPath);
    if (!distDir.existsSync()) distDir.createSync(recursive: true);

    final archName = arch.name;
    final zipName = "${Build.appName}-windows-$archName.zip";
    final zipPath = join(Build.distPath, zipName);
    await Build.createDeterministicZip(
      sourceDirectory: buildDir,
      outputZip: zipPath,
      sourceDateEpoch: sourceDateEpoch,
    );
    print("✅ ZIP created: $zipPath");
    await Build.writeArtifactChecksum(zipPath);
    print("✅ ZIP checksum created: $zipPath.sha256");

    final issTemplate =
        File(join(current, "windows", "packaging", "exe", "inno_setup.iss"));
    if (issTemplate.existsSync()) {
      final issContent = issTemplate
          .readAsStringSync()
          .replaceAll("{{APP_ID}}", "728B3532-C74B-4870-9068-BE70FE12A3E6")
          .replaceAll("{{APP_VERSION}}", version)
          .replaceAll("{{DISPLAY_NAME}}", Build.appName)
          .replaceAll("{{PUBLISHER_NAME}}", "pluralplay")
          .replaceAll(
              "{{PUBLISHER_URL}}", "https://github.com/pluralplay/FlClashX")
          .replaceAll("{{INSTALL_DIR_NAME}}", "{autopf}\\${Build.appName}")
          .replaceAll("{{OUTPUT_BASE_FILENAME}}",
              "${Build.appName}-windows-$archName-setup")
          .replaceAll("{{SETUP_ICON_FILE}}",
              join(current, "windows", "runner", "resources", "app_icon.ico"))
          .replaceAll("{{PRIVILEGES_REQUIRED}}", "admin")
          .replaceAll(
              "{{ARCH}}", archName == "amd64" ? "x64compatible" : "arm64")
          .replaceAll("{{SOURCE_DIR}}", buildDir)
          .replaceAll("{{EXECUTABLE_NAME}}", "${Build.appName}.exe")
          .replaceAll(
            "{{STRICT_PACKAGE_FILES}}",
            Build.strictPackageEnabled
                ? '''Source: "{{SOURCE_DIR}}\\FlClashStrictCallout.sys"; DestDir: "{commonpf}\\FlClashX Service"; Flags: ignoreversion\nSource: "{{SOURCE_DIR}}\\FlClashStrictBroker.exe"; DestDir: "{commonpf}\\FlClashX Service"; Flags: ignoreversion\nSource: "{{SOURCE_DIR}}\\strict-package-manifest.json"; DestDir: "{commonpf}\\FlClashX Service"; Flags: ignoreversion\nSource: "{{SOURCE_DIR}}\\FlClashAgent.exe"; DestDir: "{commonpf}\\FlClashX Service"; Flags: ignoreversion'''
                : "",
          )
          .replaceAll(
            "{{STRICT_SERVICE_BLOCK}}",
            Build.strictPackageEnabled
                ? '''    StrictBrokerExe := ExpandConstant('{commonpf}\\FlClashX Service\\FlClashStrictBroker.exe');
    Exec('sc.exe', 'config "FlClashStrictBroker" binPath= "' + StrictBrokerExe + '" start= auto', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    if ResultCode <> 0 then
      Exec('sc.exe', 'create "FlClashStrictBroker" binPath= "' + StrictBrokerExe + '" start= auto', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    if ResultCode = 0 then
      Exec('sc.exe', 'start "FlClashStrictBroker"', '', SW_HIDE, ewNoWait, ResultCode);'''
                : "",
          )
          .replaceAll(
            "{{STRICT_UNINSTALL_BLOCK}}",
            Build.strictPackageEnabled
                ? '''      Exec('sc.exe', 'stop "FlClashStrictBroker"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      Exec('sc.exe', 'delete "FlClashStrictBroker"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);'''
                : "",
          )
          // The strict file block is injected after the normal source-dir
          // substitution, so expand its intentionally repeated placeholder.
          .replaceAll("{{SOURCE_DIR}}", buildDir);

      var processed = issContent;
      final locales = [
        {"lang": "ru"},
        {"lang": "en"},
      ];
      final langLines = <String>[];
      for (final locale in locales) {
        final lang = locale["lang"]!;
        if (lang == "en")
          langLines
              .add('Name: "english"; MessagesFile: "compiler:Default.isl"');
        if (lang == "ru")
          langLines.add(
              'Name: "russian"; MessagesFile: "compiler:Languages\\Russian.isl"');
      }
      processed = processed.replaceAll(
        RegExp(r'\{% for locale in LOCALES %\}.*?\{% endfor %\}', dotAll: true),
        langLines.join('\n'),
      );
      processed = processed.replaceAllMapped(
        RegExp(
            r"\{%\s*if\s+PRIVILEGES_REQUIRED\s*==\s*'admin'\s*%\}(.*?)\{%\s*endif\s*%\}",
            dotAll: true),
        (m) => m.group(1)!,
      );

      final issOut = File(join(Build.distPath, "setup.iss"));
      issOut.writeAsStringSync(processed);
      final innoCompiler = Platform.environment["INNO_ISCC"] ??
          r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe";
      if (File(innoCompiler).existsSync()) {
        await Build.exec(
          name: "inno setup",
          [innoCompiler, issOut.path],
          runInShell: false,
        );
        final setupPath = join(Build.distPath,
            "${Build.appName}-windows-$archName-setup.exe");
        if (!File(setupPath).existsSync()) {
          throw "Inno Setup completed without creating $setupPath";
        }
        await Build.writeArtifactChecksum(setupPath);
        print("✅ EXE installer created");
      } else {
        print("⚠️  Inno Setup not installed; portable ZIP is still complete");
      }
      issOut.deleteSync();
    }

    if (msix) {
      await Build.exec(
        name: "create msix",
        ["dart", "run", "msix:create"],
      );
      final winArch2 = arch == Arch.arm64 ? "arm64" : "x64";
      final msixDir =
          join(current, "build", "windows", winArch2, "runner", "Release");
      final msixFiles =
          Directory(msixDir).listSync().where((f) => f.path.endsWith(".msix"));
      if (msixFiles.isNotEmpty) {
        final msixOutPath =
            join(Build.distPath, "${Build.appName}-windows-${arch.name}.msix");
        Build.copyFile(msixFiles.first.path, msixOutPath);
        print("✅ MSIX created: $msixOutPath");
      }
    }
  }

  _buildLinuxApp({
    required Arch arch,
    required String env,
    required String coreVersion,
  }) async {
    final targetMap = {
      Arch.arm64: "linux-arm64",
      Arch.amd64: "linux-x64",
    };
    await Build.exec(
      name: "flutter build linux",
      [
        Build.flutterExecutable,
        "build",
        "linux",
        "--release",
        "--target-platform=${targetMap[arch]}",
        "--dart-define=APP_ENV=$env",
        "--dart-define=CORE_VERSION=$coreVersion",
        "--dart-define=APP_VERSION=${Build.appVersion}",
      ],
    );

    final version = Build.readVersion();
    final appName = Build.appName;
    final archName = arch.name;
    final bundleDir = join(current, "build", "linux",
        targetMap[arch]!.replaceAll("linux-", ""), "release", "bundle");
    final distDir = Directory(Build.distPath);
    if (!distDir.existsSync()) distDir.createSync(recursive: true);

    final iconPath = join(current, "assets", "images", "icon.png");
    final debArch = arch == Arch.amd64 ? "amd64" : "arm64";
    final rpmArch = arch == Arch.amd64 ? "x86_64" : "aarch64";

    // --- DEB ---
    final debRoot = join(current, "build", "deb_root");
    final debInstallDir = join(debRoot, "opt", appName);
    final debDesktopDir = join(debRoot, "usr", "share", "applications");
    final debIconDir =
        join(debRoot, "usr", "share", "icons", "hicolor", "256x256", "apps");
    final debControlDir = join(debRoot, "DEBIAN");

    for (final d in [debInstallDir, debDesktopDir, debIconDir, debControlDir]) {
      await Directory(d).create(recursive: true);
    }
    await Build.exec(["cp", "-r", "$bundleDir/.", debInstallDir]);
    File(join(debIconDir, "$appName.png"))
        .writeAsBytesSync(File(iconPath).readAsBytesSync());
    File(join(debDesktopDir, "com.follow.clashx.desktop")).writeAsStringSync(
      "[Desktop Entry]\n"
      "Type=Application\n"
      "Name=$appName\n"
      "GenericName=$appName\n"
      "Comment=$appName\n"
      "Exec=/opt/$appName/$appName\n"
      "Icon=$appName\n"
      "Terminal=false\n"
      "Categories=Network;\n"
      "Keywords=FlClashX;Clash;Proxy;\n"
      "StartupNotify=true\n",
    );
    File(join(debControlDir, "control")).writeAsStringSync(
      "Package: flclashx\n"
      "Version: $version\n"
      "Section: x11\n"
      "Priority: optional\n"
      "Architecture: $debArch\n"
      "Depends: libayatana-appindicator3-dev, libkeybinder-3.0-dev\n"
      "Maintainer: pluralplay <mail@pluralplay.rw>\n"
      "Description: $appName\n",
    );
    final debPath = join(Build.distPath, "$appName-linux-$archName.deb");
    await Build.exec(
        name: "build deb", ["dpkg-deb", "--build", debRoot, debPath]);
    await Directory(debRoot).delete(recursive: true);
    print("✅ DEB created: $debPath");

    // --- RPM (amd64 only) ---
    if (arch == Arch.amd64) {
      final rpmBuildRoot = join(current, "build", "rpm_root");
      final rpmInstallDir = join(rpmBuildRoot, "opt", appName);
      final rpmDesktopDir = join(rpmBuildRoot, "usr", "share", "applications");
      final rpmIconDir = join(
          rpmBuildRoot, "usr", "share", "icons", "hicolor", "256x256", "apps");
      for (final d in [rpmInstallDir, rpmDesktopDir, rpmIconDir]) {
        await Directory(d).create(recursive: true);
      }
      await Build.exec(["cp", "-r", "$bundleDir/.", rpmInstallDir]);
      File(join(rpmIconDir, "$appName.png"))
          .writeAsBytesSync(File(iconPath).readAsBytesSync());
      File(join(rpmDesktopDir, "com.follow.clashx.desktop")).writeAsStringSync(
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=$appName\n"
        "GenericName=$appName\n"
        "Comment=$appName\n"
        "Exec=/opt/$appName/$appName\n"
        "Icon=$appName\n"
        "Terminal=false\n"
        "Categories=Network;\n"
        "Keywords=FlClashX;Clash;Proxy;\n"
        "StartupNotify=true\n",
      );

      final specPath = join(current, "build", "$appName.spec");
      File(specPath).writeAsStringSync(
        "Name: flclashx\n"
        "Version: $version\n"
        "Release: 1\n"
        "Summary: $appName\n"
        "License: Other\n"
        "Group: Applications/Internet\n"
        "Packager: pluralplay <mail@pluralplay.rw>\n"
        "AutoReqProv: no\n"
        "\n"
        "%description\n"
        "$appName proxy client\n"
        "\n"
        "%install\n"
        "cp -r %{_builddir}/root/* %{buildroot}/\n"
        "\n"
        "%files\n"
        "/opt/$appName/*\n"
        "/usr/share/applications/com.follow.clashx.desktop\n"
        "/usr/share/icons/hicolor/256x256/apps/$appName.png\n",
      );

      final rpmBuildDir = join(current, "build", "rpmbuild");
      await Directory(join(rpmBuildDir, "BUILD", "root"))
          .create(recursive: true);
      await Build.exec(
          ["cp", "-r", "$rpmBuildRoot/.", join(rpmBuildDir, "BUILD", "root")]);
      await Build.exec(name: "build rpm", [
        "rpmbuild",
        "-bb",
        specPath,
        "--define",
        "_topdir $rpmBuildDir",
        "--define",
        "_builddir ${join(rpmBuildDir, "BUILD")}",
        "--target",
        rpmArch,
      ]);

      final rpmOutputDir = join(rpmBuildDir, "RPMS", rpmArch);
      final rpmFiles = Directory(rpmOutputDir)
          .listSync()
          .where((f) => f.path.endsWith(".rpm"));
      if (rpmFiles.isNotEmpty) {
        final rpmOutPath = join(Build.distPath, "$appName-linux-$archName.rpm");
        Build.copyFile(rpmFiles.first.path, rpmOutPath);
        print("✅ RPM created: $rpmOutPath");
      }
      await Directory(rpmBuildRoot).delete(recursive: true);
      await Directory(rpmBuildDir).delete(recursive: true);
      File(specPath).deleteSync();
    }

    // --- AppImage (amd64 only) ---
    if (arch == Arch.amd64) {
      final appDir = join(current, "build", "AppDir");
      final appBinDir = join(appDir, "usr", "bin");
      final appLibDir = join(appDir, "usr", "lib");
      final appShareDesktop = join(appDir, "usr", "share", "applications");
      final appShareIcon =
          join(appDir, "usr", "share", "icons", "hicolor", "256x256", "apps");
      for (final d in [appBinDir, appLibDir, appShareDesktop, appShareIcon]) {
        await Directory(d).create(recursive: true);
      }

      final bundleFiles = Directory(bundleDir).listSync();
      for (final f in bundleFiles) {
        final name = basename(f.path);
        if (name == "lib") {
          await Build.exec(["cp", "-r", f.path, appDir + "/usr/"]);
        } else if (f is File) {
          Build.copyFile(f.path, join(appBinDir, name));
        } else {
          await Build.exec(["cp", "-r", f.path, join(appBinDir, name)]);
        }
      }

      // Bundle libkeybinder-3.0.so.0 — a system dependency of the global-hotkey
      // plugin that is NOT part of the Flutter bundle. Without it the AppImage
      // crashes on hosts that lack libkeybinder ("error while loading shared
      // libraries: libkeybinder-3.0.so.0: cannot open shared object file").
      var keybinderSrc = "";
      final ldconfig = await Process.run(
        "bash",
        ["-c", "ldconfig -p | grep -m1 'libkeybinder-3.0.so.0'"],
      );
      final ldOut = ldconfig.stdout.toString().trim();
      if (ldOut.contains("=>")) {
        keybinderSrc = ldOut.split("=>").last.trim();
      }
      if (keybinderSrc.isEmpty || !File(keybinderSrc).existsSync()) {
        keybinderSrc = const [
          "/usr/lib/x86_64-linux-gnu/libkeybinder-3.0.so.0",
          "/usr/lib/libkeybinder-3.0.so.0",
          "/lib/x86_64-linux-gnu/libkeybinder-3.0.so.0",
          "/usr/local/lib/libkeybinder-3.0.so.0",
        ].firstWhere((p) => File(p).existsSync(), orElse: () => "");
      }
      if (keybinderSrc.isNotEmpty) {
        // -L resolves the symlink so the real .so.0 file is copied into the AppDir.
        await Build.exec([
          "cp",
          "-L",
          keybinderSrc,
          join(appLibDir, "libkeybinder-3.0.so.0")
        ]);
        print("✅ bundled libkeybinder from $keybinderSrc");
      } else {
        print(
            "⚠️  libkeybinder-3.0.so.0 not found; AppImage may fail on hosts without it");
      }

      File(join(appShareIcon, "$appName.png"))
          .writeAsBytesSync(File(iconPath).readAsBytesSync());
      Build.copyFile(iconPath, join(appDir, "$appName.png"));
      File(join(appShareDesktop, "com.follow.clashx.desktop"))
          .writeAsStringSync(
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=$appName\n"
        "GenericName=$appName\n"
        "Comment=$appName\n"
        "Exec=$appName\n"
        "Icon=$appName\n"
        "Terminal=false\n"
        "Categories=Network;\n"
        "Keywords=FlClashX;Clash;Proxy;\n"
        "StartupNotify=true\n",
      );
      Build.copyFile(join(appShareDesktop, "com.follow.clashx.desktop"),
          join(appDir, "com.follow.clashx.desktop"));
      File(join(appDir, "AppRun")).writeAsStringSync(
        "#!/bin/bash\n"
        'SELF=\$(readlink -f "\$0")\n'
        'HERE=\${SELF%/*}\n'
        'export PATH="\${HERE}/usr/bin:\${PATH}"\n'
        'export LD_LIBRARY_PATH="\${HERE}/usr/lib:\${LD_LIBRARY_PATH}"\n'
        'exec "\${HERE}/usr/bin/$appName" "\$@"\n',
      );
      await Build.exec(["chmod", "+x", join(appDir, "AppRun")]);
      await Build.exec(["chmod", "+x", join(appBinDir, appName)]);

      final appImagePath =
          join(Build.distPath, "$appName-linux-$archName.AppImage");
      await Build.exec(
        name: "build AppImage",
        ["appimagetool", appDir, appImagePath],
        environment: {"ARCH": "x86_64"},
      );
      await Directory(appDir).delete(recursive: true);
      print("✅ AppImage created: $appImagePath");
    }
  }

  _buildAndroidApp({
    required String env,
    required String coreVersion,
  }) async {
    final distDir = Directory(Build.distPath);
    if (!distDir.existsSync()) distDir.createSync(recursive: true);

    await Build.exec(
      name: "flutter build apk (split)",
      [
        Build.flutterExecutable,
        "build",
        "apk",
        "--release",
        "--split-per-abi",
        "--dart-define=APP_ENV=$env",
        "--dart-define=CORE_VERSION=$coreVersion",
        "--dart-define=APP_VERSION=${Build.appVersion}",
      ],
    );

    final splitDir = join(current, "build", "app", "outputs", "flutter-apk");
    final archMap = {
      "app-arm64-v8a-release.apk": "${Build.appName}-android-arm64-v8a.apk",
      "app-armeabi-v7a-release.apk": "${Build.appName}-android-armeabi-v7a.apk",
      "app-x86_64-release.apk": "${Build.appName}-android-x86_64.apk",
    };
    for (final f in Directory(splitDir).listSync()) {
      final name = basename(f.path);
      if (archMap.containsKey(name)) {
        Build.copyFile(f.path, join(Build.distPath, archMap[name]!));
      }
    }

    await Build.exec(
      name: "flutter build apk (universal)",
      [
        Build.flutterExecutable,
        "build",
        "apk",
        "--release",
        "--dart-define=APP_ENV=$env",
        "--dart-define=CORE_VERSION=$coreVersion",
        "--dart-define=APP_VERSION=${Build.appVersion}",
      ],
    );
    Build.copyFile(
      join(splitDir, "app-release.apk"),
      join(Build.distPath, "${Build.appName}-android-universal.apk"),
    );
    print("✅ APKs created in ${Build.distPath}");
  }

  Future<String?> get systemArch async {
    if (Platform.isWindows) {
      return Platform.environment["PROCESSOR_ARCHITECTURE"];
    } else if (Platform.isLinux || Platform.isMacOS) {
      final result = await Process.run('uname', ['-m']);
      return result.stdout.toString().trim();
    }
    return null;
  }

  @override
  Future<void> run() async {
    final mode = target == Target.android ? Mode.lib : Mode.core;
    final String out = argResults?["out"] ?? (target.same ? "app" : "core");
    final archName = argResults?["arch"];
    final env = argResults?["env"] ?? "pre";
    final currentArches =
        arches.where((element) => element.name == archName).toList();
    final arch = currentArches.isEmpty ? null : currentArches.first;

    if (arch == null && target != Target.android) {
      throw "Invalid arch parameter";
    }

    await Build.syncCoreVersionDartFile();
    final coreVersion = await Build.extractCoreVersion();

    final corePaths = await Build.buildCore(
      target: target,
      arch: arch,
      mode: mode,
      coreVersion: coreVersion,
    );

    if (out != "app") {
      return;
    }

    switch (target) {
      case Target.windows:
        final token = await Build.calcSha256(corePaths.first);
        final buildMsix = argResults?["msix"] == true;
        await Build.buildAgent(target, arch: arch);
        await Build.buildHelper(target, token, arch: arch);
        final strictBrokerPath = Build.strictPackageEnabled
            ? await Build.buildStrictBroker(target, arch: arch)
            : null;
        await _buildWindowsApp(
          arch: arch!,
          env: env,
          coreVersion: coreVersion,
          token: token,
          strictBrokerPath: strictBrokerPath,
          msix: buildMsix,
        );
        return;
      case Target.linux:
        await Build.buildAgent(target, arch: arch);
        await _getLinuxDependencies(arch!);
        await _buildLinuxApp(
          arch: arch!,
          env: env,
          coreVersion: coreVersion,
        );
        return;
      case Target.android:
        await _buildAndroidApp(
          env: env,
          coreVersion: coreVersion,
        );
        return;
      case Target.macos:
        await Build.buildAgent(target, arch: arch);
        await _getMacosDependencies();
        await _buildMacosApp(
          arch: arch!,
          env: env,
          coreVersion: coreVersion,
        );
        return;
    }
  }
}

main(args) async {
  final runner = CommandRunner("setup", "build Application");
  runner.addCommand(BuildCommand(target: Target.android));
  runner.addCommand(BuildCommand(target: Target.linux));
  runner.addCommand(BuildCommand(target: Target.windows));
  runner.addCommand(BuildCommand(target: Target.macos));
  runner.run(args);
}
