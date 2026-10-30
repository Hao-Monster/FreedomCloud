part of 'overview.dart';

final DateFormat _isoDateFormatter = DateFormat('yyyy-MM-dd');

typedef _SubscriptionExpiryState = ({
  String dateStr,
  String countdownText,
  bool isExpired,
  bool isExpiringSoon,
});

_SubscriptionExpiryState? _resolveSubscriptionExpiryState(
  int rawExpire,
  DateTime now,
) {
  final expireDate = _parseSubscriptionExpireLocal(rawExpire);
  if (expireDate == null) return null;
  final dateStr = _isoDateFormatter.format(expireDate);
  final diff = expireDate.difference(now);
  final isExpired = !expireDate.isAfter(now);
  if (isExpired) {
    return (
      dateStr: dateStr,
      countdownText: appLocalizations.nodeOverviewStatusExpired,
      isExpired: true,
      isExpiringSoon: false,
    );
  }
  final isExpiringSoon = diff.inDays <= 7;
  final String countdown;
  if (diff.inDays >= 1) {
    countdown = appLocalizations.nodeOverviewExpireDaysLeft(diff.inDays);
  } else if (diff.inHours >= 1) {
    countdown = appLocalizations.nodeOverviewExpireHoursLeft(diff.inHours);
  } else {
    countdown = appLocalizations.nodeOverviewExpireSoon;
  }
  return (
    dateStr: dateStr,
    countdownText: countdown,
    isExpired: false,
    isExpiringSoon: isExpiringSoon,
  );
}

enum _PickerExpiryTone {
  normal,
  perpetual,
  warning,
  expired,
  local,
}

typedef _ProfilePickerItemData = ({
  String id,
  String label,
  bool isActive,
  bool isUpdating,
  bool isLoaded,
  int availableCount,
  int totalCount,
  bool hasUnresolvedProviders,
  String? statusIssue,
  String? expiryLabel,
  _PickerExpiryTone? expiryTone,
});

typedef _PickerNodeStats = ({
  bool isLoaded,
  int availableCount,
  int totalCount,
  bool hasUnresolvedProviders,
  String? statusIssue,
});

(String?, _PickerExpiryTone?) _resolvePickerExpiry(
  Profile profile,
  DateTime now,
) {
  final sub = _hasMeaningfulSubscriptionInfo(profile.subscriptionInfo)
      ? profile.subscriptionInfo
      : null;
  if (sub != null) {
    final expiry = _resolveSubscriptionExpiryState(sub.expire, now);
    if (expiry == null) {
      return (
        appLocalizations.nodeOverviewPickerPerpetual,
        _PickerExpiryTone.perpetual,
      );
    }
    final dateLabel =
        appLocalizations.nodeOverviewPickerExpireDate(expiry.dateStr);
    return (
      '$dateLabel · ${expiry.countdownText}',
      expiry.isExpired
          ? _PickerExpiryTone.expired
          : expiry.isExpiringSoon
              ? _PickerExpiryTone.warning
              : _PickerExpiryTone.normal,
    );
  }
  if (profile.url.isEmpty) {
    return (
      appLocalizations.nodeOverviewLocalProfile,
      _PickerExpiryTone.local,
    );
  }
  return (null, null);
}

String _parseFailureMessageFor(String? errorSummary) =>
    errorSummary == 'tooManyNodes'
        ? appLocalizations.nodeOverviewTooManyNodes
        : appLocalizations.nodeOverviewParseFailed;

_PickerNodeStats _resolveStaticPickerStats({
  required bool loadedHasError,
  required ProfileCatalog? catalog,
  required _IndexedProfileCountrySummary? validIndexed,
  required Map<String, NodeHealthRecord> health,
}) {
  if (catalog != null) {
    if (catalog.status == ProfileCatalogStatus.loading) {
      return (
        isLoaded: false,
        availableCount: 0,
        totalCount: 0,
        hasUnresolvedProviders: false,
        statusIssue: null,
      );
    }
    if (catalog.status == ProfileCatalogStatus.fileMissing) {
      return (
        isLoaded: true,
        availableCount: 0,
        totalCount: 0,
        hasUnresolvedProviders: false,
        statusIssue: appLocalizations.nodeOverviewFileMissing,
      );
    }
    if (catalog.status == ProfileCatalogStatus.parseFailed) {
      return (
        isLoaded: true,
        availableCount: 0,
        totalCount: 0,
        hasUnresolvedProviders: false,
        statusIssue: _parseFailureMessageFor(catalog.errorSummary),
      );
    }
    var available = 0;
    var total = 0;
    for (final node in catalog.nodes) {
      if (node.unsupported == CatalogUnsupportedReason.parseFailed) continue;
      total++;
      if ((_nodeHealth(node, health)?.delayMs ?? -1) > 0) {
        available++;
      }
    }
    return (
      isLoaded: true,
      availableCount: available,
      totalCount: total,
      hasUnresolvedProviders:
          catalog.providerNodeCounts.values.any((count) => count < 0),
      statusIssue: null,
    );
  }

  if (validIndexed != null) {
    if (validIndexed.status == ProfileCatalogStatus.loading) {
      return (
        isLoaded: false,
        availableCount: 0,
        totalCount: 0,
        hasUnresolvedProviders: false,
        statusIssue: null,
      );
    }
    if (validIndexed.status == ProfileCatalogStatus.fileMissing) {
      return (
        isLoaded: true,
        availableCount: 0,
        totalCount: 0,
        hasUnresolvedProviders: false,
        statusIssue: appLocalizations.nodeOverviewFileMissing,
      );
    }
    if (validIndexed.status == ProfileCatalogStatus.parseFailed) {
      return (
        isLoaded: true,
        availableCount: 0,
        totalCount: 0,
        hasUnresolvedProviders: false,
        statusIssue: _parseFailureMessageFor(validIndexed.errorSummary),
      );
    }
    var available = 0;
    var total = 0;
    for (final node in validIndexed.nodes) {
      if (node.parseFailed) continue;
      total++;
      if ((health[node.identityKey]?.delayMs ?? -1) > 0) {
        available++;
      }
    }
    return (
      isLoaded: true,
      availableCount: available,
      totalCount: total,
      hasUnresolvedProviders: validIndexed.hasUnresolvedProviders,
      statusIssue: null,
    );
  }

  if (loadedHasError) {
    return (
      isLoaded: true,
      availableCount: 0,
      totalCount: 0,
      hasUnresolvedProviders: false,
      statusIssue: appLocalizations.nodeOverviewParseFailed,
    );
  }

  return (
    isLoaded: false,
    availableCount: 0,
    totalCount: 0,
    hasUnresolvedProviders: false,
    statusIssue: null,
  );
}

List<_ProfilePickerItemData> _buildNarrowPickerItems({
  required List<Profile> orderedProfiles,
  required String? activeId,
  required bool Function(Profile) isLiveActive,
  required Map<String, int> activeDisplayCounts,
  required Map<String, int> availableCounts,
  required Map<String, ProfileCatalog?> resolvedCatalogs,
  required Map<String, _IndexedProfileCountrySummary> indexedProfiles,
  required Script? currentScript,
  required Map<String, Map<String, NodeHealthRecord>> healthByProfile,
  required Set<String> loadErrorIds,
  required DateTime now,
}) =>
    [
      for (final profile in orderedProfiles)
        () {
          final live = isLiveActive(profile);
          final activeDisplayCount = activeDisplayCounts[profile.id] ?? 0;
          final indexed = indexedProfiles[profile.id];
          final validIndexed =
              indexed != null && indexed.matchesProfile(profile, currentScript)
                  ? indexed
                  : null;
          final _PickerNodeStats stats;
          if (live && activeDisplayCount > 0) {
            stats = (
              isLoaded: true,
              availableCount: availableCounts[profile.id] ?? 0,
              totalCount: activeDisplayCount,
              hasUnresolvedProviders: false,
              statusIssue: null,
            );
          } else {
            stats = _resolveStaticPickerStats(
              loadedHasError: loadErrorIds.contains(profile.id),
              catalog: profile.isUpdating ? null : resolvedCatalogs[profile.id],
              validIndexed: profile.isUpdating ? null : validIndexed,
              health: healthByProfile[profile.id] ?? const {},
            );
          }
          final (expiryLabel, expiryTone) = _resolvePickerExpiry(profile, now);
          return (
            id: profile.id,
            label: profile.label ?? profile.id,
            isActive: profile.id == activeId,
            isUpdating: profile.isUpdating,
            isLoaded: stats.isLoaded,
            availableCount: stats.availableCount,
            totalCount: stats.totalCount,
            hasUnresolvedProviders: stats.hasUnresolvedProviders,
            statusIssue: stats.statusIssue,
            expiryLabel: expiryLabel,
            expiryTone: expiryTone,
          );
        }(),
    ];

class _OverviewProfileSelector extends StatefulWidget {
  const _OverviewProfileSelector({
    required this.buttonKey,
    required this.selectedProfileId,
    required this.maxTriggerWidth,
    required this.items,
    required this.onChanged,
  });

  final Key buttonKey;
  final String? selectedProfileId;
  final double maxTriggerWidth;
  final List<_ProfilePickerItemData> items;
  final ValueChanged<String?> onChanged;

  @override
  State<_OverviewProfileSelector> createState() =>
      _OverviewProfileSelectorState();
}

class _OverviewProfileSelectorState extends State<_OverviewProfileSelector> {
  final MenuController _controller = MenuController();
  final FocusNode _triggerFocusNode = FocusNode(
    debugLabel: 'OverviewProfileSelectorTrigger',
  );
  bool _hovered = false;
  bool _focused = false;
  bool _isOpen = false;

  @override
  void dispose() {
    _triggerFocusNode.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    if (_controller.isOpen) {
      _controller.close();
    } else {
      _controller.open();
    }
  }

  static Color _statusDotColorFor(
    _ProfilePickerItemData item,
    ColorScheme colors, {
    required bool isDark,
  }) {
    if (item.expiryTone == _PickerExpiryTone.expired ||
        item.statusIssue != null) {
      return colors.error;
    }
    if (item.availableCount > 0) {
      return isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
    }
    if (item.expiryTone == _PickerExpiryTone.warning) {
      return isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    }
    return colors.outline;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final viewportWidth = MediaQuery.sizeOf(context).width;

    _ProfilePickerItemData? selectedItem;
    var allAvailable = 0;
    var allTotal = 0;
    var loadedHealthyCount = 0;
    var pendingCount = 0;
    var anyUnresolvedProviders = false;
    for (final item in widget.items) {
      if (item.id == widget.selectedProfileId) {
        selectedItem = item;
      }
      if (!item.isLoaded) {
        pendingCount++;
      } else if (item.statusIssue == null) {
        loadedHealthyCount++;
        allAvailable += item.availableCount;
        allTotal += item.totalCount;
        if (item.hasUnresolvedProviders) {
          anyUnresolvedProviders = true;
        }
      }
    }

    final isFiltered = selectedItem != null;
    final triggerLabel =
        selectedItem?.label ?? appLocalizations.nodeOverviewAllProfiles;
    final borderRadius = BorderRadius.circular(10);
    final inkBorderRadius = BorderRadius.circular(9);

    final backgroundColor = _isOpen
        ? colors.surfaceContainerHighest.withValues(
            alpha: isDark ? 0.86 : 0.96,
          )
        : isFiltered
            ? colors.primary.withValues(
                alpha: _hovered
                    ? (isDark ? 0.19 : 0.13)
                    : (isDark ? 0.13 : 0.09),
              )
            : _hovered
                ? colors.surfaceContainerHighest.withValues(
                    alpha: isDark ? 0.68 : 0.88,
                  )
                : colors.surfaceContainerHigh.withValues(
                    alpha: isDark ? 0.45 : 0.65,
                  );
    final borderColor = _isOpen || _focused
        ? colors.primary.withValues(alpha: 0.72)
        : isFiltered
            ? colors.primary.withValues(alpha: _hovered ? 0.62 : 0.45)
            : _hovered
                ? colors.outline.withValues(alpha: 0.55)
                : colors.outlineVariant.withValues(alpha: 0.60);
    final labelColor =
        isFiltered ? colors.primary : colors.onSurface.withValues(alpha: 0.92);
    final accentIconColor =
        isFiltered || _isOpen ? colors.primary : colors.onSurfaceVariant;

    final panelWidth = math
        .min(
          math.max(216.0, viewportWidth - 24.0),
          math.max(348.0, (324.0 * textScale).ceilToDouble()),
        )
        .clamp(216.0, 420.0);
    final innerWidth = math.max(196.0, panelWidth - 16.0);
    final triggerMaxWidth = math.min(
      widget.maxTriggerWidth,
      math.max(256.0, (236.0 * textScale).ceilToDouble()),
    );
    final showInlineTriggerCount = selectedItem != null &&
        selectedItem.isLoaded &&
        selectedItem.statusIssue == null &&
        !(selectedItem.hasUnresolvedProviders && selectedItem.totalCount == 0) &&
        triggerMaxWidth >= 232 &&
        textScale <= 1.45;
    final inlineTriggerCountSuffix =
        (selectedItem?.hasUnresolvedProviders ?? false) ? '+' : '';

    return MenuAnchor(
      controller: _controller,
      childFocusNode: _triggerFocusNode,
      alignmentOffset: const Offset(0, 8),
      onOpen: () {
        if (mounted && !_isOpen) setState(() => _isOpen = true);
      },
      onClose: () {
        if (mounted && _isOpen) setState(() => _isOpen = false);
      },
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(isDark ? 10 : 6),
        shadowColor: WidgetStatePropertyAll(
          Colors.black.withValues(alpha: isDark ? 0.48 : 0.18),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        minimumSize: const WidgetStatePropertyAll(Size.zero),
        visualDensity: VisualDensity.compact,
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: colors.outlineVariant.withValues(
                alpha: isDark ? 0.68 : 0.78,
              ),
            ),
          ),
        ),
      ),
      menuChildren: [
        Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
            SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
          },
          child: FocusTraversalGroup(
            policy: WidgetOrderTraversalPolicy(),
            child: Padding(
              key: const ValueKey('overview-profile-menu'),
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: innerWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.layers_outlined,
                            size: 14,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              appLocalizations.nodeOverviewSelectProfileTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colors.onSurfaceVariant,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: innerWidth * 0.44),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerHighest.withValues(
                                  alpha: isDark ? 0.72 : 0.90,
                                ),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: colors.outlineVariant
                                      .withValues(alpha: 0.50),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                appLocalizations.nodeOverviewProfileCountBadge(
                                  widget.items.length,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 10.5,
                                  height: 1.2,
                                  color: colors.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _OverviewAllProfilesOptionCard(
                      key: const ValueKey('overview-profile-option-all'),
                      selected: !isFiltered,
                      hasLoadedNodes: loadedHealthyCount > 0,
                      isPartiallyLoaded:
                          pendingCount > 0 || anyUnresolvedProviders,
                      availableCount: allAvailable,
                      totalCount: allTotal,
                      maxContentWidth: innerWidth - 20,
                      onTap: () {
                        _controller.close();
                        if (widget.selectedProfileId != null) {
                          widget.onChanged(null);
                        }
                      },
                    ),
                    if (widget.items.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 6,
                        ),
                        child: Divider(
                          height: 1,
                          thickness: 0.6,
                          color: colors.outlineVariant.withValues(alpha: 0.55),
                        ),
                      ),
                    for (var i = 0; i < widget.items.length; i++) ...[
                      if (i > 0) const SizedBox(height: 5),
                      _OverviewProfileOptionCard(
                        key: ValueKey(
                          'overview-profile-option-${widget.items[i].id}',
                        ),
                        item: widget.items[i],
                        selected:
                            widget.items[i].id == widget.selectedProfileId,
                        maxContentWidth: innerWidth - 20,
                        onTap: () {
                          final targetId = widget.items[i].id;
                          _controller.close();
                          if (targetId != widget.selectedProfileId) {
                            widget.onChanged(targetId);
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
      child: Semantics(
        button: true,
        expanded: _isOpen,
        excludeSemantics: true,
        onTap: _toggleMenu,
        label:
            '${appLocalizations.nodeOverviewSelectProfileTitle}: $triggerLabel',
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: triggerMaxWidth),
            child: AnimatedContainer(
              key: widget.buttonKey,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 36),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: borderRadius,
                border: Border.all(color: borderColor),
                boxShadow: _isOpen
                    ? [
                        BoxShadow(
                          color: colors.primary.withValues(
                            alpha: isDark ? 0.16 : 0.08,
                          ),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : const [],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  focusNode: _triggerFocusNode,
                  borderRadius: inkBorderRadius,
                  hoverColor: Colors.transparent,
                  focusColor: Colors.transparent,
                  splashColor: colors.primary.withValues(alpha: 0.10),
                  highlightColor: colors.primary.withValues(alpha: 0.06),
                  onFocusChange: (value) {
                    if (mounted && _focused != value) {
                      setState(() => _focused = value);
                    }
                  },
                  onTap: _toggleMenu,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (selectedItem != null)
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _statusDotColorFor(
                                selectedItem,
                                colors,
                                isDark: isDark,
                              ),
                            ),
                          )
                        else
                          Icon(
                            Icons.layers_rounded,
                            size: 15,
                            color: accentIconColor,
                          ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            triggerLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.2,
                              fontWeight: isFiltered
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              letterSpacing: 0.1,
                              color: labelColor,
                            ),
                          ),
                        ),
                        if (showInlineTriggerCount) ...[
                          Container(
                            width: 1,
                            height: 11,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            color:
                                colors.outlineVariant.withValues(alpha: 0.65),
                          ),
                          Text(
                            '${selectedItem.availableCount}/${selectedItem.totalCount}$inlineTriggerCountSuffix',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                              color: selectedItem.availableCount > 0
                                  ? (isDark
                                      ? const Color(0xFF4ADE80)
                                      : const Color(0xFF15803D))
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: _isOpen ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: accentIconColor,
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
      ),
    );
  }
}

class _PickerOptionCardShell extends StatefulWidget {
  const _PickerOptionCardShell({
    required this.selected,
    required this.semanticLabel,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final String semanticLabel;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_PickerOptionCardShell> createState() => _PickerOptionCardShellState();
}

class _PickerOptionCardShellState extends State<_PickerOptionCardShell> {
  bool _hovered = false;
  bool _focused = false;

  void _handleFocusChange(bool value) {
    if (!mounted) return;
    if (_focused != value) {
      setState(() => _focused = value);
    }
    if (value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.maybeOf(context)?.position.ensureVisible(
              context.findRenderObject()!,
              alignmentPolicy:
                  ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
            );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final selected = widget.selected;
    final borderRadius = BorderRadius.circular(11);

    final backgroundColor = selected
        ? colors.primary.withValues(
            alpha: _hovered ? (isDark ? 0.22 : 0.15) : (isDark ? 0.15 : 0.10),
          )
        : _hovered
            ? colors.surfaceContainerHighest.withValues(
                alpha: isDark ? 0.72 : 0.88,
              )
            : colors.surface.withValues(alpha: isDark ? 0.34 : 0.52);
    final borderColor = _focused
        ? colors.primary.withValues(alpha: isDark ? 0.78 : 0.68)
        : selected
            ? colors.primary.withValues(alpha: isDark ? 0.48 : 0.38)
            : _hovered
                ? colors.outlineVariant.withValues(alpha: 0.75)
                : colors.outlineVariant.withValues(alpha: isDark ? 0.34 : 0.44);

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: widget.semanticLabel,
      onTap: widget.onTap,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: borderRadius,
            border: Border.all(
              color: borderColor,
              width: _focused && !selected ? 1.1 : 0.9,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              autofocus: selected,
              borderRadius: borderRadius,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              splashColor: colors.primary.withValues(alpha: 0.10),
              highlightColor: colors.primary.withValues(alpha: 0.06),
              onFocusChange: _handleFocusChange,
              onTap: widget.onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8.5),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverviewAllProfilesOptionCard extends StatelessWidget {
  const _OverviewAllProfilesOptionCard({
    super.key,
    required this.selected,
    required this.hasLoadedNodes,
    required this.isPartiallyLoaded,
    required this.availableCount,
    required this.totalCount,
    required this.maxContentWidth,
    required this.onTap,
  });

  final bool selected;
  final bool hasLoadedNodes;
  final bool isPartiallyLoaded;
  final int availableCount;
  final int totalCount;
  final double maxContentWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final titleColor =
        selected ? colors.primary : colors.onSurface.withValues(alpha: 0.94);

    final String? summaryText;
    final IconData summaryIcon;
    final bool highlightGreen;
    if (hasLoadedNodes) {
      final base = appLocalizations.nodeOverviewPickerAvailableNodes(
        availableCount,
        totalCount,
      );
      summaryText = isPartiallyLoaded ? '$base+' : base;
      highlightGreen = availableCount > 0;
      summaryIcon = highlightGreen
          ? Icons.bolt_rounded
          : Icons.radio_button_unchecked_rounded;
    } else if (isPartiallyLoaded) {
      summaryText = '—';
      highlightGreen = false;
      summaryIcon = Icons.hourglass_empty_rounded;
    } else {
      summaryText = null;
      highlightGreen = false;
      summaryIcon = Icons.radio_button_unchecked_rounded;
    }

    final semanticLabel = [
      appLocalizations.nodeOverviewAllProfiles,
      if (summaryText != null) summaryText,
    ].join(', ');

    return _PickerOptionCardShell(
      selected: selected,
      semanticLabel: semanticLabel,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: selected
                  ? colors.primary.withValues(alpha: isDark ? 0.22 : 0.14)
                  : colors.surfaceContainerHighest.withValues(
                      alpha: isDark ? 0.70 : 0.85,
                    ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.layers_rounded,
              size: 15,
              color: selected ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  appLocalizations.nodeOverviewAllProfiles,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.25,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: titleColor,
                  ),
                ),
                if (summaryText != null) ...[
                  const SizedBox(height: 4),
                  _PickerMetaPill(
                    icon: summaryIcon,
                    label: summaryText,
                    foreground: highlightGreen
                        ? (isDark
                            ? const Color(0xFF4ADE80)
                            : const Color(0xFF15803D))
                        : colors.onSurfaceVariant,
                    background: highlightGreen
                        ? Colors.green.withValues(alpha: isDark ? 0.15 : 0.10)
                        : colors.surfaceContainerHighest.withValues(
                            alpha: isDark ? 0.58 : 0.75,
                          ),
                    border: highlightGreen
                        ? Colors.green.withValues(alpha: isDark ? 0.34 : 0.28)
                        : colors.outlineVariant.withValues(alpha: 0.48),
                    maxWidth: math.max(120.0, maxContentWidth - 48.0),
                  ),
                ],
              ],
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.check_circle_rounded,
              size: 16,
              color: colors.primary,
            ),
          ],
        ],
      ),
    );
  }
}

class _OverviewProfileOptionCard extends StatelessWidget {
  const _OverviewProfileOptionCard({
    super.key,
    required this.item,
    required this.selected,
    required this.maxContentWidth,
    required this.onTap,
  });

  final _ProfilePickerItemData item;
  final bool selected;
  final double maxContentWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final titleColor =
        selected ? colors.primary : colors.onSurface.withValues(alpha: 0.94);

    final dotColor = _OverviewProfileSelectorState._statusDotColorFor(
      item,
      colors,
      isDark: isDark,
    );
    final maxPillWidth = math.max(120.0, maxContentWidth - 16.0);

    final Widget availabilityPill;
    final String availabilitySemantic;
    if (item.statusIssue != null) {
      availabilitySemantic = item.statusIssue!;
      availabilityPill = _PickerMetaPill(
        icon: Icons.warning_amber_rounded,
        label: item.statusIssue!,
        foreground: colors.error,
        background: colors.error.withValues(alpha: isDark ? 0.15 : 0.10),
        border: colors.error.withValues(alpha: 0.34),
        maxWidth: maxPillWidth,
      );
    } else if (!item.isLoaded) {
      availabilitySemantic = '—';
      availabilityPill = _PickerMetaPill(
        icon: Icons.hourglass_empty_rounded,
        label: '—',
        foreground: colors.onSurfaceVariant,
        background: colors.surfaceContainerHighest.withValues(
          alpha: isDark ? 0.55 : 0.72,
        ),
        border: colors.outlineVariant.withValues(alpha: 0.45),
        maxWidth: maxPillWidth,
      );
    } else if (item.hasUnresolvedProviders && item.totalCount == 0) {
      availabilitySemantic = appLocalizations.nodeOverviewPartialSummary;
      availabilityPill = _PickerMetaPill(
        icon: Icons.info_outline_rounded,
        label: availabilitySemantic,
        foreground: colors.onSurfaceVariant,
        background: colors.surfaceContainerHighest.withValues(
          alpha: isDark ? 0.58 : 0.75,
        ),
        border: colors.outlineVariant.withValues(alpha: 0.48),
        maxWidth: maxPillWidth,
      );
    } else {
      final hasAvailable = item.availableCount > 0;
      final base = appLocalizations.nodeOverviewPickerAvailableNodes(
        item.availableCount,
        item.totalCount,
      );
      availabilitySemantic = item.hasUnresolvedProviders ? '$base+' : base;
      availabilityPill = _PickerMetaPill(
        icon: hasAvailable
            ? Icons.bolt_rounded
            : Icons.radio_button_unchecked_rounded,
        label: availabilitySemantic,
        foreground: hasAvailable
            ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D))
            : colors.onSurfaceVariant,
        background: hasAvailable
            ? Colors.green.withValues(alpha: isDark ? 0.15 : 0.10)
            : colors.surfaceContainerHighest.withValues(
                alpha: isDark ? 0.58 : 0.75,
              ),
        border: hasAvailable
            ? Colors.green.withValues(alpha: isDark ? 0.34 : 0.28)
            : colors.outlineVariant.withValues(alpha: 0.48),
        maxWidth: maxPillWidth,
      );
    }

    Widget? expiryPill;
    if (item.expiryLabel != null && item.expiryTone != null) {
      final (icon, fg, bg, border) = switch (item.expiryTone!) {
        _PickerExpiryTone.expired => (
            Icons.event_busy_outlined,
            colors.error,
            colors.error.withValues(alpha: isDark ? 0.15 : 0.10),
            colors.error.withValues(alpha: 0.34),
          ),
        _PickerExpiryTone.warning => (
            Icons.schedule_rounded,
            isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
            Colors.orange.withValues(alpha: isDark ? 0.15 : 0.11),
            Colors.orange.withValues(alpha: 0.34),
          ),
        _PickerExpiryTone.perpetual => (
            Icons.verified_outlined,
            colors.onSurfaceVariant,
            colors.surfaceContainerHighest.withValues(
              alpha: isDark ? 0.55 : 0.72,
            ),
            colors.outlineVariant.withValues(alpha: 0.46),
          ),
        _PickerExpiryTone.local => (
            Icons.description_outlined,
            colors.onSurfaceVariant,
            colors.surfaceContainerHighest.withValues(
              alpha: isDark ? 0.55 : 0.72,
            ),
            colors.outlineVariant.withValues(alpha: 0.46),
          ),
        _PickerExpiryTone.normal => (
            Icons.event_outlined,
            colors.onSurfaceVariant,
            colors.surfaceContainerHighest.withValues(
              alpha: isDark ? 0.55 : 0.72,
            ),
            colors.outlineVariant.withValues(alpha: 0.46),
          ),
      };
      expiryPill = _PickerMetaPill(
        icon: icon,
        label: item.expiryLabel!,
        foreground: fg,
        background: bg,
        border: border,
        maxWidth: maxPillWidth,
      );
    }

    final semanticLabel = [
      item.label,
      if (item.isActive) appLocalizations.nodeOverviewActive,
      availabilitySemantic,
      if (item.expiryLabel != null) item.expiryLabel!,
    ].join(', ');

    return _PickerOptionCardShell(
      selected: selected,
      semanticLabel: semanticLabel,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 6.5,
                height: 6.5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.25,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: titleColor,
                  ),
                ),
              ),
              if (item.isUpdating) ...[
                const SizedBox(width: 6),
                SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                  ),
                ),
              ],
              if (item.isActive) ...[
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.min(92.0, maxContentWidth * 0.42),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6.5,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: colors.primary.withValues(alpha: 0.36),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      appLocalizations.nodeOverviewActive,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10.5,
                        height: 1.2,
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
              if (selected) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: colors.primary,
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 14.5),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                availabilityPill,
                if (expiryPill != null) expiryPill,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerMetaPill extends StatelessWidget {
  const _PickerMetaPill({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
    required this.border,
    required this.maxWidth,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;
  final Color border;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2.5),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: border, width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11.5, color: foreground),
              const SizedBox(width: 3.5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        height: 1.2,
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
      );
}
