import 'dart:io';

import "package:path/path.dart";

import 'proxy_platform_interface.dart';

enum ProxyTypes { http, https, socks }

class Proxy extends ProxyPlatform {
  static String url = "127.0.0.1";

  @override
  Future<bool?> startPac(String address) async {
    final uri = Uri.tryParse(address);
    if (uri == null || !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty || uri.userInfo.isNotEmpty || address.length > 2048 ||
        address.contains(RegExp(r'[\x00-\x20]'))) {
      throw ArgumentError('Invalid PAC URL');
    }
    if (Platform.isWindows) return ProxyPlatform.instance.startPac(address);
    if (Platform.isMacOS) {
      final devices = await _getNetworkDeviceListWithMacos();
      if (devices.isEmpty) return false;
      for (final device in devices) {
        for (final args in [
          ['-setautoproxyurl', device, address],
          ['-setwebproxystate', device, 'off'],
          ['-setsecurewebproxystate', device, 'off'],
          ['-setsocksfirewallproxystate', device, 'off'],
          ['-setautoproxystate', device, 'on'],
        ]) {
          final result = await Process.run('/usr/sbin/networksetup', args);
          if (result.exitCode != 0) return false;
        }
      }
      return true;
    }
    if (Platform.isLinux) {
      final kde = Platform.environment['XDG_CURRENT_DESKTOP']?.contains('KDE') == true;
      final commands = kde
          ? [
              ['kwriteconfig5', '--file', 'kioslaverc', '--group', 'Proxy Settings', '--key', 'Proxy Config Script', address],
              ['kwriteconfig5', '--file', 'kioslaverc', '--group', 'Proxy Settings', '--key', 'ProxyType', '2'],
            ]
          : [
              ['gsettings', 'set', 'org.gnome.system.proxy', 'autoconfig-url', address],
              ['gsettings', 'set', 'org.gnome.system.proxy', 'mode', 'auto'],
            ];
      for (final command in commands) {
        final result = await Process.run(command.first, command.sublist(1));
        if (result.exitCode != 0) return false;
      }
      return true;
    }
    return false;
  }

  @override
  Future<bool?> startProxy(
    int port, [
    List<String> bypassDomain = const [],
  ]) async {
    return switch (Platform.operatingSystem) {
      "macos" => await _startProxyWithMacos(port, bypassDomain),
      "linux" => await _startProxyWithLinux(port, bypassDomain),
      "windows" => await ProxyPlatform.instance.startProxy(port, bypassDomain),
      String() => false,
    };
  }

  @override
  Future<bool?> stopProxy() async {
    return switch (Platform.operatingSystem) {
      "macos" => await _stopProxyWithMacos(),
      "linux" => await _stopProxyWithLinux(),
      "windows" => await ProxyPlatform.instance.stopProxy(),
      String() => false,
    };
  }

  Future<bool> _startProxyWithLinux(int port, List<String> bypassDomain) async {
    try {
      final homeDir = Platform.environment['HOME']!;
      final configDir = join(homeDir, ".config");
      final cmdList = List<List<String>>.empty(growable: true);
      final desktop = Platform.environment['XDG_CURRENT_DESKTOP'];
      final isKDE = desktop == "KDE";
      if (isKDE) {
        cmdList.add(
          [
            "kwriteconfig5",
            "--file",
            "$configDir/kioslaverc",
            "--group",
            "Proxy Settings",
            "--key",
            "ProxyType",
            "1"
          ],
        );
        cmdList.add(
          [
            "kwriteconfig5",
            "--file",
            "$configDir/kioslaverc",
            "--group",
            "Proxy Settings",
            "--key",
            "NoProxyFor",
            bypassDomain.join(",")
          ],
        );
      } else {
        cmdList.add(
          ["gsettings", "set", "org.gnome.system.proxy", "mode", "manual"],
        );
        final ignoreHosts = "\"['${bypassDomain.join("', '")}']\"";
        cmdList.add(
          [
            "gsettings",
            "set",
            "org.gnome.system.proxy",
            "ignore-hosts",
            ignoreHosts
          ],
        );
      }
      for (final type in ProxyTypes.values) {
        if (!isKDE) {
          cmdList.add(
            [
              "gsettings",
              "set",
              "org.gnome.system.proxy.${type.name}",
              "host",
              url
            ],
          );
          cmdList.add(
            [
              "gsettings",
              "set",
              "org.gnome.system.proxy.${type.name}",
              "port",
              "$port"
            ],
          );
          cmdList.add(
            [
              "gsettings",
              "set",
              "org.gnome.system.proxy.${type.name}",
              "port",
              "$port"
            ],
          );
          cmdList.add(
            [
              "gsettings",
              "set",
              "org.gnome.system.proxy.${type.name}",
              "port",
              "$port"
            ],
          );
        }
        if (isKDE) {
          cmdList.add(
            [
              "kwriteconfig5",
              "--file",
              "$configDir/kioslaverc",
              "--group",
              "Proxy Settings",
              "--key",
              "${type.name}Proxy",
              "${type.name}://$url:$port"
            ],
          );
        }
      }
      for (final cmd in cmdList) {
        await Process.run(cmd[0], cmd.sublist(1), runInShell: true);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _stopProxyWithLinux() async {
    try {
      final homeDir = Platform.environment['HOME']!;
      final configDir = join(homeDir, ".config/");
      final cmdList = List<List<String>>.empty(growable: true);
      final desktop = Platform.environment['XDG_CURRENT_DESKTOP'];
      final isKDE = desktop == "KDE";
      if (isKDE) {
        cmdList.add(
          [
            "kwriteconfig5",
            "--file",
            "$configDir/kioslaverc",
            "--group",
            "Proxy Settings",
            "--key",
            "ProxyType",
            "0"
          ],
        );
      } else {
        cmdList.add(
          ["gsettings", "set", "org.gnome.system.proxy", "mode", "none"],
        );
      }
      for (final cmd in cmdList) {
        await Process.run(cmd[0], cmd.sublist(1));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _startProxyWithMacos(int port, List<String> bypassDomain) async {
    try {
      final devices = await _getNetworkDeviceListWithMacos();
      for (final dev in devices) {
        final pacOff = await Process.run('/usr/sbin/networksetup',
            ['-setautoproxystate', dev, 'off']);
        if (pacOff.exitCode != 0) return false;
        await Future.wait([
          Process.run(
            "/usr/sbin/networksetup",
            ["-setwebproxystate", dev, "on"],
          ),
          Process.run(
            "/usr/sbin/networksetup",
            ["-setwebproxy", dev, url, "$port"],
          ),
          Process.run(
            "/usr/sbin/networksetup",
            ["-setsecurewebproxystate", dev, "on"],
          ),
          Process.run(
            "/usr/sbin/networksetup",
            ["-setsecurewebproxy", dev, url, "$port"],
          ),
          Process.run(
            "/usr/sbin/networksetup",
            ["-setsocksfirewallproxystate", dev, "on"],
          ),
          Process.run(
            "/usr/sbin/networksetup",
            ["-setsocksfirewallproxy", dev, url, "$port"],
          ),
          Process.run(
            "/usr/sbin/networksetup",
            [
              "-setproxybypassdomains",
              dev,
              bypassDomain.join(","),
            ],
          ),
        ]);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _stopProxyWithMacos() async {
    try {
      final devices = await _getNetworkDeviceListWithMacos();
      for (final dev in devices) {
        await Future.wait([
          Process.run(
            "/usr/sbin/networksetup",
            ["-setautoproxystate", dev, "off"],
          ),
          Process.run(
            "/usr/sbin/networksetup",
            ["-setwebproxystate", dev, "off"],
          ),
          Process.run(
            "/usr/sbin/networksetup",
            ["-setsecurewebproxystate", dev, "off"],
          ),
          Process.run(
            "/usr/sbin/networksetup",
            ["-setsocksfirewallproxystate", dev, "off"],
          ),
          Process.run(
            "/usr/sbin/networksetup",
            ["-setproxybypassdomains", dev, ""],
          ),
        ]);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<List<String>> _getNetworkDeviceListWithMacos() async {
    final res = await Process.run(
        "/usr/sbin/networksetup", ["-listallnetworkservices"]);
    if (res.exitCode != 0) throw StateError('Cannot enumerate network services');
    return res.stdout.toString().split('\n').skip(1).map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('*')).toList();
  }
}
