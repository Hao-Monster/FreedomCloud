import 'dart:io';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/dashboard/widgets/hero_nav_bar.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

typedef OnSelected = void Function(int index);

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => HomeBackScope(
        child: Consumer(
          builder: (_, ref, child) {
            final state = ref.watch(homeStateProvider);
            final viewMode = state.viewMode;
            final navigationItems = state.navigationItems;
            final pageLabel = state.pageLabel;
            final index = navigationItems.lastIndexWhere(
              (element) => element.label == pageLabel,
            );
            final currentIndex = index == -1 ? 0 : index;
            final navigationBar = CommonNavigationBar(
              viewMode: viewMode,
              navigationItems: navigationItems,
              currentIndex: currentIndex,
            );
            // Mobile bottom bar follows the dashboard style: the hero nav bar for
            // the new look, the classic Material NavigationBar for the old one.
            final newDashboard = ref.watch(newDashboardEnabledProvider);
            final bottomNavigationBar = viewMode == ViewMode.mobile
                ? (newDashboard ? const HeroNavBar() : navigationBar)
                : null;
            final sideNavigationBar =
                viewMode != ViewMode.mobile ? navigationBar : null;
            final showAppBarBrandTrigger =
                viewMode == ViewMode.mobile || Platform.isMacOS;
            return CommonScaffold(
              key: globalState.homeScaffoldKey,
              leading: showAppBarBrandTrigger
                  ? const _CompactBrandTributeLeading()
                  : null,
              title: Intl.message(
                pageLabel.name,
              ),
              sideNavigationBar: sideNavigationBar,
              body: child!,
              bottomNavigationBar: bottomNavigationBar,
            );
          },
          child: const _HomePageView(),
        ),
      );
}

class _HomePageView extends ConsumerStatefulWidget {
  const _HomePageView();

  @override
  ConsumerState createState() => _HomePageViewState();
}

class _HomePageViewState extends ConsumerState<_HomePageView> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: _pageIndex,
      keepPage: true,
    );
    ref.listenManual(currentPageLabelProvider, (prev, next) {
      if (prev != next) {
        _toPage(next);
      }
    });
    ref.listenManual(currentNavigationsStateProvider, (prev, next) {
      if (prev?.value.length != next.value.length) {
        _updatePageController();
      }
    });
  }

  int get _pageIndex {
    final navigationItems = ref.read(currentNavigationsStateProvider).value;
    final currentLabel = ref.read(currentPageLabelProvider);
    final index = navigationItems.indexWhere(
      (item) => item.label == currentLabel,
    );
    return index < 0 ? 0 : index;
  }

  Future<void> _toPage(PageLabel pageLabel, [bool ignoreAnimateTo = false]) async {
    if (!mounted) {
      return;
    }
    final navigationItems = ref.read(currentNavigationsStateProvider).value;
    final index = navigationItems.indexWhere((item) => item.label == pageLabel);
    if (index == -1) {
      return;
    }
    final isAnimateToPage = ref.read(appSettingProvider).isAnimateToPage;
    final isMobile = ref.read(isMobileViewProvider);
    final currentPage =
        _pageController.hasClients ? (_pageController.page?.round() ?? 0) : 0;
    final canAnimate = isAnimateToPage &&
        isMobile &&
        !ignoreAnimateTo &&
        currentPage >= 0 &&
        currentPage < navigationItems.length;
    if (canAnimate) {
      await _pageController.animateToPage(
        index,
        duration: kTabScrollDuration,
        curve: Curves.easeOut,
      );
    } else if (_pageController.hasClients) {
      _pageController.jumpToPage(index);
    }
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  void _updatePageController() {
    final pageLabel = ref.read(currentPageLabelProvider);
    _toPage(pageLabel, true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navigationItems = ref.watch(currentNavigationsStateProvider).value;
    final currentLabel = ref.watch(currentPageLabelProvider);
    return PageView.builder(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: navigationItems.length,
      itemBuilder: (_, index) {
        final navigationItem = navigationItems[index];
        final isActive = navigationItem.label == currentLabel;
        return ExcludeFocus(
          excluding: !isActive,
          child: TickerMode(
            enabled: isActive,
            child: KeepScope(
              keep: navigationItem.keep,
              key: Key(navigationItem.label.name),
              child: navigationItem.view,
            ),
          ),
        );
      },
    );
  }
}

class CommonNavigationBar extends ConsumerWidget {
  final ViewMode viewMode;
  final List<NavigationItem> navigationItems;
  final int currentIndex;

  const CommonNavigationBar({
    super.key,
    required this.viewMode,
    required this.navigationItems,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expertExpanded = ref.watch(expertNavigationExpandedProvider);
    if (viewMode == ViewMode.mobile) {
      final toggleLabel =
          expertExpanded ? appLocalizations.noviceMode : appLocalizations.expertMode;
      final toggleIcon = Icon(
        expertExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
      );
      final colors = context.colorScheme;
      return DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: freedomNetHairlineColor(colors)),
          ),
        ),
        child: NavigationBarTheme(
          data: _NavigationBarDefaultsM3(context),
          child: NavigationBar(
            destinations: [
              ...navigationItems.map(
                (e) => NavigationDestination(
                  icon: e.icon,
                  label: Intl.message(e.label.name),
                ),
              ),
              NavigationDestination(
                key: const ValueKey('navigation-expert-mode-toggle'),
                icon: toggleIcon,
                label: toggleLabel,
              ),
            ],
            onDestinationSelected: (index) {
              if (index == navigationItems.length) {
                toggleExpertNavigationMode(ref);
                return;
              }
              globalState.appController.toPage(navigationItems[index].label);
            },
            selectedIndex: navigationItems.isEmpty
                ? 0
                : currentIndex.clamp(0, navigationItems.length - 1),
          ),
        ),
      );
    }
    final colors = context.colorScheme;
    final isDark = colors.brightness == Brightness.dark;
    final isZh = Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');
    final hairline = freedomNetHairlineColor(colors);
    final tributeSemanticsLabel =
        '${appLocalizations.appBrandName} · ${appLocalizations.brandDialogSubtitle}';
    return Material(
      color: colors.surfaceDim,
      // SafeArea: the app draws edge-to-edge, so on tablets/foldables (which
      // also get the desktop-style side rail) the status bar overlapped the
      // logo. Shifts the whole logo+rail block below the system inset; no-op
      // on desktop OSes.
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: hairline),
          ),
        ),
        child: SafeArea(
          bottom: false,
          right: false,
          child: Column(
            children: [
              // Brand emblem + one-tap brand showcase trigger at top of rail
              if (!Platform.isMacOS) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Semantics(
                    key: const ValueKey('brand-tribute-trigger'),
                    container: true,
                    button: true,
                    label: tributeSemanticsLabel,
                    child: Tooltip(
                      excludeFromSemantics: true,
                      message: appLocalizations.brandDialogSubtitle,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => showFreedomNetTributeDialog(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 8,
                          ),
                          child: ExcludeSemantics(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const FreedomNetBrandMark(size: 36),
                                const SizedBox(height: 6),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 88),
                                  child: Text(
                                    appLocalizations.appBrandName,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.textTheme.labelMedium
                                        ?.copyWith(
                                      color: colors.onSurface,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                                if (isZh) ...[
                                  const SizedBox(height: 1),
                                  ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 88),
                                    child: Text(
                                      brandNameEn,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.textTheme.labelSmall
                                          ?.copyWith(
                                        fontSize: 9.5,
                                        color: colors.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Divider(
                  height: 1,
                  indent: 14,
                  endIndent: 14,
                  color: hairline,
                ),
              ],
              Expanded(
                child: Builder(
                  builder: (context) {
                    final purchaseIndex = navigationItems.indexWhere(
                      (item) => item.label == PageLabel.purchase,
                    );
                    final primaryCount = purchaseIndex >= 0
                        ? purchaseIndex + 1
                        : navigationItems.length;
                    final primaryItems =
                        navigationItems.sublist(0, primaryCount);
                    final expandedItems =
                        navigationItems.sublist(primaryCount);
                    final effectiveIndex = navigationItems.isEmpty
                        ? -1
                        : currentIndex.clamp(0, navigationItems.length - 1);
                    final railSelectedIndex = (effectiveIndex >= 0 &&
                            effectiveIndex < primaryItems.length)
                        ? effectiveIndex
                        : null;
                    final indicatorColor =
                        colors.primary.withValues(alpha: isDark ? 0.16 : 0.12);
                    final selectedLabelTextStyle =
                        context.textTheme.labelMedium!.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w700,
                    );
                    final unselectedLabelTextStyle =
                        context.textTheme.labelMedium!.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    );
                    final localizations = MaterialLocalizations.of(context);
                    return ScrollConfiguration(
                      behavior: HiddenBarScrollBehavior(),
                      child: NavigationRail(
                        scrollable: true,
                        backgroundColor: Colors.transparent,
                        indicatorColor: indicatorColor,
                        indicatorShape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        selectedIconTheme: IconThemeData(
                          color: colors.primary,
                        ),
                        unselectedIconTheme: IconThemeData(
                          color: colors.onSurfaceVariant,
                        ),
                        selectedLabelTextStyle: selectedLabelTextStyle,
                        unselectedLabelTextStyle: unselectedLabelTextStyle,
                        destinations: primaryItems
                            .map(
                              (e) => NavigationRailDestination(
                                icon: e.icon,
                                label: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 88),
                                  child: Text(
                                    Intl.message(e.label.name),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onDestinationSelected: (index) {
                          globalState.appController
                              .toPage(primaryItems[index].label);
                        },
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _NavigationModeToggleButton(
                              key: const ValueKey(
                                  'navigation-expert-mode-toggle'),
                              expanded: expertExpanded,
                              showLabel: true,
                              onPressed: () => toggleExpertNavigationMode(ref),
                            ),
                            for (var i = 0; i < expandedItems.length; i++)
                              _ExpertNavigationRailItem(
                                key: ValueKey(
                                  'navigation-item-${expandedItems[i].label.name}',
                                ),
                                item: expandedItems[i],
                                selected:
                                    effectiveIndex == primaryItems.length + i,
                                indicatorColor: indicatorColor,
                                selectedIconColor: colors.primary,
                                unselectedIconColor: colors.onSurfaceVariant,
                                selectedLabelStyle: selectedLabelTextStyle,
                                unselectedLabelStyle: unselectedLabelTextStyle,
                                indexLabel: localizations.tabLabel(
                                  tabIndex: primaryItems.length + i + 1,
                                  tabCount: navigationItems.length,
                                ),
                                onTap: () => globalState.appController.toPage(
                                  expandedItems[i].label,
                                ),
                              ),
                          ],
                        ),
                        extended: false,
                        selectedIndex: railSelectedIndex,
                        labelType: NavigationRailLabelType.all,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(
                height: 12,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationModeToggleButton extends StatelessWidget {
  const _NavigationModeToggleButton({
    super.key,
    required this.expanded,
    required this.showLabel,
    required this.onPressed,
  });

  final bool expanded;
  final bool showLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final labelText =
        expanded ? appLocalizations.noviceMode : appLocalizations.expertMode;
    final iconData =
        expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded;
    final colors = context.colorScheme;
    final textStyle = context.textTheme.labelLarge?.copyWith(
      color: colors.onSurfaceVariant,
    );

    return Semantics(
      container: true,
      button: true,
      toggled: expanded,
      label: labelText,
      child: Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Tooltip(
          excludeFromSemantics: true,
          message: labelText,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: ExcludeSemantics(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 32,
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest
                            .withValues(alpha: expanded ? 0.55 : 0.35),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        iconData,
                        size: 24,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (showLabel) ...[
                      const SizedBox(height: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 88),
                        child: Text(
                          labelText,
                          style: textStyle,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpertNavigationRailItem extends StatelessWidget {
  const _ExpertNavigationRailItem({
    super.key,
    required this.item,
    required this.selected,
    required this.indicatorColor,
    required this.selectedIconColor,
    required this.unselectedIconColor,
    required this.selectedLabelStyle,
    required this.unselectedLabelStyle,
    required this.indexLabel,
    required this.onTap,
  });

  final NavigationItem item;
  final bool selected;
  final Color indicatorColor;
  final Color selectedIconColor;
  final Color unselectedIconColor;
  final TextStyle selectedLabelStyle;
  final TextStyle unselectedLabelStyle;
  final String indexLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Semantics(
      container: true,
      selected: selected,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                splashColor: colors.primary.withValues(alpha: 0.12),
                hoverColor: colors.primary.withValues(alpha: 0.04),
                onTap: onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 80),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          width: 56,
                          height: 32,
                          decoration: BoxDecoration(
                            color:
                                selected ? indicatorColor : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: IconTheme(
                            data: IconThemeData(
                              size: 24,
                              color: selected
                                  ? selectedIconColor
                                  : unselectedIconColor,
                            ),
                            child: item.icon,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 88),
                          child: DefaultTextStyle.merge(
                            style: selected
                                ? selectedLabelStyle
                                : unselectedLabelStyle,
                            child: Text(
                              Intl.message(item.label.name),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Semantics(label: indexLabel),
          ],
        ),
      ),
    );
  }
}

class _CompactBrandTributeLeading extends StatelessWidget {
  const _CompactBrandTributeLeading();

  @override
  Widget build(BuildContext context) {
    final tributeSemanticsLabel =
        '${appLocalizations.appBrandName} · ${appLocalizations.brandDialogSubtitle}';
    return Center(
      child: Semantics(
        key: const ValueKey('brand-tribute-trigger'),
        container: true,
        button: true,
        label: tributeSemanticsLabel,
        child: Tooltip(
          excludeFromSemantics: true,
          message: appLocalizations.brandDialogSubtitle,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => showFreedomNetTributeDialog(context),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: ExcludeSemantics(
                child: FreedomNetBrandMark(size: 28),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationBarDefaultsM3 extends NavigationBarThemeData {
  _NavigationBarDefaultsM3(this.context)
      : super(
          height: 76.0,
          elevation: 0.0,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        );

  final BuildContext context;
  late final ColorScheme _colors = Theme.of(context).colorScheme;
  late final TextTheme _textTheme = Theme.of(context).textTheme;

  @override
  Color? get backgroundColor => _colors.surfaceDim;

  @override
  Color? get shadowColor => Colors.transparent;

  @override
  Color? get surfaceTintColor => Colors.transparent;

  @override
  WidgetStateProperty<IconThemeData?>? get iconTheme =>
      WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => IconThemeData(
                size: 24.0,
                color: states.contains(WidgetState.disabled)
                    ? _colors.onSurfaceVariant.opacity38
                    : states.contains(WidgetState.selected)
                        ? _colors.primary
                        : _colors.onSurfaceVariant,
              ));

  @override
  Color? get indicatorColor => _colors.primary.withValues(
        alpha: _colors.brightness == Brightness.dark ? 0.16 : 0.12,
      );

  @override
  ShapeBorder? get indicatorShape => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      );

  @override
  WidgetStateProperty<TextStyle?>? get labelTextStyle =>
      WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => _textTheme.labelMedium!.apply(
              overflow: TextOverflow.ellipsis,
              color: states.contains(WidgetState.disabled)
                  ? _colors.onSurfaceVariant.opacity38
                  : states.contains(WidgetState.selected)
                      ? _colors.onSurface
                      : _colors.onSurfaceVariant));
}

class HomeBackScope extends StatelessWidget {
  final Widget child;

  const HomeBackScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      return CommonPopScope(
        onPop: () async {
          final canPop = Navigator.canPop(context);
          if (canPop) {
            Navigator.pop(context);
          } else {
            await globalState.appController.handleBackOrExit();
          }
          return false;
        },
        child: child,
      );
    }
    return child;
  }
}
