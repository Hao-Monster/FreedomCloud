import 'dart:math';

import 'package:defer_pointer/defer_pointer.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flclashx/views/tools/health_check_view.dart';
import 'widgets/hero_connect.dart';
import 'widgets/start_button.dart';


class DashboardView extends ConsumerStatefulWidget {
  const DashboardView({super.key});

  @override
  ConsumerState<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends ConsumerState<DashboardView> with PageMixin {
  final key = GlobalKey<SuperGridState>();
  final _isEditNotifier = ValueNotifier<bool>(false);
  final _addedWidgetsNotifier = ValueNotifier<List<GridItem>>([]);

  @override
  void initState() {
    ref.listenManual(
      isCurrentPageProvider(PageLabel.dashboard),
      (prev, next) {
        if (prev != next && next == true) {
          initPageState();
        }
      },
      fireImmediately: true,
    );
    return super.initState();
  }

  @override
  void dispose() {
    _isEditNotifier.dispose();
    _addedWidgetsNotifier.dispose();
    super.dispose();
  }

  @override
  Widget? get floatingActionButton => null; // Moved to bottom of body

  Widget _buildIsEdit(Widget Function(bool) builder) => ValueListenableBuilder(
      valueListenable: _isEditNotifier,
      builder: (_, isEdit, ___) => builder(isEdit),
    );

  @override
  List<Widget> get actions => [
        _buildIsEdit((isEdit) => isEdit
            ? const SizedBox.shrink()
            : ConciseDashboardModeButton(
                key: const ValueKey('dashboard-concise-mode-toggle'),
                onWillToggle: () {
                  if (_isEditNotifier.value) {
                    _isEditNotifier.value = false;
                  }
                },
              )),
        _buildIsEdit((isEdit) => isEdit
            ? const SizedBox.shrink()
            : IconButton(
                key: const ValueKey('dashboard-health-check-action'),
                tooltip: appLocalizations.healthCheckTitle,
                icon: const Icon(Icons.monitor_heart_outlined),
                onPressed: () => openHealthCheck(context),
              )),
        _buildIsEdit((isEdit) => isEdit
              ? ValueListenableBuilder(
                  valueListenable: _addedWidgetsNotifier,
                  builder: (_, addedChildren, child) {
                    if (addedChildren.isEmpty) {
                      return Container();
                    }
                    return child!;
                  },
                  child: IconButton(
                    onPressed: _showAddWidgetsModal,
                    icon: const Icon(
                      Icons.add_circle,
                    ),
                  ),
                )
              : const SizedBox()),
        Consumer(
          builder: (context, ref, child) {
            final headers = ref.watch(currentProfileProvider
                .select((profile) => profile?.providerHeaders)) ?? {};
            final denyEditing = headers['flclashx-denywidgets'];
            // Editing only applies to the old grid; hide it whenever the hero
            // board is active (same decision the body makes).
            final newDashboard = ref.watch(newDashboardEnabledProvider);

            if (denyEditing == 'true' || newDashboard) {
              return const SizedBox.shrink();
            }

            return _buildIsEdit((isEdit) => IconButton(
              tooltip: isEdit ? appLocalizations.save : appLocalizations.edit,
              icon: isEdit
                    ? const Icon(Icons.save)
                    : const Icon(Icons.edit),
              onPressed: _handleUpdateIsEdit,
            ));
          },
        ),
      ];

  void _showAddWidgetsModal() {
    showSheet(
      builder: (_, type) => ValueListenableBuilder(
          valueListenable: _addedWidgetsNotifier,
          builder: (_, value, __) => AdaptiveSheetScaffold(
              type: type,
              body: _AddDashboardWidgetModal(
                items: value,
                onAdd: (gridItem) {
                  key.currentState?.handleAdd(gridItem);
                },
              ),
              title: appLocalizations.add,
            ),
        ),
      context: context,
    );
  }

  void _handleUpdateIsEdit() {
    if (_isEditNotifier.value == true) {
      _handleSave();
    }
    _isEditNotifier.value = !_isEditNotifier.value;
  }

  void _handleSave() {
    final children = key.currentState?.children;
    if (children == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dashboardWidgets = children
          .map(
            DashboardWidget.getDashboardWidget,
          )
          .toList();
      ref.read(appSettingProvider.notifier).updateState(
            (state) => state.copyWith(dashboardWidgets: dashboardWidgets),
          );
    });
  }

  bool _isAllowedWidget(
    DashboardWidget item, {
    required bool globalModeEnabled,
    required bool hasAnnounceData,
    required bool hasMetainfoWidget,
    required bool hasServiceInfoData,
    required bool hasServerInfoData,
  }) {
    if (!item.platforms.contains(SupportPlatform.currentPlatform)) {
      return false;
    }
    
    if (!globalModeEnabled) {
      if (item == DashboardWidget.outboundMode || 
          item == DashboardWidget.outboundModeV2) {
        return false;
      }
    }
    
    if (item == DashboardWidget.announce &&
        (!hasAnnounceData || hasMetainfoWidget)) {
      return false;
    }
    if (item == DashboardWidget.serviceInfo && !hasServiceInfoData) {
      return false;
    }
    if (item == DashboardWidget.changeServerButton && !hasServerInfoData) {
      return false;
    }
    
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final dashboardState = ref.watch(dashboardStateProvider);
    final globalModeEnabled = ref.watch(globalModeEnabledProvider);
    final hasAnnounce = ref.watch(hasAnnounceDataProvider);
    final hasServiceInfo = ref.watch(hasServiceInfoDataProvider);
    final hasServerInfo = ref.watch(hasServerInfoDataProvider);
    final columns = max(4 * ((dashboardState.viewWidth / 320).ceil()), 8);
    final spacing = 16.ap;

    final hasMetainfoWidget = dashboardState.dashboardWidgets.contains(
      DashboardWidget.metainfo,
    );
    bool isAllowed(DashboardWidget item) => _isAllowedWidget(
      item,
      globalModeEnabled: globalModeEnabled,
      hasAnnounceData: hasAnnounce,
      hasMetainfoWidget: hasMetainfoWidget,
      hasServiceInfoData: hasServiceInfo,
      hasServerInfoData: hasServerInfo,
    );

    final children = [
      ...dashboardState.dashboardWidgets
          .where(isAllowed)
          .map(
            (item) => item.widget,
          ),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _addedWidgetsNotifier.value = DashboardWidget.values
          .where(
            (item) => !children.contains(item.widget) && isAllowed(item),
          )
          .map((item) => item.widget)
          .toList();
    });
    return Column(
      children: [
        _buildIsEdit((isEdit) {
      if (isEdit) {
        return Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SystemBackBlock(
              child: CommonPopScope(
                child: SuperGrid(
                  key: key,
                  crossAxisCount: columns,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                  onUpdate: _handleSave,
                  children: [
                    ...dashboardState.dashboardWidgets
                        .where(isAllowed)
                        .map((item) => item.widget),
                  ],
                ),
                onPop: () {
                  _handleUpdateIsEdit();
                  return false;
                },
              ),
            ),
          ),
        );
      }
      final newDashboard = ref.watch(newDashboardEnabledProvider);

      if (!newDashboard) {
        final startButtonState = ref.watch(startButtonSelectorStateProvider);
        final showFloatingStart =
            startButtonState.isInit && startButtonState.hasProfile;
        return Expanded(
          child: LayoutBuilder(
            builder: (context, paneConstraints) {
              final paneTextScale = MediaQuery.textScalerOf(context).scale(1.0);
              final floatingBottomMargin = computeFloatingProxyDockBottomMargin(
                paneConstraints.maxHeight,
              );
              final bottomScrollClearance = showFloatingStart
                  ? computeFloatingProxyDockScrollClearance(
                      textScale: paneTextScale,
                      bottomMargin: floatingBottomMargin,
                      viewportWidth: paneConstraints.maxWidth,
                      viewportHeight: paneConstraints.maxHeight,
                    )
                  : 16.0;
              return FloatingProxyDockOverlay(
                viewportWidth: paneConstraints.maxWidth,
                viewportHeight: paneConstraints.maxHeight,
                dock: showFloatingStart ? const StartButton(floating: true) : null,
                child: SingleChildScrollView(
                  key: const ValueKey('dashboard-scroll-view'),
                  padding: const EdgeInsets.all(16).copyWith(
                    bottom: bottomScrollClearance,
                  ),
                  child: Grid(
                    crossAxisCount: columns,
                    crossAxisSpacing: spacing,
                    mainAxisSpacing: spacing,
                    children: children,
                  ),
                ),
              );
            },
          ),
        );
      }

      return const Expanded(
        child: Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 24),
          child: HeroConnect(),
        ),
      );
    }),
      ],
    );
  }
}

class _AddDashboardWidgetModal extends StatelessWidget {

  const _AddDashboardWidgetModal({
    required this.items,
    required this.onAdd,
  });
  final List<GridItem> items;
  final Function(GridItem item) onAdd;

  @override
  Widget build(BuildContext context) => DeferredPointerHandler(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(
          16,
        ),
        child: Grid(
          crossAxisCount: 8,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: items
              .map(
                (item) => item.wrap(
                  builder: (child) => _AddedContainer(
                      onAdd: () {
                        onAdd(item);
                      },
                      child: child,
                    ),
                ),
              )
              .toList(),
        ),
      ),
    );
}

class _AddedContainer extends StatefulWidget {

  const _AddedContainer({
    required this.child,
    required this.onAdd,
  });
  final Widget child;
  final VoidCallback onAdd;

  @override
  State<_AddedContainer> createState() => _AddedContainerState();
}

class _AddedContainerState extends State<_AddedContainer> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(_AddedContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child != widget.child) {}
  }

  Future<void> _handleAdd() async {
    widget.onAdd();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
      clipBehavior: Clip.none,
      children: [
        ActivateBox(
          child: widget.child,
        ),
        Positioned(
          top: -8,
          right: -8,
          child: DeferPointer(
            child: SizedBox(
              width: 24,
              height: 24,
              child: IconButton.filled(
                iconSize: 20,
                padding: const EdgeInsets.all(2),
                onPressed: _handleAdd,
                icon: const Icon(
                  Icons.add,
                ),
              ),
            ),
          ),
        )
      ],
    );
}


/// Top AppBar capsule button allowing direct 1-click switching between the
/// classic customizable widget dashboard and the concise hero dashboard.
class ConciseDashboardModeButton extends ConsumerWidget {
  const ConciseDashboardModeButton({
    super.key,
    this.onWillToggle,
  });

  final VoidCallback? onWillToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConcise = ref.watch(newDashboardEnabledProvider);
    final label = appLocalizations.newDashboard;
    final media = MediaQuery.of(context);
    final rawScale = media.textScaler.scale(14) / 14;
    final safeScale = rawScale > 0 ? rawScale : 1.0;
    final clampedScale = safeScale.clamp(0.85, 1.35);
    // Collapse the text label only when effective horizontal room is too tight
    // for the AppBar title + action buttons (e.g. 320px width at 2.0x scale).
    final compactMode = (media.size.width / safeScale) < 250;

    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(clampedScale)),
      child: Semantics(
        container: true,
        button: true,
        toggled: isConcise,
        label: label,
        excludeSemantics: true,
        child: ConciseDashboardModePill(
          isHighlighted: isConcise,
          label: label,
          showLabel: !compactMode,
          onTap: () {
            onWillToggle?.call();
            ref.read(appSettingProvider.notifier).updateState(
                  (state) => state.copyWith(newDashboard: !isConcise),
                );
          },
        ),
      ),
    );
  }
}

/// Visual pill surface for [ConciseDashboardModeButton] with distinct highlighted
/// active appearance vs muted inactive appearance.
class ConciseDashboardModePill extends StatelessWidget {
  const ConciseDashboardModePill({
    super.key,
    required this.isHighlighted,
    required this.label,
    required this.onTap,
    this.showLabel = true,
  });

  final bool isHighlighted;
  final String label;
  final VoidCallback onTap;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final hairline = freedomNetHairlineColor(colorScheme);
    final backgroundColor = isHighlighted
        ? colorScheme.primary
        : colorScheme.surfaceContainerHigh.withValues(alpha: 0.72);
    final foregroundColor =
        isHighlighted ? colorScheme.onPrimary : colorScheme.onSurfaceVariant;
    final borderColor = isHighlighted ? colorScheme.primary : hairline;

    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            constraints: BoxConstraints(
              minHeight: 32,
              minWidth: showLabel ? 0 : 34,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: showLabel ? 10 : 8,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: borderColor,
                width: isHighlighted ? 1.2 : 1.0,
              ),
              boxShadow: isHighlighted
                  ? [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.28),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isHighlighted
                      ? Icons.auto_awesome_rounded
                      : Icons.dashboard_customize_outlined,
                  size: 15,
                  color: foregroundColor,
                ),
                if (showLabel) ...[
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.labelMedium?.copyWith(
                        color: foregroundColor,
                        fontWeight:
                            isHighlighted ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
