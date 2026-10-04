import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/manager/purchase_manager.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class PurchaseCenter extends StatefulWidget {
  const PurchaseCenter({
    super.key,
    required this.manager,
    required this.openLink,
    required this.openProfiles,
  });

  final PurchaseManager manager;
  final Future<void> Function(Uri) openLink;
  final VoidCallback openProfiles;

  @override
  State<PurchaseCenter> createState() => _PurchaseCenterState();
}

class _PurchaseCenterState extends State<PurchaseCenter> {
  final _loginForm = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _wasLoggedIn = false;

  PurchaseManager get manager => widget.manager;
  AppLocalizations get l => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    _wasLoggedIn = manager.loggedIn;
    _code.text = manager.code;
    manager.addListener(_onManagerChanged);
  }

  @override
  void didUpdateWidget(covariant PurchaseCenter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manager != manager) {
      oldWidget.manager.removeListener(_onManagerChanged);
      manager.addListener(_onManagerChanged);
      _email.clear();
      _password.clear();
      _onManagerChanged();
    }
  }

  void _onManagerChanged() {
    if (_code.text != manager.code) {
      _code.value = TextEditingValue(
        text: manager.code,
        selection: TextSelection.collapsed(offset: manager.code.length),
      );
    }
    if (_wasLoggedIn != manager.loggedIn) {
      _password.clear();
      if (!manager.loggedIn) _email.clear();
    }
    _wasLoggedIn = manager.loggedIn;
  }

  @override
  void dispose() {
    manager.removeListener(_onManagerChanged);
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (manager.busy || !(_loginForm.currentState?.validate() ?? false)) return;
    await manager.login(_email.text.trim(), _password.text);
    if (mounted && manager.loggedIn) _password.clear();
  }

  Future<void> _logout() async {
    _password.clear();
    _email.clear();
    _code.clear();
    await manager.logout();
  }

  Future<void> _open(Uri uri) async {
    try {
      await widget.openLink(uri);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.purchaseOpenLinkFailed)),
      );
    }
  }

  Future<void> _copyWechat(String account) async {
    await Clipboard.setData(ClipboardData(text: account));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.copySuccess)),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: manager,
        builder: (context, _) => Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            key: const Key('purchase-scroll'),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l.purchaseCenterTitle,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(l.purchaseCenterDescription),
                  const SizedBox(height: 24),
                  if (!manager.loggedIn && manager.receipt != null) ...[
                    _Notice(
                      message:
                          '${l.purchaseSuccess}\n${l.purchaseSuccessDescription}',
                      success: true,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (manager.restoring)
                    _Section(
                      title: l.purchaseRestoring,
                      child: const LinearProgressIndicator(),
                    )
                  else if (!manager.loggedIn)
                    _loginSection()
                  else ...[
                    _accountSection(),
                    const SizedBox(height: 20),
                    if (manager.error != null) ...[
                      _Notice(
                          message: _errorMessage(manager.error!), error: true),
                      const SizedBox(height: 12),
                    ],
                    _redemptionSection(),
                    const SizedBox(height: 20),
                    _historySection(),
                  ],
                  const SizedBox(height: 20),
                  _supportSection(),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _loginSection() => _Section(
        title: l.purchaseLoginTitle,
        child: AutofillGroup(
          child: Form(
            key: _loginForm,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.purchaseLoginDescription),
                const SizedBox(height: 20),
                TextFormField(
                  key: const Key('purchase-email'),
                  controller: _email,
                  enabled: !manager.busy,
                  decoration: InputDecoration(labelText: l.purchaseEmail),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  autocorrect: false,
                  validator: (value) => value != null &&
                          RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                              .hasMatch(value.trim())
                      ? null
                      : l.purchaseEmailRequired,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('purchase-password'),
                  controller: _password,
                  enabled: !manager.busy,
                  decoration: InputDecoration(labelText: l.purchasePassword),
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  validator: (value) => value == null || value.isEmpty
                      ? l.purchasePasswordRequired
                      : null,
                  onFieldSubmitted: (_) async => _login(),
                ),
                if (manager.error != null) ...[
                  const SizedBox(height: 16),
                  _Notice(message: _errorMessage(manager.error!), error: true),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: manager.busy ? null : manager.refresh,
                      child: Text(l.purchaseRefresh),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const Key('purchase-login'),
                      onPressed: manager.busy ? null : _login,
                      icon: const Icon(Icons.login_rounded),
                      label: Text(
                          manager.busy ? l.purchaseLoggingIn : l.purchaseLogin),
                    ),
                    TextButton(
                      onPressed: () => _open(
                          manager.api.baseUri.replace(fragment: '/register')),
                      child: Text(l.purchaseRegister),
                    ),
                    TextButton(
                      onPressed: () => _open(manager.api.baseUri
                          .replace(fragment: '/forgetpassword')),
                      child: Text(l.purchaseRecoverPassword),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

  Widget _accountSection() {
    final subscription = manager.subscription;
    return _Section(
      title: l.purchaseAccount,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(manager.account?.email ?? '',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Wrap(
            spacing: 28,
            runSpacing: 16,
            children: [
              _Metric(
                label: l.purchasePlan,
                value: subscription?.planName ??
                    (subscription?.planId == null
                        ? l.purchaseNoPlan
                        : l.purchasePlanUnknown),
              ),
              if (subscription != null) ...[
                _Metric(
                    label: l.purchaseRemaining,
                    value: _traffic(subscription.remainingTraffic)),
                _Metric(
                    label: l.purchaseUsed,
                    value: _traffic(subscription.usedTraffic)),
                _Metric(
                    label: l.purchaseExpires,
                    value: subscription.planId == null
                        ? '—'
                        : _expiry(subscription.expiresAt)),
              ],
            ],
          ),
          const SizedBox(height: 20),
          if (manager.syncError != null) ...[
            _Notice(
              message:
                  '${manager.receipt == null ? l.purchaseSyncError : l.purchaseSyncFailed}\n${_errorMessage(manager.syncError!)}',
              error: true,
            ),
            const SizedBox(height: 12),
          ],
          if (manager.subscriptionSynced) ...[
            _Notice(message: l.purchaseSyncSucceeded, success: true),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                key: const Key('purchase-sync'),
                onPressed: manager.canSync && !manager.busy && !manager.syncing
                    ? manager.syncSubscription
                    : null,
                icon: const Icon(Icons.sync_rounded),
                label:
                    Text(manager.syncing ? l.purchaseSyncing : l.purchaseSync),
              ),
              TextButton.icon(
                onPressed: manager.busy ? null : manager.refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l.purchaseRefresh),
              ),
              TextButton(
                onPressed: widget.openProfiles,
                child: Text(l.purchaseProfiles),
              ),
              TextButton(
                key: const Key('purchase-logout'),
                onPressed: manager.busy || manager.syncing ? null : _logout,
                child: Text(l.purchaseLogout),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _redemptionSection() {
    final preview = manager.preview;
    final receipt = manager.receipt;
    final locked =
        manager.busy || manager.syncing || manager.unresolvedRedemption;
    return _Section(
      title: l.purchaseRedeemTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (manager.unresolvedRedemption) ...[
            _Notice(
              message:
                  '${l.purchaseUnresolved}\n${l.purchaseUnresolvedDescription}',
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                key: const Key('purchase-recover'),
                onPressed: manager.busy ? null : manager.recoverRedemption,
                icon: const Icon(Icons.manage_search_rounded),
                label: Text(l.purchaseRecoverResult),
              ),
            ),
            const SizedBox(height: 20),
          ],
          TextField(
            key: const Key('purchase-code'),
            controller: _code,
            enabled: !locked,
            decoration: InputDecoration(labelText: l.purchaseCode),
            maxLength: 32,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.search,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: manager.setCode,
            onSubmitted: (_) async {
              if (!locked && manager.code.trim().isNotEmpty) {
                await manager.checkCode();
              }
            },
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: const Key('purchase-check'),
              onPressed: locked || manager.code.trim().isEmpty
                  ? null
                  : manager.checkCode,
              icon: const Icon(Icons.search_rounded),
              label: Text(manager.busy ? l.purchaseChecking : l.purchaseCheck),
            ),
          ),
          if (preview != null && !manager.unresolvedRedemption) ...[
            const Divider(height: 36),
            Text(l.purchasePreview,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(preview.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('${l.purchaseRedeemFor}: ${manager.account?.email ?? ''}'),
            const SizedBox(height: 12),
            if (preview.isMystery)
              Text(l.purchaseMysteryPreview)
            else ...[
              _rewardDetails(preview.rewards),
              if (preview.purchasePreview != null)
                _purchaseChanges(preview.purchasePreview!),
            ],
            const SizedBox(height: 16),
            if (!preview.canRedeem)
              _Notice(
                message: (preview.reason?.isNotEmpty ?? false)
                    ? preview.reason!
                    : l.purchaseNotEligible,
                error: true,
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const Key('purchase-redeem'),
                onPressed: !locked && manager.canRedeem && preview.canRedeem
                    ? manager.redeem
                    : null,
                icon: const Icon(Icons.redeem_rounded),
                label: Text(manager.busy
                    ? l.purchaseRedeeming
                    : l.purchaseConfirmRedeem),
              ),
            ),
          ],
          if (receipt != null) ...[
            const Divider(height: 36),
            _Notice(
              message: '${l.purchaseSuccess}\n${l.purchaseSuccessDescription}',
              success: true,
            ),
            const SizedBox(height: 12),
            Text(receipt.templateName,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _rewardDetails(receipt.rewards),
            if (receipt.orderTradeNo != null)
              Text('${l.purchaseOrderNumber}: ${receipt.orderTradeNo}'),
          ],
        ],
      ),
    );
  }

  Widget _purchaseChanges(GiftPurchasePreview value) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                '${l.purchaseQuotaChange}\n${_traffic(value.transferBefore)} → ${_traffic(value.transferAfter)}'),
            const SizedBox(height: 8),
            Text(
                '${value.renewal ? l.purchaseUsedPreserved : l.purchaseUsed}: ${_traffic(value.usedTraffic)}'),
            const SizedBox(height: 8),
            Text(
                '${l.purchaseExpiryChange}\n${value.renewal ? _expiry(value.expiresBefore) : l.purchaseNoPreviousExpiry} → ${_expiry(value.expiresAfter)}'),
          ],
        ),
      );

  Widget _rewardDetails(GiftReward reward) {
    final snapshot = reward.purchaseSnapshot;
    final lines = <String>[
      if (snapshot != null) ...[
        snapshot.planName,
        '${l.purchasePeriod}: ${_period(snapshot.period)}',
        '${l.purchaseTraffic}: ${_traffic(snapshot.transferEnable)}',
      ],
      if (reward.balance != 0)
        '${l.purchaseBalance}: ${NumberFormat.currency(locale: Localizations.localeOf(context).toString(), symbol: '¥').format(reward.balance / 100)}',
      if (reward.transferEnable > 0)
        '${l.purchaseTraffic}: +${_traffic(reward.transferEnable)}',
      if (reward.expireDays > 0) '${l.purchaseExtraDays}: ${reward.expireDays}',
      if (snapshot == null && reward.planId != null)
        '${l.purchasePlan}: #${reward.planId}',
      if (reward.planValidityDays > 0)
        '${l.purchaseValidityDays}: ${reward.planValidityDays}',
      if (reward.deviceLimit > 0)
        '${l.purchaseExtraDevices}: ${reward.deviceLimit}',
      if (reward.resetTraffic) l.purchaseResetTraffic,
      if (reward.isEmpty) l.purchaseNoBenefits,
      if (reward.balance > 0 && snapshot == null && reward.planId == null)
        l.purchaseBalanceOnlyHint,
    ];
    return Text(lines.join('\n'), style: const TextStyle(height: 1.6));
  }

  Widget _historySection() {
    final history = manager.history;
    return _Section(
      title: l.purchaseHistory,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (manager.historyError != null) ...[
            _Notice(message: _errorMessage(manager.historyError!), error: true),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: manager.busy
                    ? null
                    : () => manager.loadHistory(history?.page ?? 1),
                child: Text(l.purchaseHistoryRetry),
              ),
            ),
          ] else if (history == null && manager.busy)
            const LinearProgressIndicator()
          else if (history == null || history.entries.isEmpty)
            Text(l.purchaseHistoryEmpty),
          for (final item in history?.entries ?? <GiftHistoryEntry>[]) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(item.templateName,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text('${item.maskedCode} · ${_date(item.usedAt)}'),
                  const SizedBox(height: 6),
                  _rewardDetails(item.rewards),
                  if (item.orderTradeNo != null)
                    Text('${l.purchaseOrderNumber}: ${item.orderTradeNo}'),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          if (history != null && history.total > 0) ...[
            const SizedBox(height: 12),
            Text(
                '${l.purchaseHistoryPage}: ${history.page} / ${history.lastPage} · ${l.purchaseHistoryTotal}: ${history.total}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  key: const Key('purchase-history-previous'),
                  onPressed: manager.busy || history.page <= 1
                      ? null
                      : () => manager.loadHistory(history.page - 1),
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: Text(l.purchasePreviousPage),
                ),
                TextButton.icon(
                  key: const Key('purchase-history-next'),
                  onPressed: manager.busy || history.page >= history.lastPage
                      ? null
                      : () => manager.loadHistory(history.page + 1),
                  icon: const Icon(Icons.chevron_right_rounded),
                  label: Text(l.purchaseNextPage),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _supportSection() => _Section(
        title: l.purchaseGetCard,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.purchaseGetCardDescription),
            if (manager.channelError != null) ...[
              const SizedBox(height: 12),
              _Notice(message: l.purchaseChannelError),
            ],
            if (manager.cardStoreUrl != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _open(manager.cardStoreUrl!),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(l.purchaseCardStore),
                ),
              ),
            ],
            const SizedBox(height: 16),
            for (final account in ['ChasingDream_2021', 'dxm_qa'])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SelectableText('${l.wechatId}: $account'),
                    TextButton.icon(
                      onPressed: () => _copyWechat(account),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: Text(l.copy),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

  String _date(DateTime value) {
    final local = value.toLocal();
    final material = MaterialLocalizations.of(context);
    final time = material.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return '${material.formatFullDate(local)} $time';
  }

  String _errorMessage(XboardException error) => switch (error.code) {
        'purchase_failed' => l.purchaseGenericError,
        'secure_storage_failed' => l.purchaseStorageError,
        'purchase_account_unsupported' => l.purchaseUnsupportedAccount,
        'logout_remote_failed' => l.purchaseLogoutRemoteError,
        'gift_code_format' => l.purchaseCodeFormatError,
        'gift_result_unconfirmed' => l.purchaseUnresolvedDescription,
        'subscription_sync_failed' => l.purchaseSyncError,
        _ =>
          error.message.trim().isEmpty ? l.purchaseGenericError : error.message,
      };

  String _expiry(DateTime? value) =>
      value == null ? l.purchaseNoExpiry : _date(value);

  String _traffic(int bytes) {
    final format =
        NumberFormat('0.##', Localizations.localeOf(context).toString());
    return '${format.format(bytes / 1073741824)} GiB';
  }

  String _period(String period) => switch (period) {
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

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 5),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
}

class _Notice extends StatelessWidget {
  const _Notice(
      {required this.message, this.error = false, this.success = false});

  final String message;
  final bool error;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: error ? colors.errorContainer : colors.secondaryContainer,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              error
                  ? Icons.error_outline_rounded
                  : success
                      ? Icons.check_circle_outline_rounded
                      : Icons.info_outline_rounded,
              color:
                  error ? colors.onErrorContainer : colors.onSecondaryContainer,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: TextStyle(
                    color: error
                        ? colors.onErrorContainer
                        : colors.onSecondaryContainer,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}
