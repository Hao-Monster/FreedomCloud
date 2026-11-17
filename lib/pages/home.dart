import 'dart:async';
import 'dart:io';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/providers/purchase_support_provider.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/dashboard/widgets/hero_nav_bar.dart';
import 'package:flclashx/views/support/support_chat_sheet.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

typedef OnSelected = void Function(int index);

void _openGlobalSupport(BuildContext context, WidgetRef ref) {
  final coordinator = ref.read(purchaseSupportCoordinatorProvider);
  unawaited(coordinator.prepareSupport());
  final locale = Localizations.localeOf(context);
  unawaited(
    openSupportChatSheet(
      context,
      supportManager: coordinator.supportManager,
      openLink: openHttpsExternalLink,
      externalWidgetUri: coordinator.resolveExternalWidgetUri(locale),
      onRetryChannel: () => coordinator.prepareSupport(force: true),
    ),
  );
}

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
              persistentActions: viewMode == ViewMode.mobile
                  ? [
                      Builder(
                        builder: (iconContext) {
                          final isDark =
                              Theme.of(iconContext).colorScheme.brightness ==
                                  Brightness.dark;
                          return IconButton(
                            key: const ValueKey(
                                'navigation-support-trigger-mobile'),
                            tooltip: appLocalizations.supportSheetTitle,
                            onPressed: () => _openGlobalSupport(context, ref),
                            icon: Icon(
                              Icons.support_agent_rounded,
                              color: isDark
                                  ? _YouthfulNavPalette.support.darkFg
                                  : _YouthfulNavPalette.support.lightFg,
                            ),
                          );
                        },
                      ),
                    ]
                  : null,
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
        unawaited(_toPage(next));
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
    unawaited(_toPage(pageLabel, true));
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
  const CommonNavigationBar({
    super.key,
    required this.viewMode,
    required this.navigationItems,
    required this.currentIndex,
  });

  final ViewMode viewMode;
  final List<NavigationItem> navigationItems;
  final int currentIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expertExpanded = ref.watch(expertNavigationExpandedProvider);
    if (viewMode == ViewMode.mobile) {
      final toggleLabel =
          expertExpanded ? appLocalizations.noviceMode : appLocalizations.expertMode;
      final toggleIcon = Icon(
        expertExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
      );
      final togglePalette = _YouthfulNavPalette.toggle(expanded: expertExpanded);
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
                (e) {
                  final palette = _YouthfulNavPalette.forPageLabel(e.label);
                  return NavigationDestination(
                    icon: _YouthfulNavIconBadge(
                      icon: e.icon,
                      palette: palette,
                      selected: false,
                      compact: true,
                    ),
                    selectedIcon: _YouthfulNavIconBadge(
                      icon: e.icon,
                      palette: palette,
                      selected: true,
                      compact: true,
                    ),
                    label: Intl.message(e.label.name),
                  );
                },
              ),
              NavigationDestination(
                key: const ValueKey('navigation-expert-mode-toggle'),
                icon: _YouthfulNavIconBadge(
                  icon: toggleIcon,
                  palette: togglePalette,
                  selected: false,
                  compact: true,
                ),
                selectedIcon: _YouthfulNavIconBadge(
                  icon: toggleIcon,
                  palette: togglePalette,
                  selected: true,
                  compact: true,
                ),
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
    final isPureBlack = isDark && colors.surface == Colors.black;
    final panelGradientColors = isDark
        ? (isPureBlack
            ? const [
                Color(0xFF061116),
                Color(0xFF070D1A),
                Color(0xFF0E091A),
              ]
            : const [
                Color(0xFF0D2229),
                Color(0xFF101B33),
                Color(0xFF1A1433),
              ])
        : const [
            Color(0xFFE4FAF4),
            Color(0xFFEAF2FF),
            Color(0xFFF3E8FF),
          ];
    final railBorderColor = isDark
        ? const Color(0xFF818CF8).withValues(alpha: 0.18)
        : const Color(0xFF6366F1).withValues(alpha: 0.14);
    final dividerGradient = LinearGradient(
      colors: [
        Colors.transparent,
        (isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1))
            .withValues(alpha: isDark ? 0.34 : 0.24),
        Colors.transparent,
      ],
    );
    final tributeSemanticsLabel =
        '$brandDisplayName · ${appLocalizations.brandDialogSubtitle}';
    return Material(
      type: MaterialType.transparency,
      // SafeArea: the app draws edge-to-edge, so on tablets/foldables (which
      // also get the desktop-style side rail) the status bar overlapped the
      // logo. Shifts the whole logo+rail block below the system inset; no-op
      // on desktop OSes.
      child: DecoratedBox(
        key: const ValueKey('desktop-navigation-rail-panel'),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.52, 1.0],
            colors: panelGradientColors,
          ),
          border: Border(
            right: BorderSide(color: railBorderColor),
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
                        borderRadius: BorderRadius.circular(14),
                        splashColor:
                            const Color(0xFF10B981).withValues(alpha: 0.16),
                        hoverColor:
                            const Color(0xFF6366F1).withValues(alpha: 0.08),
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
                                    brandNameZh,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.textTheme.labelMedium
                                        ?.copyWith(
                                      color: isDark
                                          ? const Color(0xFFF8FAFC)
                                          : const Color(0xFF0F172A),
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 1),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 88),
                                  child: Text(
                                    brandNameEn,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        context.textTheme.labelSmall?.copyWith(
                                      fontSize: 9.5,
                                      color: isDark
                                          ? const Color(0xFF94A3B8)
                                          : const Color(0xFF475569),
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 56,
                  height: 1,
                  decoration: BoxDecoration(gradient: dividerGradient),
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
                    final selectedLabelTextStyle =
                        context.textTheme.labelMedium!.copyWith(
                      color: isDark
                          ? const Color(0xFFF8FAFC)
                          : const Color(0xFF0F172A),
                      fontWeight: FontWeight.w700,
                    );
                    final unselectedLabelTextStyle =
                        context.textTheme.labelMedium!.copyWith(
                      color: isDark
                          ? const Color(0xFFCBD5E1)
                          : const Color(0xFF334155),
                      fontWeight: FontWeight.w600,
                    );
                    final localizations = MaterialLocalizations.of(context);
                    return ScrollConfiguration(
                      behavior: HiddenBarScrollBehavior(),
                      child: NavigationRail(
                        scrollable: true,
                        backgroundColor: Colors.transparent,
                        useIndicator: false,
                        selectedLabelTextStyle: selectedLabelTextStyle,
                        unselectedLabelTextStyle: unselectedLabelTextStyle,
                        destinations: List<NavigationRailDestination>.generate(
                          primaryItems.length,
                          (i) {
                            final item = primaryItems[i];
                            final palette =
                                _YouthfulNavPalette.forPageLabel(item.label);
                            final isSelected = railSelectedIndex == i;
                            return NavigationRailDestination(
                              icon: _YouthfulNavIconBadge(
                                key: ValueKey('nav-badge-${item.label.name}'),
                                icon: item.icon,
                                palette: palette,
                                selected: false,
                              ),
                              selectedIcon: _YouthfulNavIconBadge(
                                key: ValueKey('nav-badge-${item.label.name}'),
                                icon: item.icon,
                                palette: palette,
                                selected: true,
                              ),
                              label: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 88),
                                child: Text(
                                  Intl.message(item.label.name),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: isSelected
                                      ? TextStyle(
                                          color: isDark
                                              ? palette.darkFg
                                              : palette.selectedTextLight,
                                          fontWeight: FontWeight.w700,
                                        )
                                      : null,
                                ),
                              ),
                            );
                          },
                        ),
                        onDestinationSelected: (index) {
                          globalState.appController
                              .toPage(primaryItems[index].label);
                        },
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _NavigationSupportRailButton(
                              key: const ValueKey('navigation-support-trigger'),
                              labelStyle: unselectedLabelTextStyle,
                              onTap: () => _openGlobalSupport(context, ref),
                            ),
                            for (var i = 0; i < expandedItems.length; i++)
                              _ExpertNavigationRailItem(
                                key: ValueKey(
                                  'navigation-item-${expandedItems[i].label.name}',
                                ),
                                item: expandedItems[i],
                                selected:
                                    effectiveIndex == primaryItems.length + i,
                                palette: _YouthfulNavPalette.forPageLabel(
                                  expandedItems[i].label,
                                ),
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
              Container(
                width: 56,
                height: 1,
                decoration: BoxDecoration(gradient: dividerGradient),
              ),
              _NavigationModeToggleButton(
                key: const ValueKey('navigation-expert-mode-toggle'),
                expanded: expertExpanded,
                onPressed: () => toggleExpertNavigationMode(ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _YouthfulNavPalette {
  const _YouthfulNavPalette({
    required this.gradient,
    required this.lightFg,
    required this.darkFg,
    required this.selectedTextLight,
  });

  final List<Color> gradient;
  final Color lightFg;
  final Color darkFg;
  final Color selectedTextLight;

  static const proxies = _YouthfulNavPalette(
    gradient: [Color(0xFF00C6FF), Color(0xFF2563EB)],
    lightFg: Color(0xFF0284C7),
    darkFg: Color(0xFF38BDF8),
    selectedTextLight: Color(0xFF1D4ED8),
  );

  static const purchase = _YouthfulNavPalette(
    gradient: [Color(0xFFFF6B8B), Color(0xFFF43F5E)],
    lightFg: Color(0xFFE11D48),
    darkFg: Color(0xFFFB7185),
    selectedTextLight: Color(0xFFBE123C),
  );

  static const support = _YouthfulNavPalette(
    gradient: [Color(0xFF10B981), Color(0xFF06B6D4)],
    lightFg: Color(0xFF059669),
    darkFg: Color(0xFF34D399),
    selectedTextLight: Color(0xFF047857),
  );

  static const dashboard = _YouthfulNavPalette(
    gradient: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
    lightFg: Color(0xFF6D28D9),
    darkFg: Color(0xFFA78BFA),
    selectedTextLight: Color(0xFF5B21B6),
  );

  static const profiles = _YouthfulNavPalette(
    gradient: [Color(0xFFFBBF24), Color(0xFFF97316)],
    lightFg: Color(0xFFD97706),
    darkFg: Color(0xFFFBBF24),
    selectedTextLight: Color(0xFFB45309),
  );

  static const connections = _YouthfulNavPalette(
    gradient: [Color(0xFF22D3EE), Color(0xFF0284C7)],
    lightFg: Color(0xFF0891B2),
    darkFg: Color(0xFF22D3EE),
    selectedTextLight: Color(0xFF0E7490),
  );

  static const logs = _YouthfulNavPalette(
    gradient: [Color(0xFF34D399), Color(0xFF16A34A)],
    lightFg: Color(0xFF15803D),
    darkFg: Color(0xFF4ADE80),
    selectedTextLight: Color(0xFF166534),
  );

  static const tools = _YouthfulNavPalette(
    gradient: [Color(0xFFEC4899), Color(0xFFA855F7)],
    lightFg: Color(0xFFBE185D),
    darkFg: Color(0xFFF472B6),
    selectedTextLight: Color(0xFF9D174D),
  );

  static _YouthfulNavPalette toggle({required bool expanded}) =>
      expanded ? support : dashboard;

  static _YouthfulNavPalette forPageLabel(PageLabel label) => switch (label) {
        PageLabel.proxies => proxies,
        PageLabel.purchase => purchase,
        PageLabel.dashboard => dashboard,
        PageLabel.profiles => profiles,
        PageLabel.connections || PageLabel.requests => connections,
        PageLabel.logs => logs,
        PageLabel.tools || PageLabel.resources => tools,
      };
}

class _YouthfulNavIconBadge extends StatelessWidget {
  const _YouthfulNavIconBadge({
    super.key,
    required this.icon,
    required this.palette,
    required this.selected,
    this.compact = false,
  });

  final Widget icon;
  final _YouthfulNavPalette palette;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    final fillColors = selected
        ? palette.gradient
        : [
            palette.gradient[0].withValues(alpha: isDark ? 0.22 : 0.17),
            palette.gradient[1].withValues(alpha: isDark ? 0.14 : 0.11),
          ];
    final borderColor = selected
        ? Colors.white.withValues(alpha: isDark ? 0.24 : 0.38)
        : palette.gradient[0].withValues(alpha: isDark ? 0.34 : 0.26);
    final fgColor = selected
        ? Colors.white
        : (isDark ? palette.darkFg : palette.lightFg);
    final width = compact ? 42.0 : 46.0;
    final height = compact ? 30.0 : 34.0;
    final radius = compact ? 11.0 : 13.0;
    final iconSize =
        selected ? (compact ? 20.0 : 22.0) : (compact ? 19.0 : 21.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: fillColors,
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: (selected ? palette.gradient[1] : palette.gradient[0])
                .withValues(
              alpha: selected ? (isDark ? 0.45 : 0.34) : (isDark ? 0.12 : 0.08),
            ),
            blurRadius: selected ? 12 : 6,
            offset: Offset(0, selected ? 4 : 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: IconTheme(
        data: IconThemeData(
          size: iconSize,
          color: fgColor,
        ),
        child: icon,
      ),
    );
  }
}

class _NavigationModeToggleButton extends StatelessWidget {
  const _NavigationModeToggleButton({
    super.key,
    required this.expanded,
    required this.onPressed,
  });

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final labelText =
        expanded ? appLocalizations.noviceMode : appLocalizations.expertMode;
    final colors = context.colorScheme;
    final isDark = colors.brightness == Brightness.dark;
    final gradientColors = expanded
        ? const [Color(0xFF0EA5E9), Color(0xFF10B981)]
        : const [Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFFD946EF)];
    final shadowColor =
        expanded ? const Color(0xFF10B981) : const Color(0xFF8B5CF6);
    final textStyle = context.textTheme.labelMedium?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    );

    return Semantics(
      container: true,
      button: true,
      toggled: expanded,
      label: labelText,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
        child: Tooltip(
          excludeFromSemantics: true,
          message: labelText,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors,
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: Colors.white.withValues(alpha: isDark ? 0.22 : 0.38),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: shadowColor.withValues(alpha: isDark ? 0.36 : 0.28),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Material(
              type: MaterialType.transparency,
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                splashColor: Colors.white.withValues(alpha: 0.24),
                hoverColor: Colors.white.withValues(alpha: 0.12),
                onTap: onPressed,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 68,
                    maxWidth: 88,
                    minHeight: 32,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: ExcludeSemantics(
                      child: Center(
                        widthFactor: 1.0,
                        heightFactor: 1.0,
                        child: Text(
                          labelText,
                          style: textStyle,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
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
    required this.palette,
    required this.selectedLabelStyle,
    required this.unselectedLabelStyle,
    required this.indexLabel,
    required this.onTap,
  });

  final NavigationItem item;
  final bool selected;
  final _YouthfulNavPalette palette;
  final TextStyle selectedLabelStyle;
  final TextStyle unselectedLabelStyle;
  final String indexLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final isDark = colors.brightness == Brightness.dark;
    final effectiveLabelStyle = selected
        ? selectedLabelStyle.copyWith(
            color: isDark ? palette.darkFg : palette.selectedTextLight,
            fontWeight: FontWeight.w700,
          )
        : unselectedLabelStyle;
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
                borderRadius: BorderRadius.circular(14),
                splashColor: palette.gradient[0].withValues(alpha: 0.18),
                hoverColor: palette.gradient[0].withValues(alpha: 0.08),
                onTap: onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 72),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _YouthfulNavIconBadge(
                          key: ValueKey('nav-badge-${item.label.name}'),
                          icon: item.icon,
                          palette: palette,
                          selected: selected,
                        ),
                        const SizedBox(height: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 88),
                          child: DefaultTextStyle.merge(
                            style: effectiveLabelStyle,
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

class _NavigationSupportRailButton extends StatelessWidget {
  const _NavigationSupportRailButton({
    super.key,
    required this.labelStyle,
    required this.onTap,
  });

  final TextStyle labelStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = appLocalizations.purchaseOnlineSupport;
    return Semantics(
      container: true,
      button: true,
      label: label,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            splashColor:
                _YouthfulNavPalette.support.gradient[0].withValues(alpha: 0.18),
            hoverColor:
                _YouthfulNavPalette.support.gradient[0].withValues(alpha: 0.08),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 72),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ExcludeSemantics(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _YouthfulNavIconBadge(
                        key: ValueKey('nav-badge-support'),
                        icon: Icon(Icons.support_agent_rounded),
                        palette: _YouthfulNavPalette.support,
                        selected: false,
                      ),
                      const SizedBox(height: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 88),
                        child: Text(
                          label,
                          style: labelStyle,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
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
        '$brandDisplayName · ${appLocalizations.brandDialogSubtitle}';
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
          (states) => IconThemeData(
                size: 24.0,
                color: states.contains(WidgetState.disabled)
                    ? _colors.onSurfaceVariant.opacity38
                    : states.contains(WidgetState.selected)
                        ? _colors.primary
                        : _colors.onSurfaceVariant,
              ));

  @override
  Color? get indicatorColor => Colors.transparent;

  @override
  ShapeBorder? get indicatorShape => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      );

  @override
  WidgetStateProperty<TextStyle?>? get labelTextStyle =>
      WidgetStateProperty.resolveWith(
          (states) => _textTheme.labelMedium!.apply(
              overflow: TextOverflow.ellipsis,
              color: states.contains(WidgetState.disabled)
                  ? _colors.onSurfaceVariant.opacity38
                  : states.contains(WidgetState.selected)
                      ? _colors.onSurface
                      : _colors.onSurfaceVariant));
}

class HomeBackScope extends StatelessWidget {
  const HomeBackScope({super.key, required this.child});

  final Widget child;

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
