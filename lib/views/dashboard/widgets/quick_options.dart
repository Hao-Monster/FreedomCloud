import 'dart:async';
import 'dart:io';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/providers/app.dart';
import 'package:flclashx/providers/config.dart';
import 'package:flclashx/providers/state.dart';
import 'package:flclashx/providers/tun.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/config/network.dart';
import 'package:flclashx/views/tools/health_check_view.dart';
import 'package:flclashx/widgets/tun_status.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TUNButton extends StatelessWidget {
  const TUNButton({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
      height: getWidgetHeight(1),
      child: CommonCard(
        onPressed: () {
          showSheet(
            context: context,
            builder: (_, type) => AdaptiveSheetScaffold(
                type: type,
                body: generateListView(
                  generateSection(
                    items: [
                      if (system.isDesktop) const TUNItem(),
                      if (Platform.isMacOS) const AutoSetSystemDnsItem(),
                      const TunStackItem(),
                    ],
                  ),
                ),
                title: appLocalizations.tun,
              ),
          );
        },
        info: Info(
          label: appLocalizations.tun,
          iconData: Icons.stacked_line_chart,
        ),
        child: Container(
          padding: baseInfoEdgeInsets.copyWith(
            top: 4,
            bottom: 8,
            right: 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                flex: 1,
                child: Platform.isWindows ? Consumer(builder: (_, ref, __) {
                  final runtime = ref.watch(tunRuntimeProvider);
                  final isStopped = ref.watch(
                    runTimeProvider.select((state) => state == null),
                  );
                  final label = tunStatusLabel(
                    runtime,
                    waiting: runtime.desiredEnabled && isStopped,
                  );
                  return Tooltip(
                    message: label,
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.adjustSize(-2)
                          .toLight,
                    ),
                  );
                }) : TooltipText(
                  text: Text(
                    appLocalizations.options,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.adjustSize(-2)
                        .toLight,
                  ),
                ),
              ),
              Consumer(
                builder: (_, ref, __) {
                  if (Platform.isWindows) {
                    final runtime = ref.watch(tunRuntimeProvider);
                    return Tooltip(
                      message: tunStatusLabel(runtime),
                      child: TunStatusSwitch(
                        runtime: runtime,
                        onChanged: globalState.appController.setTunEnabled,
                        onDiagnose: () => openHealthCheck(context),
                      ),
                    );
                  }
                  final enable = ref.watch(patchClashConfigProvider
                      .select((state) => state.tun.enable));
                  return Switch(
                    value: enable,
                    onChanged: (value) {
                      ref.read(patchClashConfigProvider.notifier).updateState(
                            (state) => state.copyWith.tun(
                              enable: value,
                            ),
                          );
                    },
                  );
                },
              )
            ],
          ),
        ),
      ),
    );
}

class SystemProxyButton extends StatelessWidget {
  const SystemProxyButton({super.key});

  static String _statusLabel({
    required bool configured,
    required bool isStart,
    required bool? pending,
  }) {
    if (pending != null && !pending && isStart && configured) {
      return appLocalizations.tunStatusStopping;
    }
    if ((pending ?? false) && configured) {
      return appLocalizations.tunStatusStarting;
    }
    if (isStart && configured) {
      return appLocalizations.tunStatusOn;
    }
    if (!isStart && configured) {
      return appLocalizations.tunStatusWaiting;
    }
    return appLocalizations.tunStatusOff;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
      height: getWidgetHeight(1),
      child: CommonCard(
        onPressed: () {
          showSheet(
            context: context,
            builder: (_, type) => AdaptiveSheetScaffold(
                type: type,
                body: generateListView(
                  generateSection(
                    items: [
                      const SystemProxyItem(),
                      const BypassDomainItem(),
                    ],
                  ),
                ),
                title: appLocalizations.systemProxy,
              ),
          );
        },
        info: Info(
          label: appLocalizations.systemProxy,
          iconData: Icons.shuffle,
        ),
        child: Container(
          padding: baseInfoEdgeInsets.copyWith(
            top: 4,
            bottom: 8,
            right: 8,
          ),
          child: Consumer(
            builder: (_, ref, __) {
              final systemProxy = ref.watch(
                networkSettingProvider.select((state) => state.systemProxy),
              );
              final mixedPort = ref.watch(
                patchClashConfigProvider.select((state) => state.mixedPort),
              );
              final isStart = ref.watch(
                runTimeProvider.select((state) => state != null),
              );
              final hasProfile = ref.watch(
                currentProfileProvider.select((profile) => profile != null),
              );
              final pending = ref.watch(statusSwitchPendingProvider);
              final configured = systemProxy && mixedPort > 0;
              final isStopping = pending != null && !pending;
              final isActive = isStart && configured && !isStopping;
              final isWaiting = !isStart && configured && pending == null;
              final label = _statusLabel(
                configured: configured,
                isStart: isStart,
                pending: pending,
              );

              return Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    flex: 1,
                    child: Tooltip(
                      message: label,
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.adjustSize(-2)
                            .toLight,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isWaiting)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          padding: const EdgeInsets.all(4),
                          iconSize: 18,
                          tooltip: appLocalizations.tunDisableAction,
                          onPressed: () {
                            ref
                                .read(networkSettingProvider.notifier)
                                .updateState(
                                  (state) =>
                                      state.copyWith(systemProxy: false),
                                );
                          },
                          icon: const Icon(Icons.close),
                        ),
                      Semantics(
                        label: label,
                        child: Switch(
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          value: isActive,
                          onChanged: (pending != null || mixedPort <= 0)
                              ? null
                              : (value) {
                                  ref
                                      .read(networkSettingProvider.notifier)
                                      .updateState(
                                        (state) => state.copyWith(
                                          systemProxy: value,
                                        ),
                                      );
                                  if (value && !isStart && hasProfile) {
                                    unawaited(
                                      globalState.appController
                                          .updateStatus(true),
                                    );
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
}

class VpnButton extends StatelessWidget {
  const VpnButton({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
      height: getWidgetHeight(1),
      child: CommonCard(
        onPressed: () {
          showSheet(
            context: context,
            builder: (_, type) => AdaptiveSheetScaffold(
                type: type,
                body: generateListView(
                  generateSection(
                    items: [
                      const VPNItem(),
                      const VpnSystemProxyItem(),
                      const TunStackItem(),
                    ],
                  ),
                ),
                title: "VPN",
              ),
          );
        },
        info: const Info(
          label: "VPN",
          iconData: Icons.stacked_line_chart,
        ),
        child: Container(
          padding: baseInfoEdgeInsets.copyWith(
            top: 4,
            bottom: 8,
            right: 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                flex: 1,
                child: TooltipText(
                  text: Text(
                    appLocalizations.options,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.adjustSize(-2)
                        .toLight,
                  ),
                ),
              ),
              Consumer(
                builder: (_, ref, __) {
                  final enable = ref.watch(
                    vpnSettingProvider.select(
                      (state) => state.enable,
                    ),
                  );
                  return Switch(
                    value: enable,
                    onChanged: (value) {
                      ref.read(vpnSettingProvider.notifier).updateState(
                            (state) => state.copyWith(
                              enable: value,
                            ),
                          );
                    },
                  );
                },
              )
            ],
          ),
        ),
      ),
    );
}
