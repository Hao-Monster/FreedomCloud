import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/proxies/list.dart';
import 'package:flclashx/views/proxies/overview/overview.dart';
import 'package:flclashx/views/proxies/providers.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'common.dart';
import 'delay_test_action.dart';
import 'setting.dart';
import 'tab.dart';

class ProxiesView extends ConsumerStatefulWidget {
  const ProxiesView({super.key});

  @override
  ConsumerState<ProxiesView> createState() => _ProxiesViewState();
}

class _ProxiesViewState extends ConsumerState<ProxiesView> with PageMixin {
  bool _hasProviders = false;
  bool _isTab = false;
  final NodeOverviewCommandController _overviewCommandController =
      NodeOverviewCommandController();
  late final Widget _overviewInlineAccessory = NodeOverviewAppBarCommandBar(
    controller: _overviewCommandController,
  );
  CommonScaffoldState? _attachedScaffold;
  bool _titleSyncScheduled = false;
  bool _pendingSyncActions = false;
  bool? _lastTickerEnabled;
  Locale? _lastLocale;
  String? _lastIntlLocale;
  bool _hasRecordedLocale = false;
  bool? _lastHasNavigationBar;

  Future<void> _pingAllGroups() async {
    // Resolve every group's members and URL inside one shared bounded batch.
    final groups = ref.read(currentGroupsStateProvider).value;
    await delayTestGroups(groups);
  }

  bool _isAdvancedActionsVisible() {
    final expertExpanded = ref.read(expertNavigationExpandedProvider);
    if (expertExpanded) return true;
    final scaffold = context.commonScaffoldState;
    if (scaffold != null && !scaffold.hasNavigationBar) {
      return true;
    }
    return false;
  }

  bool _isScopeActionVisible() {
    if (!_isAdvancedActionsVisible()) return false;
    final enabled = ref.read(nodeOverviewEnabledProvider);
    final count = ref.read(profilesProvider.select((value) => value.length));
    return enabled && count > 0;
  }

  @override
  List<Widget> get actions {
    final advancedVisible = _isAdvancedActionsVisible();
    final showOverview = _readShowAllProfiles(context, ref);
    return [
      if (_isScopeActionVisible()) const NodeOverviewScopeAction(),
      if (advancedVisible && ref.read(globalModeEnabledProvider))
        const _ModeSelectorAction(),
      const SearchOrderMarker(),
      if (!showOverview) ...[
        DelayTestAction(
          coordinator: delayTests,
          onStart: _pingAllGroups,
          startLabel: appLocalizations.testAllDelay,
          cancelLabel: appLocalizations.cancel,
        ),
        if (!_isTab)
          Consumer(
            builder: (ctx, ref, __) {
              final unfoldSet = ref.watch(unfoldSetProvider);
              final groupNames = ref.watch(
                currentGroupsStateProvider.select(
                  (state) => state.value.map((e) => e.name).toList(),
                ),
              );
              final allExpanded = groupNames.isNotEmpty &&
                  groupNames.every(unfoldSet.contains);
              return IconButton(
                tooltip: allExpanded
                    ? appLocalizations.collapseAll
                    : appLocalizations.expandAll,
                onPressed: () {
                  if (allExpanded) {
                    globalState.appController.updateCurrentUnfoldSet({});
                  } else {
                    globalState.appController
                        .updateCurrentUnfoldSet(groupNames.toSet());
                  }
                },
                icon: Icon(
                  allExpanded ? Icons.unfold_less : Icons.unfold_more,
                ),
              );
            },
          ),
      ],
      if (advancedVisible)
        CommonPopupBox(
          targetBuilder: (open) => IconButton(
            onPressed: () {
              open(
                offset: const Offset(0, 20),
              );
            },
            icon: const Icon(
              Icons.more_vert,
            ),
          ),
          popup: CommonPopupMenu(
            items: [
              PopupMenuItemData(
                icon: Icons.tune,
                label: appLocalizations.settings,
                onPressed: () {
                  showSheet(
                    context: context,
                    props: const SheetProps(
                      isScrollControlled: true,
                    ),
                    builder: (_, type) => AdaptiveSheetScaffold(
                      type: type,
                      body: const ProxiesSetting(),
                      title: appLocalizations.settings,
                    ),
                  );
                },
              ),
              if (_hasProviders)
                PopupMenuItemData(
                  icon: Icons.poll_outlined,
                  label: appLocalizations.providers,
                  onPressed: () {
                    showExtend(
                      context,
                      builder: (_, type) => const ProvidersView(),
                    );
                  },
                ),
              if (!_isTab)
                PopupMenuItemData(
                  icon: Icons.style_outlined,
                  label: appLocalizations.iconConfiguration,
                  onPressed: () {
                    showExtend(
                      context,
                      builder: (_, type) => const _IconConfigView(),
                    );
                  },
                ),
            ],
          ),
        ),
    ];
  }

  @override
  Null Function(String value) get onSearch => (value) {
        ref.read(proxiesQueryProvider.notifier).value = value;
      };

  @override
  void dispose() {
    final attached = _attachedScaffold;
    final accessory = _overviewInlineAccessory;
    _overviewCommandController.dispose();
    super.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached != null &&
          attached.mounted &&
          identical(attached.titleAccessory, accessory)) {
        attached.titleAccessory = null;
      }
    });
  }

  void _scheduleTitleAccessorySync({bool syncActions = false}) {
    _pendingSyncActions = _pendingSyncActions || syncActions;
    if (_titleSyncScheduled || !mounted) return;
    _titleSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _titleSyncScheduled = false;
      _syncTitleAccessory();
    });
  }

  void _syncTitleAccessoryNowOrScheduled({bool syncActions = false}) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      _syncTitleAccessory(syncActions: syncActions);
    } else {
      _scheduleTitleAccessorySync(syncActions: syncActions);
    }
  }

  void _syncTitleAccessory({
    CommonScaffoldState? scaffoldOverride,
    bool syncActions = false,
  }) {
    final shouldSyncActions = syncActions || _pendingSyncActions;
    _pendingSyncActions = false;
    if (!mounted) return;
    final scaffold = scaffoldOverride ?? context.commonScaffoldState;
    if (scaffold == null || !scaffold.mounted) return;
    _attachedScaffold = scaffold;
    final isProxiesPage =
        ref.read(proxiesActionsStateProvider).pageLabel == PageLabel.proxies;
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    final overviewActive = _readShowAllProfiles(context, ref);
    final shouldAttach = isProxiesPage && tickerEnabled && overviewActive;
    if (isProxiesPage && tickerEnabled && shouldSyncActions) {
      scaffold
        ..actions = actions
        ..floatingActionButton = floatingActionButton
        ..onKeywordsUpdate = onKeywordsUpdate;
    }
    if (shouldAttach) {
      if (!identical(scaffold.titleAccessory, _overviewInlineAccessory)) {
        scaffold.titleAccessory = _overviewInlineAccessory;
      }
    } else if (identical(scaffold.titleAccessory, _overviewInlineAccessory)) {
      scaffold.titleAccessory = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    final scaffold = context.commonScaffoldState;
    if (scaffold != null) {
      _attachedScaffold = scaffold;
    }
    final currentLocale = Localizations.maybeLocaleOf(context);
    final currentIntlLocale = Intl.getCurrentLocale();
    final localeChanged = _hasRecordedLocale &&
        (currentLocale != _lastLocale ||
            currentIntlLocale != _lastIntlLocale);
    _lastLocale = currentLocale;
    _lastIntlLocale = currentIntlLocale;
    _hasRecordedLocale = true;

    final isProxiesPage =
        ref.read(proxiesActionsStateProvider).pageLabel == PageLabel.proxies;
    if (localeChanged && isProxiesPage && tickerEnabled) {
      // Rebuild cached action tooltips/menus in the new locale while preserving search state.
      _scheduleTitleAccessorySync(syncActions: true);
    }
    if (_lastTickerEnabled != tickerEnabled) {
      _lastTickerEnabled = tickerEnabled;
      _scheduleTitleAccessorySync(syncActions: tickerEnabled);
    } else if (tickerEnabled &&
        isProxiesPage &&
        _readShowAllProfiles(context, ref) &&
        scaffold != null &&
        scaffold.titleAccessory == null) {
      _scheduleTitleAccessorySync();
    }
  }

  @override
  void initState() {
    _overviewCommandController.inlineAccessoryWidget = _overviewInlineAccessory;
    ref.listenManual(
      proxiesActionsStateProvider,
      fireImmediately: true,
      (prev, next) {
        if (prev == next) {
          return;
        }
        if (next.pageLabel == PageLabel.proxies) {
          _hasProviders = next.hasProviders;
          _isTab = next.type == ProxiesType.tab;
          if (prev?.pageLabel != PageLabel.proxies) {
            initPageState();
          } else {
            _scheduleTitleAccessorySync(syncActions: true);
          }
          return;
        } else {
          _syncTitleAccessoryNowOrScheduled();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ref.read(proxiesQueryProvider.notifier).value = "";
            }
          });
        }
      },
    );
    ref.listenManual<bool>(
      nodeOverviewEnabledProvider,
      (_, __) => _syncTitleAccessoryNowOrScheduled(syncActions: true),
    );
    ref.listenManual<ProxiesScope>(
      proxiesScopeProvider,
      (_, __) => _syncTitleAccessoryNowOrScheduled(syncActions: true),
    );
    ref.listenManual<bool>(
      expertNavigationExpandedProvider,
      (_, __) => _syncTitleAccessoryNowOrScheduled(syncActions: true),
    );
    ref.listenManual<bool>(
      globalModeEnabledProvider,
      (_, __) => _syncTitleAccessoryNowOrScheduled(syncActions: true),
    );
    ref.listenManual<bool>(
      profilesProvider.select((profiles) => profiles.isEmpty),
      (_, __) => _syncTitleAccessoryNowOrScheduled(syncActions: true),
    );
    super.initState();
  }

  @override
  void initPageState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final commonScaffoldState = context.commonScaffoldState;
      commonScaffoldState?.actions = actions;
      commonScaffoldState?.floatingActionButton = floatingActionButton;
      commonScaffoldState?.onKeywordsUpdate = onKeywordsUpdate;
      commonScaffoldState?.updateSearchState(
        (_) => AppBarSearchState(
          onSearch: onSearch,
        ),
      );
      _syncTitleAccessory(scaffoldOverride: commonScaffoldState);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = context.commonScaffoldState;
    if (scaffold != null) {
      _attachedScaffold = scaffold;
      final hasNavBar = scaffold.hasNavigationBar;
      final isProxiesPage =
          ref.read(proxiesActionsStateProvider).pageLabel == PageLabel.proxies;
      final tickerEnabled = TickerMode.valuesOf(context).enabled;
      final overviewActive = _readShowAllProfiles(context, ref);
      if (_lastHasNavigationBar != hasNavBar) {
        final changed = _lastHasNavigationBar != null;
        _lastHasNavigationBar = hasNavBar;
        if (changed && isProxiesPage && tickerEnabled) {
          _scheduleTitleAccessorySync(syncActions: true);
        }
      }
      if (isProxiesPage &&
          tickerEnabled &&
          overviewActive &&
          scaffold.titleAccessory == null) {
        _scheduleTitleAccessorySync();
      } else if ((!isProxiesPage || !tickerEnabled || !overviewActive) &&
          identical(scaffold.titleAccessory, _overviewInlineAccessory)) {
        _scheduleTitleAccessorySync();
      }
    }
    final proxiesType = ref.watch(
      proxiesStyleSettingProvider.select(
        (state) => state.type,
      ),
    );
    return NodeOverviewScopeView(
      commandController: _overviewCommandController,
      currentView: switch (proxiesType) {
        ProxiesType.tab => const ProxiesTabView(),
        ProxiesType.list => const ProxiesListView(),
      },
    );
  }
}

bool _readShowAllProfiles(BuildContext context, WidgetRef ref) {
  if (!ref.read(nodeOverviewEnabledProvider)) return false;
  final expertExpanded = ref.read(expertNavigationExpandedProvider);
  if (!expertExpanded &&
      (context.commonScaffoldState?.hasNavigationBar ?? false)) {
    return true;
  }
  final count = ref.read(profilesProvider).length;
  return count == 0 || ref.read(proxiesScopeProvider) == ProxiesScope.all;
}

class _ModeSelectorAction extends ConsumerWidget {
  const _ModeSelectorAction();

  String _modeLabel(BuildContext context, Mode mode) => switch (mode) {
        Mode.rule => appLocalizations.rule,
        Mode.global => appLocalizations.global,
        Mode.direct => appLocalizations.direct,
      };

  IconData _modeIcon(Mode mode) => switch (mode) {
        Mode.rule => Icons.rule,
        Mode.global => Icons.public,
        Mode.direct => Icons.flash_on,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Localizations.maybeLocaleOf(context);
    final mode = ref.watch(
      patchClashConfigProvider.select((state) => state.mode),
    );

    return CommonPopupBox(
      targetBuilder: (open) => IconButton(
        tooltip: appLocalizations.action_mode,
        onPressed: () => open(offset: const Offset(0, 20)),
        icon: Icon(_modeIcon(mode)),
      ),
      popup: CommonPopupMenu(
        items: [
          for (final item in Mode.values.where((m) => m != Mode.direct))
            PopupMenuItemData(
              icon: _modeIcon(item),
              label: _modeLabel(context, item),
              onPressed: () {
                globalState.appController.changeMode(item);
              },
            ),
        ],
      ),
    );
  }
}

class _IconConfigView extends ConsumerWidget {
  const _IconConfigView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconMap = ref.watch(proxiesStyleSettingProvider.select(
      (state) => state.iconMap,
    ));
    return CommonScaffold(
      title: appLocalizations.iconConfiguration,
      body: MapInputPage(
        title: appLocalizations.iconConfiguration,
        map: iconMap,
        keyLabel: appLocalizations.regExp,
        valueLabel: appLocalizations.icon,
        titleBuilder: (item) => Text(item.key),
        leadingBuilder: (item) => Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: CommonTargetIcon(
            src: item.value,
            size: 42,
          ),
        ),
        subtitleBuilder: (item) => Text(
          item.value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onChange: (value) {
          ref.read(proxiesStyleSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  iconMap: value,
                ),
              );
        },
      ),
    );
  }
}
