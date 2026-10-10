import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/views/purchase/plan_content.dart';
import 'package:flutter/material.dart';

class PurchasePlanCatalog extends StatelessWidget {
  const PurchasePlanCatalog({
    super.key,
    required this.catalog,
    required this.loading,
    required this.failed,
    required this.retry,
    this.openLink,
  });

  final XboardPlanCatalog? catalog;
  final bool loading;
  final bool failed;
  final VoidCallback retry;
  final Future<void> Function(Uri)? openLink;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final plans = catalog?.plans ?? const <XboardPlanOffer>[];
    return Column(
      key: const Key('purchase-plans'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.purchaseAvailablePlans,
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(l.purchasePlansDescription),
        const SizedBox(height: 16),
        if (loading)
          Semantics(
            liveRegion: true,
            label: l.purchasePlansLoading,
            child: const LinearProgressIndicator(
              key: Key('purchase-plans-loading'),
            ),
          )
        else if (failed)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.purchasePlansError),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    key: const Key('purchase-plans-retry'),
                    onPressed: retry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(l.purchaseRefresh),
                  ),
                ],
              ),
            ),
          )
        else if (plans.isEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(l.purchasePlansEmpty),
            ),
          )
        else
          LayoutBuilder(builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final twoColumns = constraints.maxWidth >= 640 * textScale;
            final width = twoColumns
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final plan in plans)
                  SizedBox(
                    width: width,
                    child: _PlanCard(
                      key: Key('purchase-plan-${plan.id}'),
                      plan: plan,
                      openLink: openLink,
                    ),
                  ),
              ],
            );
          }),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({super.key, required this.plan, this.openLink});

  final XboardPlanOffer plan;
  final Future<void> Function(Uri)? openLink;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(plan.name, style: theme.textTheme.titleMedium),
            if (plan.tags.any((tag) => tag.trim().isNotEmpty)) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in plan.tags)
                    if (tag.trim().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(tag,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                            )),
                      ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Text('${l.purchaseTraffic}: ${plan.transferGiB} GiB'),
            const SizedBox(height: 4),
            Text('${l.purchasePlanSpeed}: '
                '${_limit(l, plan.hasSpeedLimit, plan.speedLimit, unit: ' Mbps')}'),
            const SizedBox(height: 4),
            Text('${l.purchasePlanDevices}: '
                '${_limit(l, plan.hasDeviceLimit, plan.deviceLimit)}'),
            const SizedBox(height: 4),
            Text('${l.purchasePlanTrafficReset}: ${_reset(l)}'),
            const SizedBox(height: 4),
            Text('${l.purchasePlanSalesCapacity}: '
                '${!plan.hasCapacityRemaining ? l.purchasePlanNotProvided : plan.capacityRemaining?.toString() ?? l.purchasePlanUnlimited}'),
            const Divider(height: 28),
            for (final price in plan.prices)
              _price(theme, _period(l, price.period), price.amount),
            if (plan.resetTrafficPrice != null) ...[
              const Divider(height: 20),
              _price(theme, l.purchasePlanResetPrice, plan.resetTrafficPrice!),
            ],
            if (plan.content.trim().isNotEmpty) ...[
              const Divider(height: 28),
              Text(l.purchasePlanDetails, style: theme.textTheme.titleSmall),
              const SizedBox(height: 12),
              PurchasePlanContent(data: plan.content, openLink: openLink),
            ],
          ],
        ),
      ),
    );
  }

  Widget _price(ThemeData theme, String label, int amount) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _amount(amount),
                textAlign: TextAlign.end,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      );

  String _limit(AppLocalizations l, bool provided, int? value,
      {String unit = ''}) {
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
