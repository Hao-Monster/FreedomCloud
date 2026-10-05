import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flutter/material.dart';

class PurchasePlanCatalog extends StatelessWidget {
  const PurchasePlanCatalog({
    super.key,
    required this.catalog,
    required this.loading,
    required this.failed,
    required this.retry,
  });

  final XboardPlanCatalog? catalog;
  final bool loading;
  final bool failed;
  final VoidCallback retry;

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
  const _PlanCard({super.key, required this.plan});

  final XboardPlanOffer plan;

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
            const SizedBox(height: 12),
            Text('${l.purchaseTraffic}: ${plan.transferGiB} GiB'),
            if ((plan.speedLimit ?? 0) > 0) ...[
              const SizedBox(height: 4),
              Text('${l.purchasePlanSpeed}: ${plan.speedLimit} Mbps'),
            ],
            if ((plan.deviceLimit ?? 0) > 0) ...[
              const SizedBox(height: 4),
              Text('${l.purchasePlanDevices}: ${plan.deviceLimit}'),
            ],
            const Divider(height: 28),
            for (final price in plan.prices)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(_period(l, price.period))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _amount(price.amount),
                        textAlign: TextAlign.end,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
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
