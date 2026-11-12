import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flclashx/clash/clash.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/manager/hotkey_manager.dart';
import 'package:flclashx/manager/manager.dart';
import 'package:flclashx/plugins/app.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'controller.dart';
import 'pages/pages.dart';

// Windows reports internet-connected adapter types. Adapter notifications can
// omit the TUN even while existing Core connections are still healthy.
bool shouldCloseConnectionsOnNetworkChange(
  List<ConnectivityResult> results, {
  required bool isWindows,
}) =>
    !isWindows && !results.contains(ConnectivityResult.vpn);

class NetworkChangeCoordinator {
  NetworkChangeCoordinator({
    required this.isWindows,
    required this.readLocalIp,
    required this.resetConnections,
    required this.closeConnections,
    this.onLocalIpChanged,
    this.probeDelays = const [
      Duration(milliseconds: 250),
      Duration(milliseconds: 1200),
      Duration(milliseconds: 2800),
    ],
  });

  final bool isWindows;
  final Future<String?> Function() readLocalIp;
  final VoidCallback resetConnections;
  final VoidCallback closeConnections;
  final ValueChanged<String?>? onLocalIpChanged;
  final List<Duration> probeDelays;

  bool _disposed = false;
  int _epoch = 0;
  bool _hasSnapshot = false;
  bool _wasOffline = false;
  Set<ConnectivityResult> _lastTransports = const <ConnectivityResult>{};
  String _lastLocalIp = '';

  Set<ConnectivityResult> _extractPhysicalTransports(
    List<ConnectivityResult> results,
  ) =>
      results
          .where(
            (result) =>
                result != ConnectivityResult.vpn &&
                result != ConnectivityResult.none,
          )
          .toSet();

  Future<void> seedInitialBaseline(List<ConnectivityResult> results) async {
    if (_disposed || !isWindows || _hasSnapshot || _epoch != 0) {
      return;
    }
    final seedEpoch = _epoch;
    final transports = _extractPhysicalTransports(results);
    if (transports.isEmpty) {
      _hasSnapshot = true;
      _wasOffline = true;
      _lastTransports = const <ConnectivityResult>{};
      return;
    }
    final rawIp = await readLocalIp();
    if (_disposed || _hasSnapshot || _epoch != seedEpoch) {
      return;
    }
    final ip = (rawIp ?? '').trim();
    _lastTransports = transports;
    _lastLocalIp = ip;
    _hasSnapshot = true;
    _wasOffline = false;
    if (ip.isNotEmpty) {
      onLocalIpChanged?.call(rawIp);
    }
  }

  Future<void> handleConnectivityChanged(
    List<ConnectivityResult> results,
  ) async {
    if (_disposed) {
      return;
    }
    final epoch = ++_epoch;
    final delays = probeDelays.isEmpty ? const [Duration.zero] : probeDelays;

    if (!isWindows) {
      if (shouldCloseConnectionsOnNetworkChange(results, isWindows: false)) {
        resetConnections();
        closeConnections();
      }
      final delay = delays.first;
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      if (_disposed || epoch != _epoch) {
        return;
      }
      final ip = await readLocalIp();
      if (_disposed || epoch != _epoch) {
        return;
      }
      onLocalIpChanged?.call(ip);
      return;
    }

    final transports = _extractPhysicalTransports(results);

    if (transports.isEmpty) {
      _hasSnapshot = true;
      _wasOffline = true;
      _lastTransports = const <ConnectivityResult>{};
      final delay = delays.first;
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      if (_disposed || epoch != _epoch) {
        return;
      }
      final ip = await readLocalIp();
      if (_disposed || epoch != _epoch) {
        return;
      }
      onLocalIpChanged?.call(ip);
      return;
    }

    for (var i = 0; i < delays.length; i++) {
      final delay = delays[i];
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      if (_disposed || epoch != _epoch) {
        return;
      }
      final rawIp = await readLocalIp();
      if (_disposed || epoch != _epoch) {
        return;
      }
      onLocalIpChanged?.call(rawIp);
      final ip = (rawIp ?? '').trim();
      final isLastProbe = i == delays.length - 1;

      if (!_hasSnapshot) {
        _lastTransports = transports;
        if (ip.isNotEmpty || isLastProbe) {
          _lastLocalIp = ip;
          _hasSnapshot = true;
          _wasOffline = false;
          break;
        }
        continue;
      }

      final transportChanged = !setEquals(_lastTransports, transports);
      final ipChanged = ip.isNotEmpty && ip != _lastLocalIp;
      final shouldReset = _wasOffline || transportChanged || ipChanged;

      if (shouldReset) {
        if (ip.isNotEmpty || isLastProbe) {
          resetConnections();
          _wasOffline = false;
          _lastTransports = transports;
          if (ip.isNotEmpty) {
            _lastLocalIp = ip;
          }
          break;
        }
        continue;
      }

      if (ip.isNotEmpty) {
        _lastTransports = transports;
        break;
      }
    }
  }

  void dispose() {
    _disposed = true;
    _epoch++;
  }
}

class Application extends ConsumerStatefulWidget {
  const Application({
    super.key,
  });

  @override
  ConsumerState<Application> createState() => ApplicationState();
}

class ApplicationState extends ConsumerState<Application> {
  Timer? _autoUpdateProfilesTaskTimer;
  late final NetworkChangeCoordinator _networkChangeCoordinator;

  final _pageTransitionsTheme = const PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: CommonPageTransitionsBuilder(),
      TargetPlatform.windows: CommonPageTransitionsBuilder(),
      TargetPlatform.linux: CommonPageTransitionsBuilder(),
      TargetPlatform.macOS: CommonPageTransitionsBuilder(),
    },
  );

  @override
  void initState() {
    super.initState();

    if (Platform.isWindows) {
      windows?.enableDarkModeForApp();
    }

    if (Platform.isAndroid) {
      // Pin the highest refresh rate (per session) so the Flutter engine samples
      // 120 Hz at surface creation. A hand-rolled preferredDisplayModeId left LTPO
      // Pixel panels showing 120 Hz while the engine rendered at 60 (visible jank);
      // flutter_displaymode handles the OEM quirks. Best-effort, never fatal.
      unawaited(FlutterDisplayMode.setHighRefreshRate().catchError((_) {}));
    }

    globalState.startGroupsUpdateTask();
    _autoUpdateProfilesTask();
    globalState.appController = AppController(context, ref);
    _networkChangeCoordinator = NetworkChangeCoordinator(
      isWindows: Platform.isWindows,
      readLocalIp: utils.getLocalIpAddress,
      resetConnections: clashCore.resetConnections,
      closeConnections: clashCore.closeConnections,
      onLocalIpChanged: (ip) {
        if (mounted) {
          ref.read(localIpProvider.notifier).value = ip;
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      logStartupFirstFrameOnce();
      final currentContext = globalState.navigatorKey.currentContext;
      if (currentContext != null) {
        globalState.appController.updateContext(currentContext);
      }
      await globalState.appController.init();
      globalState.appController.initLink();
      app?.initShortcuts();
    });
  }

  void _autoUpdateProfilesTask() {
    _autoUpdateProfilesTaskTimer = Timer(const Duration(minutes: 20), () async {
      await globalState.appController.autoUpdateProfiles();
      // dispose() may have landed during the await; don't arm a fresh
      // post-dispose timer that would keep firing.
      if (!mounted) return;
      _autoUpdateProfilesTask();
    });
  }

  Widget _buildPlatformState(Widget child) {
    if (system.isDesktop) {
      return WindowManager(
        child: TrayManager(
          child: HotKeyManager(
            child: ProxyManager(
              child: child,
            ),
          ),
        ),
      );
    }
    return AndroidManager(
      child: TileManager(
        child: child,
      ),
    );
  }

  Widget _buildState(Widget child) => AppStateManager(
        child: ClashManager(
          child: ConnectivityManager(
            onInitialConnectivity: (results) {
              unawaited(
                _networkChangeCoordinator.seedInitialBaseline(results),
              );
            },
            onConnectivityChanged: (results) {
              detectionState.notifyRoutingChanged();
              ref.read(localIpProvider.notifier).value = null;
              unawaited(
                _networkChangeCoordinator.handleConnectivityChanged(results),
              );
              globalState.appController.addCheckIpNumDebounce();
            },
            child: child,
          ),
        ),
      );

  Widget _buildPlatformApp(Widget child) {
    if (system.isDesktop) {
      return WindowHeaderContainer(
        child: child,
      );
    }
    return VpnManager(
      child: child,
    );
  }

  Widget _buildApp(Widget child) => MessageManager(
        child: ThemeManager(
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) => _buildPlatformState(
        _buildState(
          Consumer(
            builder: (_, ref, child) {
              final locale =
                  ref.watch(appSettingProvider.select((state) => state.locale));
              final themeProps = ref.watch(themeSettingProvider);
              return MaterialApp(
                debugShowCheckedModeBanner: false,
                navigatorKey: globalState.navigatorKey,
                checkerboardRasterCacheImages: false,
                checkerboardOffscreenLayers: false,
                showPerformanceOverlay: false,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate
                ],
                builder: (_, child) {
                  final Widget app = AppEnvManager(
                    child: _buildPlatformApp(
                      _buildApp(child!),
                    ),
                  );

                  if (Platform.isMacOS) {
                    return FittedBox(
                      fit: BoxFit.contain,
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: 500,
                        height: 800,
                        child: app,
                      ),
                    );
                  }

                  return app;
                },
                scrollBehavior: BaseScrollBehavior(),
                onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appBrandName,
                locale: utils.getLocaleForString(locale),
                supportedLocales: AppLocalizations.delegate.supportedLocales,
                themeMode: themeProps.themeMode,
                theme: buildFreedomNetThemeData(
                  colorScheme: ref.watch(
                    genColorSchemeProvider(Brightness.light),
                  ),
                  pageTransitionsTheme: _pageTransitionsTheme,
                ),
                darkTheme: buildFreedomNetThemeData(
                  colorScheme: ref
                      .watch(genColorSchemeProvider(Brightness.dark))
                      .toPureBlack(themeProps.pureBlack),
                  pageTransitionsTheme: _pageTransitionsTheme,
                ),
                home: child,
              );
            },
            child: const HomePage(),
          ),
        ),
      );

  @override
  void dispose() {
    _networkChangeCoordinator.dispose();
    linkManager.destroy();
    globalState.stopGroupsUpdateTask();
    _autoUpdateProfilesTaskTimer?.cancel();
    if (Platform.isAndroid) {
      // Activity teardown (recreation, "don't keep activities", OEM kill) must
      // not shut the core down: the FGS/tunnel outlives the UI by design, and
      // handleExit()/destroy() here killed the executor under a live VPN.
      // savePreferences() is debounced/saved-on-pause, so fire-and-forget it to
      // honor the synchronous State.dispose() contract.
      unawaited(globalState.appController.savePreferences());
      super.dispose();
      return;
    }
    // An unexpected desktop UI teardown must detach from the background Agent,
    // not stop the Core. Explicit Full Exit performs the bounded network/Core
    // cleanup before the process reaches this point.
    unawaited(_desktopTeardown());
    super.dispose();
  }

  Future<void> _desktopTeardown() async {
    await globalState.appController.savePreferences();
    if (clashService?.usesAgent == true) {
      await clashService?.detach();
      return;
    }
    await clashCore.destroy();
    await globalState.appController.handleExit();
  }
}
