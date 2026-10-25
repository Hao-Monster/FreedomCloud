import 'package:flclashx/common/node_country.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/manager/purchase_manager.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flclashx/views/purchase/plan_catalog.dart';
import 'package:flclashx/widgets/text.dart';
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
  static const _wechatContacts = <String>['ChasingDream_2021', 'dxm_qa'];

  final _loginForm = GlobalKey<FormState>();
  final _workbenchAnchor = GlobalKey();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _wasLoggedIn = false;
  bool _obscurePassword = true;
  bool _historyExpanded = false;

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
      _historyExpanded = false;
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
      if (!manager.loggedIn) {
        _email.clear();
        _historyExpanded = false;
      }
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
    _historyExpanded = false;
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

  Future<void> _copyText(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.copySuccess)),
    );
  }

  Future<void> _pasteCode() async {
    final clip = await Clipboard.getData('text/plain');
    final raw = clip?.text ?? '';
    if (raw.trim().isEmpty || !mounted) return;
    final colonIndex = raw.lastIndexOf(RegExp(r'[:：]'));
    final candidate =
        colonIndex >= 0 ? raw.substring(colonIndex + 1) : raw;
    final sanitized = candidate
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase();
    if (sanitized.isEmpty) return;
    final bounded =
        sanitized.length > 32 ? sanitized.substring(0, 32) : sanitized;
    _code.value = TextEditingValue(
      text: bounded,
      selection: TextSelection.collapsed(offset: bounded.length),
    );
    manager.setCode(bounded);
  }

  Future<void> _jumpToWorkbench() async {
    final targetContext = _workbenchAnchor.currentContext;
    if (targetContext == null) return;
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _showAcquireSheet(XboardPlanOffer plan) async {
    final priceSummary = plan.prices
        .map((price) => '${_period(price.period)} ${_amount(price.amount)}')
        .join(' / ');
    final inquiryText = l.purchaseInquiryTemplate(
      plan.name,
      plan.transferGiB,
      priceSummary,
    );
    final countryCode = inferCountryCodeFromText(plan.name);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final colors = theme.colorScheme;
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
            child: Column(
              key: const Key('purchase-acquire-sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (countryCode != null) ...[
                      EmojiText(
                        nodeCountryEmoji(countryCode),
                        style: const TextStyle(fontSize: 20),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        plan.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${plan.transferGiB} GiB · $priceSummary',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: FontFamily.jetBrainsMono.value,
fontFamilyFallback: _cjkMonoFallback(theme),
                      fontWeight: FontWeight.w600,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l.purchaseAcquireSheetSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                if (manager.cardStoreUrl != null) ...[
                  FilledButton.icon(
                    key: const Key('purchase-acquire-store'),
                    onPressed: () => _open(manager.cardStoreUrl!),
                    icon: const Icon(Icons.storefront_rounded, size: 18),
                    label: Text(l.purchaseCardStore),
                  ),
                  const SizedBox(height: 10),
                ],
                FilledButton.tonalIcon(
                  key: const Key('purchase-acquire-copy-inquiry'),
                  onPressed: () => _copyText(inquiryText),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  label: Text(l.purchaseCopyInquiry),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                for (final account in _wechatContacts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest
                            .withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SelectableText(
                            '${l.wechatId}: $account',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: FontFamily.jetBrainsMono.value,
fontFamilyFallback: _cjkMonoFallback(theme),
                            ),
                          ),
                          OutlinedButton.icon(
                            key: Key('purchase-acquire-wechat-$account'),
                            onPressed: () => _copyText(account),
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            label: Text(l.wechatId),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: manager,
        builder: (context, _) {
          final viewportWidth = MediaQuery.sizeOf(context).width;
          final horizontalPadding = viewportWidth < 420 ? 14.0 : 20.0;
          return FocusTraversalGroup(
            // Keep the form's reading order separate from the desktop side rail.
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                key: const Key('purchase-scroll'),
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  20,
                  horizontalPadding,
                  40,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final textScale =
                          MediaQuery.textScalerOf(context).scale(1);
                      final isDualColumn =
                          constraints.maxWidth >= 860 * textScale;
                      final workbenchWidth =
                          (constraints.maxWidth * 0.37).clamp(356.0, 420.0);
                      final columnGap =
                          constraints.maxWidth >= 1080 ? 24.0 : 20.0;

                      final catalogPane = FocusTraversalGroup(
                        child: PurchasePlanCatalog(
                          catalog: manager.planCatalog,
                          loading: manager.plansLoading,
                          failed: manager.plansError != null,
                          retry: manager.loadPlans,
                          openLink: _open,
                          onAcquirePlan: _showAcquireSheet,
                          collapsibleDetails: true,
                        ),
                      );

                      final workbenchPane = FocusTraversalGroup(
                        child: KeyedSubtree(
                          key: _workbenchAnchor,
                          child: Column(
                            key: const Key('purchase-workbench'),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!manager.loggedIn &&
                                  manager.receipt != null) ...[
                                _Notice(
                                  message:
                                      '${l.purchaseSuccess}\n${l.purchaseSuccessDescription}',
                                  success: true,
                                ),
                                const SizedBox(height: 12),
                              ],
                              if (manager.restoring)
                                _Section(
                                  icon: Icons.hourglass_top_rounded,
                                  title: l.purchaseRestoring,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(999),
                                    child: const LinearProgressIndicator(
                                      minHeight: 6,
                                    ),
                                  ),
                                )
                              else if (!manager.loggedIn)
                                _loginSection()
                              else ...[
                                _accountSection(),
                                const SizedBox(height: 16),
                                if (manager.error != null) ...[
                                  _Notice(
                                    message: _errorMessage(manager.error!),
                                    error: true,
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                _redemptionSection(),
                                const SizedBox(height: 16),
                                _historySection(),
                              ],
                              const SizedBox(height: 16),
                              _supportSection(),
                            ],
                          ),
                        ),
                      );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _headerBanner(
                            context,
                            showQuickJump: !isDualColumn,
                          ),
                          const SizedBox(height: 20),
                          if (isDualColumn)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: catalogPane),
                                SizedBox(width: columnGap),
                                SizedBox(
                                  width: workbenchWidth,
                                  child: workbenchPane,
                                ),
                              ],
                            )
                          else ...[
                            catalogPane,
                            const SizedBox(height: 20),
                            workbenchPane,
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      );

  Widget _headerBanner(BuildContext context, {required bool showQuickJump}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.purchaseCenterTitle,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l.purchaseCenterDescription,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (showQuickJump)
                ExcludeFocusTraversal(
                  child: FilledButton.tonalIcon(
                    key: const Key('purchase-jump-workbench'),
                    onPressed: _jumpToWorkbench,
                    icon: const Icon(Icons.bolt_rounded, size: 18),
                    label: Text(l.purchaseJumpToWorkbench),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _StepChip(label: l.purchaseStepBrowse, active: true),
              _StepChip(label: l.purchaseStepRedeem, active: manager.loggedIn),
              _StepChip(
                label: l.purchaseStepSync,
                active: manager.subscriptionSynced,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _loginSection() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return _Section(
      icon: Icons.person_outline_rounded,
      title: l.purchaseLoginTitle,
      child: AutofillGroup(
        child: Form(
          key: _loginForm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: 18,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l.purchaseLoginDescription,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('purchase-email'),
                controller: _email,
                enabled: !manager.busy,
                decoration: _inputDecoration(
                  context,
                  labelText: l.purchaseEmail,
                  prefixIcon: Icons.alternate_email_rounded,
                ),
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
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('purchase-password'),
                controller: _password,
                enabled: !manager.busy,
                decoration: _inputDecoration(
                  context,
                  labelText: l.purchasePassword,
                  prefixIcon: Icons.lock_outline_rounded,
                  suffixIcon: ExcludeFocusTraversal(
                    child: IconButton(
                      key: const Key('purchase-password-visibility'),
                      tooltip: _obscurePassword
                          ? l.purchaseShowPassword
                          : l.purchaseHidePassword,
                      onPressed: manager.busy
                          ? null
                          : () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                obscureText: _obscurePassword,
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
                const SizedBox(height: 14),
                _Notice(message: _errorMessage(manager.error!), error: true),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: manager.busy ? null : manager.refresh,
                    child: Text(l.purchaseRefresh),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('purchase-login'),
                onPressed: manager.busy ? null : _login,
                icon: const Icon(Icons.login_rounded, size: 18),
                label: Text(
                  manager.busy ? l.purchaseLoggingIn : l.purchaseLogin,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    onPressed: () => _open(
                      manager.api.baseUri.replace(fragment: '/register'),
                    ),
                    child: Text(l.purchaseRegister),
                  ),
                  TextButton(
                    onPressed: () => _open(
                      manager.api.baseUri.replace(fragment: '/forgetpassword'),
                    ),
                    child: Text(l.purchaseRecoverPassword),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountSection() {
    final subscription = manager.subscription;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasQuota = subscription != null && subscription.total > 0;
    final quotaRatio = hasQuota
        ? (subscription.remainingTraffic / subscription.total).clamp(0.0, 1.0)
        : 0.0;

    return _Section(
      icon: Icons.card_membership_rounded,
      title: l.purchaseAccount,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.account_circle_outlined,
                  size: 20,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    manager.account?.email ?? '',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontFamily: FontFamily.jetBrainsMono.value,
fontFamilyFallback: _cjkMonoFallback(theme),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (hasQuota) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: quotaRatio,
                minHeight: 7,
                backgroundColor: colors.surfaceContainerHighest,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 20,
            runSpacing: 12,
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
                  value: _traffic(subscription.remainingTraffic),
                  monospace: true,
                ),
                _Metric(
                  label: l.purchaseUsed,
                  value: _traffic(subscription.usedTraffic),
                  monospace: true,
                ),
                _Metric(
                  label: l.purchaseExpires,
                  value: subscription.planId == null
                      ? '—'
                      : _expiry(subscription.expiresAt),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
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
                icon: const Icon(Icons.sync_rounded, size: 18),
                label: Text(
                  manager.syncing ? l.purchaseSyncing : l.purchaseSync,
                ),
              ),
              TextButton.icon(
                onPressed: manager.busy ? null : manager.refresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasCodeText = manager.code.trim().isNotEmpty || _code.text.isNotEmpty;

    return _Section(
      icon: Icons.redeem_rounded,
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
                icon: const Icon(Icons.manage_search_rounded, size: 18),
                label: Text(l.purchaseRecoverResult),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (receipt != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.45),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Notice(
                    message:
                        '${l.purchaseSuccess}\n${l.purchaseSuccessDescription}',
                    success: true,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    receipt.templateName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _rewardDetails(receipt.rewards),
                  if (receipt.orderTradeNo != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${l.purchaseOrderNumber}: ${receipt.orderTradeNo}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: FontFamily.jetBrainsMono.value,
fontFamilyFallback: _cjkMonoFallback(theme),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const Key('purchase-open-profiles'),
                      onPressed: widget.openProfiles,
                      icon: const Icon(Icons.dns_outlined, size: 18),
                      label: Text(l.purchaseOpenNodesAction),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            key: const Key('purchase-code'),
            controller: _code,
            enabled: !locked,
            style: TextStyle(
              fontFamily: FontFamily.jetBrainsMono.value,
fontFamilyFallback: _cjkMonoFallback(theme),
              letterSpacing: 1.1,
              fontWeight: FontWeight.w600,
            ),
            decoration: _inputDecoration(
              context,
              labelText: l.purchaseCode,
              prefixIcon: Icons.confirmation_number_outlined,
              suffixIcon: ExcludeFocusTraversal(
                child: hasCodeText
                    ? IconButton(
                        key: const Key('purchase-code-clear'),
                        tooltip: l.purchaseClearCode,
                        onPressed: locked
                            ? null
                            : () {
                                _code.clear();
                                manager.setCode('');
                              },
                        icon: const Icon(Icons.close_rounded, size: 18),
                      )
                    : IconButton(
                        key: const Key('purchase-code-paste'),
                        tooltip: l.paste,
                        onPressed: locked ? null : _pasteCode,
                        icon: const Icon(Icons.content_paste_rounded, size: 18),
                      ),
              ),
            ),
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
          const SizedBox(height: 4),
          FilledButton.tonalIcon(
            key: const Key('purchase-check'),
            onPressed: locked || manager.code.trim().isEmpty
                ? null
                : manager.checkCode,
            icon: const Icon(Icons.search_rounded, size: 18),
            label: Text(
              manager.checkingCode ? l.purchaseChecking : l.purchaseCheck,
            ),
          ),
          if (preview != null && !manager.unresolvedRedemption) ...[
            const SizedBox(height: 16),
            Container(
              key: const Key('purchase-preview-card'),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: preview.canRedeem
                      ? colors.primary.withValues(alpha: 0.55)
                      : colors.error.withValues(alpha: 0.65),
                  width: 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        l.purchasePreview,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (preview.purchasePreview != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colors.secondaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            preview.purchasePreview!.renewal
                                ? l.purchaseRenewalBadge
                                : l.purchaseNewActivationBadge,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    preview.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person_pin_circle_outlined,
                          size: 16,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${l.purchaseRedeemFor}: ${manager.account?.email ?? ''}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (preview.isMystery)
                    Text(l.purchaseMysteryPreview)
                  else ...[
                    _rewardDetails(preview.rewards),
                    if (preview.purchasePreview != null)
                      _purchaseChanges(preview.purchasePreview!),
                  ],
                  const SizedBox(height: 14),
                  if (!preview.canRedeem) ...[
                    _Notice(
                      message: (preview.reason?.isNotEmpty ?? false)
                          ? preview.reason!
                          : l.purchaseNotEligible,
                      error: true,
                    ),
                    const SizedBox(height: 10),
                  ],
                  FilledButton.icon(
                    key: const Key('purchase-redeem'),
                    onPressed: !locked && manager.canRedeem && preview.canRedeem
                        ? manager.redeem
                        : null,
                    icon: const Icon(Icons.redeem_rounded, size: 18),
                    label: Text(
                      manager.redeemingCode
                          ? l.purchaseRedeeming
                          : l.purchaseConfirmRedeem,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _purchaseChanges(GiftPurchasePreview value) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${l.purchaseQuotaChange}\n${_traffic(value.transferBefore)} → ${_traffic(value.transferAfter)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: FontFamily.jetBrainsMono.value,
fontFamilyFallback: _cjkMonoFallback(theme),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${value.renewal ? l.purchaseUsedPreserved : l.purchaseUsed}: ${_traffic(value.usedTraffic)}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Text(
            '${l.purchaseExpiryChange}\n${value.renewal ? _expiry(value.expiresBefore) : l.purchaseNoPreviousExpiry} → ${_expiry(value.expiresAfter)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

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
    return Text(lines.join('\n'), style: const TextStyle(height: 1.55));
  }

  Widget _historySection() {
    final history = manager.history;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const Key('purchase-history-toggle'),
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => _historyExpanded = !_historyExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 20,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.purchaseHistory,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (history != null && history.total > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${history.total}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontFamily: FontFamily.jetBrainsMono.value,
fontFamilyFallback: _cjkMonoFallback(theme),
                          color: colors.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Icon(
                    _historyExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_historyExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 14),
                  if (manager.historyError != null) ...[
                    _Notice(
                      message: _errorMessage(manager.historyError!),
                      error: true,
                    ),
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
                  for (final item
                      in history?.entries ?? <GiftHistoryEntry>[]) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            item.templateName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${item.maskedCode} · ${_date(item.usedAt)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: FontFamily.jetBrainsMono.value,
fontFamilyFallback: _cjkMonoFallback(theme),
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _rewardDetails(item.rewards),
                          if (item.orderTradeNo != null)
                            Text(
                              '${l.purchaseOrderNumber}: ${item.orderTradeNo}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: FontFamily.jetBrainsMono.value,
fontFamilyFallback: _cjkMonoFallback(theme),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                  if (history != null && history.total > 0) ...[
                    const SizedBox(height: 12),
                    Text(
                      '${l.purchaseHistoryPage}: ${history.page} / ${history.lastPage} · ${l.purchaseHistoryTotal}: ${history.total}',
                      style: theme.textTheme.bodySmall,
                    ),
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
                          onPressed: manager.busy ||
                                  history.page >= history.lastPage
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
            ),
        ],
      ),
    );
  }

  Widget _supportSection() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return _Section(
      icon: Icons.support_agent_rounded,
      title: l.purchaseGetCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.purchaseGetCardDescription,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
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
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(l.purchaseCardStore),
              ),
            ),
          ],
          const SizedBox(height: 14),
          for (final account in _wechatContacts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SelectableText(
                      '${l.wechatId}: $account',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: FontFamily.jetBrainsMono.value,
fontFamilyFallback: _cjkMonoFallback(theme),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _copyText(account),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: Text(l.copy),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    required String labelText,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    final colors = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: labelText,
      filled: true,
      fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.35),
      prefixIcon: Icon(prefixIcon, size: 18),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  String _amount(int amount) =>
      '${amount ~/ 100}.${(amount % 100).toString().padLeft(2, '0')}';

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

List<String> _cjkMonoFallback(ThemeData theme) => <String>[
      if (theme.textTheme.bodyMedium?.fontFamily case final String family)
        family,
      'Microsoft YaHei UI',
      'Microsoft YaHei',
      'PingFang SC',
      'Noto Sans CJK SC',
      'sans-serif',
    ];

class _StepChip extends StatelessWidget {
  const _StepChip({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active
            ? colors.primaryContainer.withValues(alpha: 0.65)
            : colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: active ? colors.onPrimaryContainer : colors.onSurfaceVariant,
          fontWeight: active ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontFamily: monospace ? FontFamily.jetBrainsMono.value : null,
              fontFamilyFallback: monospace ? _cjkMonoFallback(theme) : null,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.message,
    this.error = false,
    this.success = false,
  });

  final String message;
  final bool error;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bgColor = error
        ? colors.errorContainer
        : success
            ? colors.primaryContainer.withValues(alpha: 0.75)
            : colors.secondaryContainer;
    final fgColor = error
        ? colors.onErrorContainer
        : success
            ? colors.onPrimaryContainer
            : colors.onSecondaryContainer;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: bgColor,
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
              color: fgColor,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: fgColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
