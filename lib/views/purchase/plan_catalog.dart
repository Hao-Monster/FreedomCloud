import 'package:flclashx/common/node_country.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/views/purchase/plan_content.dart';
import 'package:flclashx/widgets/text.dart';
import 'package:flutter/material.dart';

enum _PlanCategoryFilter { all, period, onetime }

class PurchasePlanCatalog extends StatefulWidget {
  const PurchasePlanCatalog({
    super.key,
    required this.catalog,
    required this.loading,
    required this.failed,
    required this.retry,
    this.openLink,
    this.onAcquirePlan,
    this.collapsibleDetails = false,
  });

  final XboardPlanCatalog? catalog;
  final bool loading;
  final bool failed;
  final VoidCallback retry;
  final Future<void> Function(Uri)? openLink;
  final ValueChanged<XboardPlanOffer>? onAcquirePlan;
  final bool collapsibleDetails;

  @override
  State<PurchasePlanCatalog> createState() => _PurchasePlanCatalogState();
}

class _PurchasePlanCatalogState extends State<PurchasePlanCatalog> {
  _PlanCategoryFilter _filter = _PlanCategoryFilter.all;

  static bool _hasRecurringPeriod(XboardPlanOffer plan) =>
      plan.prices.any((price) => price.period != 'onetime');

  static bool _hasOnetimePeriod(XboardPlanOffer plan) =>
      plan.prices.any((price) => price.period == 'onetime');

  List<XboardPlanOffer> _applyFilter(List<XboardPlanOffer> plans) =>
      switch (_filter) {
        _PlanCategoryFilter.all => plans,
        _PlanCategoryFilter.period =>
          plans.where(_hasRecurringPeriod).toList(growable: false),
        _PlanCategoryFilter.onetime =>
          plans.where(_hasOnetimePeriod).toList(growable: false),
      };

  @override
  void didUpdateWidget(covariant PurchasePlanCatalog oldWidget) {
    super.didUpdateWidget(oldWidget);
    final plans = widget.catalog?.plans ?? const <XboardPlanOffer>[];
    if (_filter != _PlanCategoryFilter.all &&
        plans.isNotEmpty &&
        _applyFilter(plans).isEmpty) {
      _filter = _PlanCategoryFilter.all;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final plans = widget.catalog?.plans ?? const <XboardPlanOffer>[];
    final hasMixedCategories = plans.length > 1 &&
        plans.any(_hasRecurringPeriod) &&
        plans.any(
          (plan) => !_hasRecurringPeriod(plan) && _hasOnetimePeriod(plan),
        );
    final filteredPlans =
        hasMixedCategories ? _applyFilter(plans) : plans;

    return Column(
      key: const Key('purchase-plans'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.layers_outlined,
                  size: 20,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    l.purchaseAvailablePlans,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (!widget.loading && !widget.failed && hasMixedCategories)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    key: const Key('purchase-plans-filter-all'),
                    label: Text(l.purchaseFilterAll),
                    labelStyle: theme.textTheme.labelSmall,
                    showCheckmark: false,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    selected: _filter == _PlanCategoryFilter.all,
                    onSelected: (_) =>
                        setState(() => _filter = _PlanCategoryFilter.all),
                  ),
                  ChoiceChip(
                    key: const Key('purchase-plans-filter-period'),
                    label: Text(l.purchaseFilterPeriod),
                    labelStyle: theme.textTheme.labelSmall,
                    showCheckmark: false,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    selected: _filter == _PlanCategoryFilter.period,
                    onSelected: (_) =>
                        setState(() => _filter = _PlanCategoryFilter.period),
                  ),
                  ChoiceChip(
                    key: const Key('purchase-plans-filter-onetime'),
                    label: Text(l.purchaseFilterOnetime),
                    labelStyle: theme.textTheme.labelSmall,
                    showCheckmark: false,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    selected: _filter == _PlanCategoryFilter.onetime,
                    onSelected: (_) =>
                        setState(() => _filter = _PlanCategoryFilter.onetime),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l.purchasePlansDescription,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        if (widget.loading)
          Semantics(
            liveRegion: true,
            label: l.purchasePlansLoading,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: const LinearProgressIndicator(
                key: Key('purchase-plans-loading'),
                minHeight: 6,
              ),
            ),
          )
        else if (widget.failed)
          _CatalogStateCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 20,
                      color: colors.error,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(l.purchasePlansError)),
                  ],
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  key: const Key('purchase-plans-retry'),
                  onPressed: widget.retry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(l.purchaseRefresh),
                ),
              ],
            ),
          )
        else if (plans.isEmpty)
          _CatalogStateCard(
            child: Row(
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 20,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(l.purchasePlansEmpty)),
              ],
            ),
          )
        else
          LayoutBuilder(builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final twoColumns = filteredPlans.length > 1 &&
                constraints.maxWidth >= 540 * textScale;
            final width = twoColumns
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final plan in filteredPlans)
                  SizedBox(
                    width: width,
                    child: _PlanCard(
                      key: Key('purchase-plan-${plan.id}'),
                      plan: plan,
                      openLink: widget.openLink,
                      onAcquirePlan: widget.onAcquirePlan,
                      collapsibleDetails: widget.collapsibleDetails,
                    ),
                  ),
              ],
            );
          }),
      ],
    );
  }
}

class _CatalogStateCard extends StatelessWidget {
  const _CatalogStateCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: child,
    );
  }
}

class _PlanCard extends StatefulWidget {
  const _PlanCard({
    super.key,
    required this.plan,
    this.openLink,
    this.onAcquirePlan,
    this.collapsibleDetails = false,
  });

  final XboardPlanOffer plan;
  final Future<void> Function(Uri)? openLink;
  final ValueChanged<XboardPlanOffer>? onAcquirePlan;
  final bool collapsibleDetails;

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard> {
  bool _detailsExpanded = false;

  XboardPlanOffer get plan => widget.plan;

  @override
  void didUpdateWidget(covariant _PlanCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plan.id != widget.plan.id) {
      _detailsExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final countryCode = inferCountryCodeFromText(plan.name);
    final isSoldOut =
        plan.hasCapacityRemaining && plan.capacityRemaining == 0;
    final isLowStock = plan.hasCapacityRemaining &&
        plan.capacityRemaining != null &&
        plan.capacityRemaining! > 0 &&
        plan.capacityRemaining! <= 20;

    final contentLines = plan.content
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    final shouldCollapse =
        widget.collapsibleDetails && contentLines.length > 6;
    final previewMarkdown = shouldCollapse && !_detailsExpanded
        ? plan.content.split('\n').take(5).join('\n')
        : plan.content;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSoldOut
              ? colors.outlineVariant.withValues(alpha: 0.55)
              : colors.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (countryCode != null) ...[
                      Container(
                        key: Key('purchase-plan-flag-${plan.id}'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colors.secondaryContainer
                              .withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: EmojiText(
                          nodeCountryEmoji(countryCode),
                          style: const TextStyle(fontSize: 15, height: 1.1),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
                      child: Text(
                        plan.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (isSoldOut || isLowStock)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isSoldOut
                          ? colors.errorContainer
                          : colors.tertiaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      isSoldOut
                          ? l.purchasePlanSoldOut
                          : l.purchasePlanLowStock(plan.capacityRemaining!),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isSoldOut
                            ? colors.onErrorContainer
                            : colors.onTertiaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            if (plan.tags.any((tag) => tag.trim().isNotEmpty)) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in plan.tags)
                    if (tag.trim().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          tag,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.onPrimaryContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.data_usage_rounded,
                        size: 18,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${l.purchaseTraffic}: ${plan.transferGiB} GiB',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontFamily: FontFamily.jetBrainsMono.value,
                            fontFamilyFallback: _cjkMonoFallback(theme),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (var index = 0; index < plan.prices.length; index++) ...[
                    if (index > 0) const SizedBox(height: 6),
                    _priceTile(
                      theme,
                      _period(l, plan.prices[index].period),
                      plan.prices[index].amount,
                      highlighted: index == 0,
                    ),
                  ],
                  if (plan.resetTrafficPrice != null) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1),
                    ),
                    _priceTile(
                      theme,
                      l.purchasePlanResetPrice,
                      plan.resetTrafficPrice!,
                      highlighted: false,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SpecPill(
                  icon: Icons.speed_rounded,
                  text: '${l.purchasePlanSpeed}: '
                      '${_limit(l, plan.hasSpeedLimit, plan.speedLimit, unit: ' Mbps')}',
                ),
                _SpecPill(
                  icon: Icons.devices_rounded,
                  text: '${l.purchasePlanDevices}: '
                      '${_limit(l, plan.hasDeviceLimit, plan.deviceLimit)}',
                ),
                _SpecPill(
                  icon: Icons.autorenew_rounded,
                  text: '${l.purchasePlanTrafficReset}: ${_reset(l)}',
                ),
                _SpecPill(
                  icon: Icons.confirmation_number_outlined,
                  text: '${l.purchasePlanSalesCapacity}: '
                      '${!plan.hasCapacityRemaining ? l.purchasePlanNotProvided : plan.capacityRemaining?.toString() ?? l.purchasePlanUnlimited}',
                ),
              ],
            ),
            if (plan.content.trim().isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(height: 1),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    l.purchasePlanDetails,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (shouldCollapse)
                    InkWell(
                      key: Key('purchase-plan-details-toggle-${plan.id}'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(
                        () => _detailsExpanded = !_detailsExpanded,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _detailsExpanded
                                    ? l.purchasePlanCollapseDetails
                                    : l.purchasePlanExpandDetails,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              _detailsExpanded
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              size: 18,
                              color: colors.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              PurchasePlanContent(
                data: previewMarkdown,
                openLink: widget.openLink,
              ),
            ],
            if (widget.onAcquirePlan != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                key: Key('purchase-plan-acquire-${plan.id}'),
                onPressed:
                    isSoldOut ? null : () => widget.onAcquirePlan!(plan),
                icon: Icon(
                  isSoldOut
                      ? Icons.block_rounded
                      : Icons.card_giftcard_rounded,
                  size: 18,
                ),
                label: Text(l.purchaseAcquirePlanCode),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<String> _cjkMonoFallback(ThemeData theme) => <String>[
        if (theme.textTheme.bodyMedium?.fontFamily case final String family)
          family,
        'Microsoft YaHei UI',
        'Microsoft YaHei',
        'PingFang SC',
        'Noto Sans CJK SC',
        'sans-serif',
      ];

  Widget _priceTile(
    ThemeData theme,
    String label,
    int amount, {
    required bool highlighted,
  }) {
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: highlighted
            ? colors.surface.withValues(alpha: 0.85)
            : colors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _amount(amount),
              textAlign: TextAlign.end,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: FontFamily.jetBrainsMono.value,
                fontWeight: FontWeight.w700,
                color: colors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _limit(
    AppLocalizations l,
    bool provided,
    int? value, {
    String unit = '',
  }) {
    if (!provided) return l.purchasePlanNotProvided;
    return (value ?? 0) == 0 ? l.purchasePlanUnlimited : '$value$unit';
  }

  String _reset(AppLocalizations l) {
    if (!plan.hasResetTrafficMethod) return l.purchasePlanNotProvided;
    return switch (plan.resetTrafficMethod) {
      null => l.purchasePlanResetSystem,
      0 => l.purchasePlanResetMonthStart,
      1 => l.purchasePlanResetMonthlyExpiry,
      2 => l.purchasePlanResetNever,
      3 => l.purchasePlanResetYearStart,
      4 => l.purchasePlanResetYearlyExpiry,
      final code => l.purchasePlanResetUnknown(code),
    };
  }

  // Keep minor units as integers; converting through double can round prices.
  String _amount(int amount) =>
      '${amount ~/ 100}.${(amount % 100).toString().padLeft(2, '0')}';

  String _period(AppLocalizations l, String period) => switch (period) {
        'monthly' => l.purchasePeriodMonthly,
        'quarterly' => l.purchasePeriodQuarterly,
        'half_yearly' => l.purchasePeriodHalfYearly,
        'yearly' => l.purchasePeriodYearly,
        'two_yearly' => l.purchasePeriodTwoYearly,
        'three_yearly' => l.purchasePeriodThreeYearly,
        'onetime' => l.purchasePeriodOnetime,
        _ => period,
      };
}

class _SpecPill extends StatelessWidget {
  const _SpecPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colors.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
