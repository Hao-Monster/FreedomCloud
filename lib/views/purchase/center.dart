import 'dart:async';

import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/manager/purchase_manager.dart';
import 'package:flclashx/manager/support_manager.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/providers/purchase_support_provider.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flclashx/views/purchase/plan_catalog.dart';
import 'package:flclashx/views/support/support_chat_sheet.dart';
import 'package:flclashx/widgets/text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final RegExp _standardUuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

String? _extractStrictResumeCode(
  String raw, {
  required bool allowUnlabeled,
}) {
  if (raw.trim().isEmpty) return null;
  final sanitized = raw
      .replaceAll(RegExp(r'https?://[\x21-\x7E]+', caseSensitive: false), ' ')
      .replaceAll(
        RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
        ' ',
      )
      .replaceAll(
        RegExp(r'(?<!\d)\d{4}[-/.]\d{1,2}[-/.]\d{1,2}(?!\d)'),
        ' ',
      )
      .replaceAll(RegExp(r'(?<!\d)\d{1,2}:\d{2}(?::\d{2})?(?!\d)'), ' ');

  final labeledMatch = RegExp(
    r'''(?:兑换码|卡密|礼品卡|激活码|(?<![A-Za-z0-9_])(?:voucher|gift\s*code|redeem\s*code|code))\s*[:：]\s*[`'"“”‘’【「『\[\(]*([A-Za-z0-9]+(?:-[A-Za-z0-9]+)*)''',
    caseSensitive: false,
  ).firstMatch(sanitized);
  if (labeledMatch != null) {
    final token = labeledMatch.group(1)!;
    if (_standardUuidPattern.hasMatch(token)) return null;
    final normalized = token.replaceAll('-', '').toUpperCase();
    if (RegExp(r'^[A-Z0-9]{8,32}$').hasMatch(normalized)) {
      return normalized;
    }
  }

  if (!allowUnlabeled) return null;

  final trimmed = sanitized.trim();
  if (_standardUuidPattern.hasMatch(trimmed)) return null;
  if (RegExp(r'^[A-Za-z0-9]{2,}(?:-[A-Za-z0-9]{2,})+$').hasMatch(trimmed)) {
    final normalized = trimmed.replaceAll('-', '').toUpperCase();
    if (RegExp(r'^[A-Z0-9]{8,32}$').hasMatch(normalized)) {
      return normalized;
    }
  }
  if (RegExp(r'^(?=.*[A-Za-z])(?=.*\d)[A-Za-z0-9]{8,32}$').hasMatch(trimmed)) {
    return trimmed.toUpperCase();
  }
  return null;
}

String? extractRedemptionCodeFromClipboard(String raw) {
  if (raw.trim().isEmpty) return null;
  final sanitized = raw
      .replaceAll(RegExp(r'https?://[\x21-\x7E]+', caseSensitive: false), ' ')
      .replaceAll(
        RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
        ' ',
      )
      .replaceAll(
        RegExp(r'(?<!\d)\d{4}[-/.]\d{1,2}[-/.]\d{1,2}(?!\d)'),
        ' ',
      )
      .replaceAll(RegExp(r'(?<!\d)\d{1,2}:\d{2}(?::\d{2})?(?!\d)'), ' ');
  if (!RegExp(r'[A-Za-z0-9]').hasMatch(sanitized)) {
    return null;
  }

  final labeledMatches = RegExp(
    r'''(?:兑换码|卡密|礼品卡|激活码|(?<![A-Za-z0-9_])(?:voucher|gift\s*code|redeem\s*code|code))\s*[:：]\s*[`'"“”‘’【「『\[\(]*([A-Za-z0-9]+(?:-[A-Za-z0-9]+)*)''',
    caseSensitive: false,
  ).allMatches(sanitized);
  for (final labeledMatch in labeledMatches) {
    final normalized = labeledMatch.group(1)!.replaceAll('-', '').toUpperCase();
    if (normalized.length >= 4) return normalized;
  }

  final tokenMatches = RegExp(
    r'(?<![A-Za-z0-9_@./-])(?:[A-Za-z0-9]+(?:-[A-Za-z0-9]+)+|[A-Za-z0-9]{8,})(?![A-Za-z0-9_@./-])',
  ).allMatches(sanitized);
  String? fallbackInRange;
  String? fallbackOverlong;
  for (final match in tokenMatches) {
    final rawToken = match.group(0)!;
    final upper = rawToken.replaceAll('-', '').toUpperCase();
    if (upper.length >= 8 && upper.length <= 32) {
      final looksLikeCode = rawToken.contains('-') ||
          RegExp(r'\d').hasMatch(rawToken) ||
          rawToken == upper;
      if (looksLikeCode) return upper;
      fallbackInRange ??= upper;
    } else if (upper.length > 32) {
      fallbackOverlong ??= upper;
    }
  }
  if (fallbackInRange != null) return fallbackInRange;
  if (fallbackOverlong != null) return fallbackOverlong;

  final fallback =
      sanitized.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  return fallback.isEmpty ? null : fallback;
}

class _UpperCaseCodeFormatter extends TextInputFormatter {
  const _UpperCaseCodeFormatter();

  static final RegExp _asciiLower = RegExp('[a-z]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.isComposingRangeValid ||
        !_asciiLower.hasMatch(newValue.text)) {
      return newValue;
    }
    final upper = newValue.text.replaceAllMapped(
      _asciiLower,
      (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 32),
    );
    return newValue.copyWith(
      text: upper,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

class PurchaseCenter extends StatefulWidget {
  const PurchaseCenter({
    super.key,
    required this.manager,
    required this.openLink,
    required this.openProfiles,
    this.supportManager,
    this.isActiveTab = true,
  });

  final PurchaseManager manager;
  final Future<void> Function(Uri) openLink;
  final VoidCallback openProfiles;
  final SupportManager? supportManager;
  final bool isActiveTab;

  @override
  State<PurchaseCenter> createState() => _PurchaseCenterState();
}

class _PurchaseCenterState extends State<PurchaseCenter>
    with WidgetsBindingObserver {
  static const _wechatContacts = <String>['ChasingDream_2021', 'dxm_qa'];
  static const _preferredEmailDomains = <String>[
    'gmail.com',
    'qq.com',
    '163.com',
    'outlook.com',
    'icloud.com',
    'hotmail.com',
    '126.com',
    'foxmail.com',
    'yahoo.com',
  ];

  final _loginForm = GlobalKey<FormState>();
  final _catalogAnchor = GlobalKey();
  final _workbenchAnchor = GlobalKey();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailCode = TextEditingController();
  final _inviteCode = TextEditingController();
  final _newPassword = TextEditingController();
  final _code = TextEditingController();
  final ValueNotifier<int> _cooldownSeconds = ValueNotifier<int>(0);
  Timer? _cooldownTimer;
  SupportManagerHandle? _fallbackSupportHandle;
  bool _wasLoggedIn = false;
  bool _isRegisterMode = false;
  bool _isForgotPasswordMode = false;
  bool _showInviteField = false;
  bool _codeSentNotice = false;
  String? _localEmailError;
  bool _obscurePassword = true;
  bool _historyExpanded = false;
  bool _updatingCodeFromInput = false;
  bool _checkingResumeClipboard = false;
  bool _openingExternalLink = false;
  int? _buyingPlanId;
  String? _lastAutoDetectedClipboard;
  String? _lastHandledNormalizedCode;
  String _lastNonEmptyManagerCode = '';

  PurchaseManager get manager => widget.manager;
  AppLocalizations get l => AppLocalizations.of(context);
  bool get _isRealManager => PurchaseManager.isRealInstance(manager);
  XboardPurchaseChannels? get _purchaseChannels =>
      _isRealManager ? manager.purchaseChannels : null;
  XboardGuestAuthConfig get _guestAuthConfig =>
      _isRealManager ? manager.guestAuthConfig : const XboardGuestAuthConfig();
  XboardPlanOffer? get _handoffPlan =>
      _isRealManager ? manager.handoffPlan : null;
  bool get _registering => _isRealManager && manager.registering;
  bool get _resettingPassword => _isRealManager && manager.resettingPassword;
  SupportManager get _effectiveSupportManager =>
      widget.supportManager ??
      (_fallbackSupportHandle ??= createSupportManagerHandle(
        fallbackBaseUrl: () => manager.api.baseUri,
      ))
          .manager;

  Uri? _resolvePlanStoreUrl(XboardPlanOffer plan) => _isRealManager
      ? manager.resolvePlanStoreUrl(plan)
      : (XboardPurchaseChannels.extractPlanContentPurchaseUrl(plan.content) ??
          manager.cardStoreUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _wasLoggedIn = manager.loggedIn;
    _code.text = manager.code;
    manager.addListener(_onManagerChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkClipboardOnResume());
    }
  }

  Future<void> _checkClipboardOnResume() async {
    if (!mounted ||
        !widget.isActiveTab ||
        !TickerMode.valuesOf(context).enabled ||
        _checkingResumeClipboard ||
        manager.restoring ||
        manager.busy ||
        manager.syncing ||
        manager.unresolvedRedemption ||
        manager.code.trim().isNotEmpty ||
        (manager.receipt != null && _handoffPlan == null)) {
      return;
    }
    _checkingResumeClipboard = true;
    try {
      final clip = await Clipboard.getData('text/plain');
      final raw = clip?.text ?? '';
      if (!mounted ||
          !widget.isActiveTab ||
          !TickerMode.valuesOf(context).enabled ||
          raw.isEmpty ||
          raw == _lastAutoDetectedClipboard) {
        return;
      }
      if (manager.busy ||
          manager.syncing ||
          manager.unresolvedRedemption ||
          manager.code.trim().isNotEmpty ||
          (manager.receipt != null && _handoffPlan == null)) {
        return;
      }
      final extracted = _extractStrictResumeCode(
        raw,
        allowUnlabeled: _handoffPlan != null,
      );
      if (extracted == null || extracted == _lastHandledNormalizedCode) return;
      _lastAutoDetectedClipboard = raw;
      _lastHandledNormalizedCode = extracted;
      _code.value = TextEditingValue(
        text: extracted,
        selection: TextSelection.collapsed(offset: extracted.length),
      );
      manager.setCode(extracted);
      if (manager.loggedIn && !manager.busy) {
        await manager.checkCode();
      }
    } catch (_) {
      // Ignore clipboard platform errors silently on window focus.
    } finally {
      _checkingResumeClipboard = false;
    }
  }

  @override
  void didUpdateWidget(covariant PurchaseCenter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manager != manager) {
      oldWidget.manager.removeListener(_onManagerChanged);
      manager.addListener(_onManagerChanged);
      _email.clear();
      _password.clear();
      _emailCode.clear();
      _inviteCode.clear();
      _newPassword.clear();
      _cooldownTimer?.cancel();
      _cooldownTimer = null;
      _cooldownSeconds.value = 0;
      _isRegisterMode = false;
      _isForgotPasswordMode = false;
      _showInviteField = false;
      _codeSentNotice = false;
      _obscurePassword = true;
      _historyExpanded = false;
      _onManagerChanged(notifyState: false);
    }
  }

  void _onManagerChanged({bool notifyState = true}) {
    if (manager.code.isNotEmpty) {
      _lastNonEmptyManagerCode = manager.code;
    } else if (manager.receipt != null && _lastNonEmptyManagerCode.isNotEmpty) {
      _lastHandledNormalizedCode = _lastNonEmptyManagerCode;
    }
    final normalizedControllerCode =
        PurchaseManager.normalizeCodeInput(_code.text);
    final shouldSyncController = manager.code.isEmpty
        ? normalizedControllerCode.isNotEmpty
        : (normalizedControllerCode != manager.code &&
            !_code.value.isComposingRangeValid);
    if (!_updatingCodeFromInput && shouldSyncController) {
      _code.value = TextEditingValue(
        text: manager.code,
        selection: TextSelection.collapsed(offset: manager.code.length),
      );
    }
    if (_wasLoggedIn != manager.loggedIn) {
      if (manager.loggedIn) {
        TextInput.finishAutofillContext();
      }
      _password.clear();
      _emailCode.clear();
      _inviteCode.clear();
      _newPassword.clear();
      _cooldownTimer?.cancel();
      _cooldownTimer = null;
      _cooldownSeconds.value = 0;
      if (!manager.loggedIn) {
        _email.clear();
        _code.clear();
      }
      final needsStateReset = !_obscurePassword ||
          _isRegisterMode ||
          _isForgotPasswordMode ||
          _showInviteField ||
          _codeSentNotice ||
          (!manager.loggedIn && _historyExpanded);
      _obscurePassword = true;
      _isRegisterMode = false;
      _isForgotPasswordMode = false;
      _showInviteField = false;
      _codeSentNotice = false;
      if (!manager.loggedIn) {
        _historyExpanded = false;
      }
      if (notifyState && needsStateReset && mounted) {
        setState(() {});
      }
    }
    _wasLoggedIn = manager.loggedIn;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    manager.removeListener(_onManagerChanged);
    _cooldownTimer?.cancel();
    _cooldownSeconds.dispose();
    _fallbackSupportHandle?.dispose();
    _email.dispose();
    _password.dispose();
    _emailCode.dispose();
    _inviteCode.dispose();
    _newPassword.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown([int seconds = 60]) {
    _cooldownTimer?.cancel();
    final initial = seconds > 0 ? seconds : 60;
    _cooldownSeconds.value = initial;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final next = _cooldownSeconds.value - 1;
      if (next <= 0) {
        _cooldownSeconds.value = 0;
        timer.cancel();
        _cooldownTimer = null;
      } else {
        _cooldownSeconds.value = next;
      }
    });
  }

  String? _validateEmailInput(
    String? value, {
    required bool checkRegisterPolicy,
  }) {
    final trimmed = value?.trim() ?? '';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(trimmed)) {
      return l.purchaseEmailRequired;
    }
    if (checkRegisterPolicy) {
      if (_guestAuthConfig.hasGmailPlusAlias(trimmed)) {
        return l.purchaseGmailAliasError;
      }
      if (!_guestAuthConfig.isEmailDomainAllowed(trimmed)) {
        return l.purchaseEmailDomainError;
      }
    }
    return null;
  }

  Future<void> _sendEmailVerificationCode({required bool forReset}) async {
    if (!_isRealManager || manager.sendingEmailCode || manager.busy) return;
    final emailError = _validateEmailInput(
      _email.text,
      checkRegisterPolicy: !forReset && manager.api is XboardPassportApi,
    );
    if (emailError != null) {
      setState(() {
        _codeSentNotice = false;
        _localEmailError = emailError;
      });
      return;
    }
    final email = _email.text.trim();
    if ((_codeSentNotice || _localEmailError != null) && mounted) {
      setState(() {
        _codeSentNotice = false;
        _localEmailError = null;
      });
    }
    final sent = forReset
        ? await manager.sendPasswordResetCode(email)
        : await manager.sendRegistrationEmailCode(email);
    if (!mounted) return;
    if (sent) {
      setState(() {
        _codeSentNotice = true;
        _localEmailError = null;
      });
      _startCooldown(60);
    } else if (manager.error?.retryAfterSeconds != null) {
      _startCooldown(manager.error!.retryAfterSeconds!);
    }
  }

  Future<void> _login() async {
    if (manager.busy || !(_loginForm.currentState?.validate() ?? false)) return;
    if (_isRealManager) {
      manager.clearPasswordResetState();
    }
    await manager.login(_email.text.trim(), _password.text);
    if (mounted && manager.loggedIn) _password.clear();
  }

  Future<void> _register() async {
    if (!_isRealManager ||
        manager.busy ||
        !(_loginForm.currentState?.validate() ?? false)) {
      return;
    }
    if (manager.api is XboardPassportApi) {
      final emailCode = _emailCode.text.trim();
      final inviteCode = _inviteCode.text.trim();
      await manager.registerWithDetails(
        email: _email.text.trim(),
        password: _password.text,
        emailCode: emailCode.isEmpty ? null : emailCode,
        inviteCode: inviteCode.isEmpty ? null : inviteCode,
      );
    } else {
      await manager.register(_email.text.trim(), _password.text);
    }
    if (mounted && manager.loggedIn) {
      _password.clear();
      _emailCode.clear();
      _inviteCode.clear();
    }
  }

  Future<void> _submitResetPassword() async {
    if (!_isRealManager ||
        manager.busy ||
        !(_loginForm.currentState?.validate() ?? false)) {
      return;
    }
    final ok = await manager.resetPassword(
      email: _email.text.trim(),
      emailCode: _emailCode.text.trim(),
      password: _newPassword.text,
    );
    if (!mounted) return;
    if (ok && manager.passwordResetSucceeded) {
      _emailCode.clear();
      _newPassword.clear();
      _password.clear();
      setState(() {
        _isForgotPasswordMode = false;
        _isRegisterMode = false;
        _codeSentNotice = false;
      });
    }
  }

  Future<void> _openSupport({String? initialDraft}) async {
    final locale = Localizations.localeOf(context).toString();
    final chatUrl = _purchaseChannels?.resolveChatwootWidgetUrl(locale: locale);
    final support = _effectiveSupportManager;
    syncSupportManagerWithPurchase(manager, support);
    await openSupportChatSheet(
      context,
      supportManager: support,
      openLink: _open,
      externalWidgetUri: chatUrl,
      initialDraft: initialDraft,
      wechatContacts: _wechatContacts,
      onRetryChannel: _isRealManager
          ? () => manager.ensurePurchaseChannels(force: true)
          : null,
    );
  }

  Future<void> _handleBuyPlan(XboardPlanOffer plan) async {
    if (_buyingPlanId != null || _openingExternalLink) return;
    if (mounted) {
      setState(() => _buyingPlanId = plan.id);
    } else {
      _buyingPlanId = plan.id;
    }
    try {
      var targetUrl = _resolvePlanStoreUrl(plan);
      if (targetUrl == null && _isRealManager) {
        await manager.ensurePurchaseChannels(
          force: manager.channelError != null,
        );
        if (!mounted) return;
        targetUrl = _resolvePlanStoreUrl(plan);
      }
      if (targetUrl != null) {
        if (_isRealManager) {
          manager.markPlanHandoff(plan);
        }
        await _open(targetUrl);
        return;
      }
      await _showAcquireSheet(plan);
    } finally {
      if (mounted) {
        setState(() => _buyingPlanId = null);
      } else {
        _buyingPlanId = null;
      }
    }
  }

  Future<void> _pasteAndCheckHandoff() async {
    await _pasteCode();
    if (!mounted) return;
    if (manager.loggedIn &&
        !manager.busy &&
        !manager.syncing &&
        !manager.unresolvedRedemption &&
        manager.code.trim().isNotEmpty) {
      await manager.checkCode();
    }
  }

  Future<void> _logout() async {
    _password.clear();
    await manager.logout();
    if (!mounted || manager.loggedIn) return;
    _email.clear();
    _code.clear();
    if (!_obscurePassword || _historyExpanded) {
      setState(() {
        _obscurePassword = true;
        _historyExpanded = false;
      });
    }
  }

  Future<void> _open(Uri uri) async {
    if (_openingExternalLink) return;
    _openingExternalLink = true;
    try {
      await widget.openLink(uri);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.purchaseOpenLinkFailed)),
      );
    } finally {
      _openingExternalLink = false;
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
    if (!mounted) return;
    final extracted = extractRedemptionCodeFromClipboard(raw);
    if (extracted == null || extracted.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.purchaseClipboardEmpty)));
      return;
    }
    _lastAutoDetectedClipboard = raw;
    _lastHandledNormalizedCode = extracted;
    _code.value = TextEditingValue(
      text: extracted,
      selection: TextSelection.collapsed(offset: extracted.length),
    );
    manager.setCode(extracted);
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
    if (_isRealManager && _resolvePlanStoreUrl(plan) == null) {
      unawaited(
        manager.ensurePurchaseChannels(force: manager.channelError != null),
      );
    }
    final hasChatwoot = _purchaseChannels?.hasChatwoot ?? false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => _AcquirePlanSheet(
        plan: plan,
        manager: manager,
        wechatContacts: _wechatContacts,
        openLink: widget.openLink,
        onOpenSupport: hasChatwoot
            ? (draft) {
                Navigator.of(sheetContext).maybePop();
                unawaited(_openSupport(initialDraft: draft));
              }
            : null,
      ),
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
                        child: KeyedSubtree(
                          key: _catalogAnchor,
                          child: PurchasePlanCatalog(
                            catalog: manager.planCatalog,
                            loading: manager.plansLoading,
                            failed: manager.plansError != null,
                            retry: manager.loadPlans,
                            openLink: _open,
                            onBuyPlan: _handleBuyPlan,
                            onAcquirePlan: _showAcquireSheet,
                            buyingPlanId: _buyingPlanId,
                            collapsibleDetails: true,
                          ),
                        ),
                      );

                      final workbenchPane = FocusTraversalGroup(
                        child: KeyedSubtree(
                          key: _workbenchAnchor,
                          child: Column(
                            key: const Key('purchase-workbench'),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_handoffPlan != null &&
                                  manager.receipt == null &&
                                  !manager.unresolvedRedemption) ...[
                                _handoffBanner(_handoffPlan!),
                                const SizedBox(height: 12),
                              ],
                              if (!manager.loggedIn &&
                                  manager.receipt != null) ...[
                                _receiptCard(
                                  manager.receipt!,
                                  showOpenProfiles: false,
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primaryContainer.withValues(alpha: 0.22),
            colors.surfaceContainerLow,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.primary.withValues(alpha: 0.28)),
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
                constraints: const BoxConstraints(maxWidth: 740),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          l.purchaseCenterTitle,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: manager.subscriptionSynced
                                ? colors.primary.withValues(alpha: 0.16)
                                : colors.tertiaryContainer
                                    .withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            manager.subscriptionSynced
                                ? l.purchaseHeaderSyncedBadge
                                : l.purchaseHeaderTrialBadge,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: manager.subscriptionSynced
                                  ? colors.primary
                                  : colors.onTertiaryContainer,
                            ),
                          ),
                        ),
                      ],
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
              if (showQuickJump || (_purchaseChannels?.hasChatwoot ?? false))
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_purchaseChannels?.hasChatwoot ?? false)
                      FilledButton.tonalIcon(
                        key: const Key('purchase-header-support'),
                        onPressed: _openSupport,
                        icon: const Icon(Icons.support_agent_rounded, size: 18),
                        label: Text(l.purchaseOnlineSupport),
                      ),
                    if (showQuickJump)
                      FilledButton.tonalIcon(
                        key: const Key('purchase-jump-workbench'),
                        onPressed: _jumpToWorkbench,
                        icon: const Icon(Icons.bolt_rounded, size: 18),
                        label: Text(l.purchaseJumpToWorkbench),
                      ),
                  ],
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

  Widget _handoffBanner(XboardPlanOffer plan) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      key: const Key('purchase-handoff-banner'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.primary.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.bolt_rounded, size: 20, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.purchaseHandoffTitle(plan.name),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                key: const Key('purchase-handoff-dismiss'),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: _isRealManager ? manager.clearPlanHandoff : null,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l.purchaseHandoffDescription,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: const Key('purchase-handoff-paste'),
              onPressed: manager.busy ||
                      manager.syncing ||
                      manager.unresolvedRedemption
                  ? null
                  : _pasteAndCheckHandoff,
              icon: const Icon(Icons.content_paste_go_rounded, size: 18),
              label: Text(l.purchaseHandoffPasteAction),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _resolveWhitelistSuffixChips(XboardGuestAuthConfig config) {
    if (config.emailWhitelistSuffix.isEmpty) return const [];
    final normalized = <String>[];
    for (final entry in config.emailWhitelistSuffix) {
      var domain = entry.trim().toLowerCase();
      while (domain.startsWith('@')) {
        domain = domain.substring(1).trim();
      }
      if (domain.isNotEmpty && !normalized.contains(domain)) {
        normalized.add(domain);
      }
    }
    if (normalized.isEmpty) return const [];
    final ordered = <String>[
      for (final preferred in _preferredEmailDomains)
        if (normalized.contains(preferred)) preferred,
      for (final other in normalized)
        if (!_preferredEmailDomains.contains(other)) other,
    ];
    return ordered.take(6).toList(growable: false);
  }

  void _applyEmailSuffix(String domain) {
    final raw = _email.text.trim();
    final atIndex = raw.indexOf('@');
    final localPart = atIndex >= 0 ? raw.substring(0, atIndex) : raw;
    final updated = '$localPart@$domain';
    _email.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
    );
  }

  void _switchAuthMode({
    required bool registerMode,
    required bool forgotMode,
  }) {
    final savedEmail = _email.value;
    final savedPassword = _password.value;
    setState(() {
      _isRegisterMode = registerMode;
      _isForgotPasswordMode = forgotMode;
      _codeSentNotice = false;
      _localEmailError = null;
    });
    _loginForm.currentState?.reset();
    _email.value = savedEmail;
    _password.value = savedPassword;
    if (_isRealManager) {
      manager
        ..clearError()
        ..clearPasswordResetState();
    }
  }

  Widget _buildEmailCodeRow({
    required Key fieldKey,
    required Key buttonKey,
    required bool forReset,
  }) {
    final field = TextFormField(
      key: fieldKey,
      controller: _emailCode,
      enabled: !manager.busy,
      decoration: _inputDecoration(
        context,
        labelText: l.purchaseEmailCode,
        prefixIcon: Icons.mark_email_read_outlined,
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      textInputAction: TextInputAction.next,
      validator: (value) =>
          value != null && RegExp(r'^\d{6}$').hasMatch(value.trim())
              ? null
              : l.purchaseEmailCodeRequired,
    );

    final sendButton = ValueListenableBuilder<int>(
      valueListenable: _cooldownSeconds,
      builder: (context, seconds, _) {
        final sending = _isRealManager && manager.sendingEmailCode;
        final disabled = manager.busy || sending || seconds > 0;
        final label = sending
            ? l.purchaseSendingCode
            : (seconds > 0
                ? l.purchaseSendCodeCooldown(seconds)
                : l.purchaseSendCode);
        return FilledButton.tonal(
          key: buttonKey,
          onPressed: disabled
              ? null
              : () => _sendEmailVerificationCode(forReset: forReset),
          child: Text(label),
        );
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        if (constraints.maxWidth < 260 * scale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field,
              const SizedBox(height: 8),
              sendButton,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: field),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: sendButton,
            ),
          ],
        );
      },
    );
  }

  Widget _loginSection() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final registerSupported =
        _isRealManager && manager.api is XboardExtendedApi;
    final passportSupported =
        _isRealManager && manager.api is XboardPassportApi;
    final inForgotMode = passportSupported && _isForgotPasswordMode;
    final inRegisterMode = registerSupported && !inForgotMode && _isRegisterMode;
    final authConfig = _guestAuthConfig;
    final needRegisterEmailCode = inRegisterMode &&
        passportSupported &&
        (authConfig.isEmailVerify || manager.emailVerifyRequiredByServer);
    final needRegisterInviteCode = inRegisterMode &&
        passportSupported &&
        (authConfig.isInviteForce ||
            manager.inviteCodeRequiredByServer ||
            _showInviteField);
    final suffixChips = inRegisterMode && passportSupported
        ? _resolveWhitelistSuffixChips(authConfig)
        : const <String>[];
    final showCaptchaFallback = (inRegisterMode && authConfig.isCaptcha) ||
        manager.error?.code == 'register_web_required';

    return _Section(
      icon: inForgotMode
          ? Icons.lock_reset_rounded
          : (inRegisterMode
              ? Icons.person_add_alt_1_rounded
              : Icons.person_outline_rounded),
      title: inForgotMode
          ? l.purchaseResetPasswordTitle
          : (inRegisterMode ? l.purchaseAuthTabRegister : l.purchaseLoginTitle),
      child: AutofillGroup(
        child: Form(
          key: _loginForm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (registerSupported && !inForgotMode) ...[
                Container(
                  key: const Key('purchase-auth-mode-tabs'),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: LayoutBuilder(
                    builder: (context, tabConstraints) {
                      final scale = MediaQuery.textScalerOf(context).scale(1);
                      final stackTabs = tabConstraints.maxWidth < 240 * scale;
                      final loginTab = _AuthModeTabButton(
                        key: const Key('purchase-auth-tab-login'),
                        label: l.purchaseAuthTabLogin,
                        icon: Icons.login_rounded,
                        selected: !inRegisterMode,
                        enabled: !manager.busy,
                        onTap: () {
                          if (!inRegisterMode) return;
                          _switchAuthMode(
                            registerMode: false,
                            forgotMode: false,
                          );
                        },
                      );
                      final registerTab = _AuthModeTabButton(
                        key: const Key('purchase-auth-tab-register'),
                        label: l.purchaseAuthTabRegister,
                        icon: Icons.card_giftcard_rounded,
                        selected: inRegisterMode,
                        enabled: !manager.busy,
                        onTap: () {
                          if (inRegisterMode) return;
                          _switchAuthMode(
                            registerMode: true,
                            forgotMode: false,
                          );
                        },
                      );
                      if (stackTabs) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            loginTab,
                            const SizedBox(height: 4),
                            registerTab,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: loginTab),
                          const SizedBox(width: 4),
                          Expanded(child: registerTab),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: inForgotMode
                      ? colors.secondaryContainer.withValues(alpha: 0.45)
                      : (inRegisterMode
                          ? colors.tertiaryContainer.withValues(alpha: 0.45)
                          : colors.primaryContainer.withValues(alpha: 0.35)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      inForgotMode
                          ? Icons.mark_email_unread_outlined
                          : (inRegisterMode
                              ? Icons.rocket_launch_outlined
                              : Icons.verified_user_outlined),
                      size: 18,
                      color: inForgotMode
                          ? colors.secondary
                          : (inRegisterMode ? colors.tertiary : colors.primary),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        inForgotMode
                            ? l.purchaseResetPasswordDescription
                            : (inRegisterMode
                                ? l.purchaseRegisterTrialBanner
                                : l.purchaseLoginDescription),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
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
                onChanged: (_) {
                  if (_localEmailError != null) {
                    setState(() => _localEmailError = null);
                  }
                },
                validator: (value) => _validateEmailInput(
                  value,
                  checkRegisterPolicy: inRegisterMode && passportSupported,
                ),
              ),
              if (suffixChips.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  key: const Key('purchase-email-suffix-strip'),
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final domain in suffixChips)
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: Text('@$domain'),
                        onPressed: manager.busy
                            ? null
                            : () => _applyEmailSuffix(domain),
                      ),
                  ],
                ),
              ],
              if (needRegisterEmailCode) ...[
                const SizedBox(height: 12),
                _buildEmailCodeRow(
                  fieldKey: const Key('purchase-register-email-code'),
                  buttonKey: const Key('purchase-register-send-code'),
                  forReset: false,
                ),
              ],
              if (inForgotMode) ...[
                const SizedBox(height: 12),
                _buildEmailCodeRow(
                  fieldKey: const Key('purchase-reset-email-code'),
                  buttonKey: const Key('purchase-reset-send-code'),
                  forReset: true,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('purchase-reset-new-password'),
                  controller: _newPassword,
                  enabled: !manager.busy,
                  decoration: _inputDecoration(
                    context,
                    labelText: l.purchaseNewPassword,
                    prefixIcon: Icons.lock_reset_rounded,
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
                  autofillHints: const [AutofillHints.newPassword],
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return l.purchasePasswordRequired;
                    }
                    if (value.length < 8) {
                      return l.purchasePasswordMinLength;
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) async => _submitResetPassword(),
                ),
              ] else ...[
                const SizedBox(height: 12),
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
                  textInputAction: needRegisterInviteCode
                      ? TextInputAction.next
                      : TextInputAction.done,
                  autofillHints: [
                    if (inRegisterMode)
                      AutofillHints.newPassword
                    else
                      AutofillHints.password,
                  ],
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return l.purchasePasswordRequired;
                    }
                    if (inRegisterMode && value.length < 8) {
                      return l.purchasePasswordMinLength;
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) async =>
                      inRegisterMode ? _register() : _login(),
                ),
              ],
              if (needRegisterInviteCode) ...[
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('purchase-register-invite-code'),
                  controller: _inviteCode,
                  enabled: !manager.busy,
                  decoration: _inputDecoration(
                    context,
                    labelText: l.purchaseInviteCode,
                    prefixIcon: Icons.confirmation_number_outlined,
                  ),
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  validator: (value) {
                    final requiredByPolicy = authConfig.isInviteForce ||
                        manager.inviteCodeRequiredByServer;
                    if (requiredByPolicy &&
                        (value == null || value.trim().isEmpty)) {
                      return l.purchaseInviteCodeRequired;
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) async => _register(),
                ),
              ] else if (inRegisterMode && passportSupported) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('purchase-invite-toggle'),
                    onPressed: manager.busy
                        ? null
                        : () => setState(() => _showInviteField = true),
                    child: Text(l.purchaseInviteCodeOptionalToggle),
                  ),
                ),
              ],
              if (inRegisterMode &&
                  passportSupported &&
                  authConfig.tosUrl != null) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      l.purchaseTosAgreementPrefix,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    InkWell(
                      key: const Key('purchase-register-tos-link'),
                      onTap: () => _open(authConfig.tosUrl!),
                      child: Text(
                        l.purchaseTosLinkLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_localEmailError != null) ...[
                const SizedBox(height: 10),
                _Notice(message: _localEmailError!, error: true),
              ],
              if (_codeSentNotice && manager.error == null) ...[
                const SizedBox(height: 10),
                _Notice(message: l.purchaseCodeSentNotice, success: true),
              ],
              if (!inForgotMode &&
                  !inRegisterMode &&
                  _isRealManager &&
                  manager.passwordResetSucceeded &&
                  manager.error == null) ...[
                const SizedBox(height: 10),
                KeyedSubtree(
                  key: const Key('purchase-reset-success-notice'),
                  child: _Notice(
                    message: l.purchaseResetPasswordSuccess,
                    success: true,
                  ),
                ),
              ],
              if (showCaptchaFallback) ...[
                const SizedBox(height: 10),
                _Notice(message: l.purchaseCaptchaRequiredNotice),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('purchase-auth-web-fallback'),
                  onPressed: () => _open(
                    manager.api.baseUri.replace(fragment: '/register'),
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(l.purchaseOpenWebAuth),
                ),
              ],
              if (manager.error != null) ...[
                const SizedBox(height: 12),
                _Notice(message: _errorMessage(manager.error!), error: true),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: manager.busy ? null : manager.refresh,
                    child: Text(l.purchaseRefresh),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (inForgotMode) ...[
                FilledButton.icon(
                  key: const Key('purchase-reset-submit'),
                  onPressed: manager.busy ? null : _submitResetPassword,
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: Text(
                    _resettingPassword || manager.busy
                        ? l.purchaseResettingPassword
                        : l.purchaseResetPasswordSubmit,
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('purchase-reset-back-to-login'),
                    onPressed: manager.busy
                        ? null
                        : () => _switchAuthMode(
                              registerMode: false,
                              forgotMode: false,
                            ),
                    child: Text(l.purchaseBackToLogin),
                  ),
                ),
              ] else if (inRegisterMode)
                FilledButton.icon(
                  key: const Key('purchase-register-submit'),
                  onPressed: manager.busy ? null : _register,
                  icon: const Icon(Icons.rocket_launch_rounded, size: 18),
                  label: Text(
                    _registering || manager.busy
                        ? l.purchaseRegistering
                        : l.purchaseRegisterSubmit,
                  ),
                )
              else ...[
                FilledButton.icon(
                  key: const Key('purchase-login'),
                  onPressed: manager.busy ? null : _login,
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: Text(
                    manager.busy ? l.purchaseLoggingIn : l.purchaseLogin,
                  ),
                ),
                const SizedBox(height: 4),
                if (!registerSupported)
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
                          manager.api.baseUri
                              .replace(fragment: '/forgetpassword'),
                        ),
                        child: Text(l.purchaseRecoverPassword),
                      ),
                    ],
                  )
                else if (passportSupported)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const Key('purchase-auth-forgot-trigger'),
                      onPressed: manager.busy
                          ? null
                          : () => _switchAuthMode(
                                registerMode: false,
                                forgotMode: true,
                              ),
                      child: Text(l.purchaseForgotPassword),
                    ),
                  )
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => _open(
                        manager.api.baseUri
                            .replace(fragment: '/forgetpassword'),
                      ),
                      child: Text(l.purchaseRecoverPassword),
                    ),
                  ),
              ],
              if (_isRealManager && !inForgotMode) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1),
                ),
                Text(
                  l.purchasePreloginCodeHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('purchase-prelogin-code'),
                  controller: _code,
                  enabled: !manager.busy,
                  inputFormatters: const [_UpperCaseCodeFormatter()],
                  style: TextStyle(
                    fontFamily: FontFamily.jetBrainsMono.value,
                    fontFamilyFallback: _cjkMonoFallback(theme),
                    letterSpacing: 1.05,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: _inputDecoration(
                    context,
                    labelText: l.purchaseCode,
                    prefixIcon: Icons.confirmation_number_outlined,
                    suffixIcon: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _code,
                      builder: (context, codeValue, _) {
                        final hasCodeText =
                            codeValue.text.isNotEmpty || manager.code.isNotEmpty;
                        return hasCodeText
                            ? IconButton(
                                key: const Key('purchase-prelogin-code-clear'),
                                tooltip: l.purchaseClearCode,
                                onPressed: manager.busy
                                    ? null
                                    : () {
                                        if (manager.code.isNotEmpty) {
                                          _lastHandledNormalizedCode =
                                              manager.code;
                                        }
                                        _code.clear();
                                        manager.setCode('');
                                      },
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                ),
                              )
                            : IconButton(
                                key: const Key('purchase-prelogin-code-paste'),
                                tooltip: l.paste,
                                onPressed: manager.busy ? null : _pasteCode,
                                icon: const Icon(
                                  Icons.content_paste_rounded,
                                  size: 18,
                                ),
                              );
                      },
                    ),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (value) {
                    _updatingCodeFromInput = true;
                    try {
                      manager.setCode(value);
                    } finally {
                      _updatingCodeFromInput = false;
                    }
                  },
                ),
              ],
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
            _receiptCard(receipt, showOpenProfiles: true),
            const SizedBox(height: 16),
          ],
          TextField(
            key: const Key('purchase-code'),
            controller: _code,
            enabled: !locked,
            inputFormatters: const [_UpperCaseCodeFormatter()],
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
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _code,
                builder: (context, codeValue, _) {
                  final hasCodeText =
                      codeValue.text.isNotEmpty || manager.code.isNotEmpty;
                  return hasCodeText
                      ? IconButton(
                          key: const Key('purchase-code-clear'),
                          tooltip: l.purchaseClearCode,
                          onPressed: locked
                              ? null
                              : () {
                                  if (manager.code.isNotEmpty) {
                                    _lastHandledNormalizedCode = manager.code;
                                  }
                                  _code.clear();
                                  manager.setCode('');
                                },
                          icon: const Icon(Icons.close_rounded, size: 18),
                        )
                      : IconButton(
                          key: const Key('purchase-code-paste'),
                          tooltip: l.paste,
                          onPressed: locked ? null : _pasteCode,
                          icon: const Icon(
                            Icons.content_paste_rounded,
                            size: 18,
                          ),
                        );
                },
              ),
            ),
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.search,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (value) {
              _updatingCodeFromInput = true;
              try {
                manager.setCode(value);
              } finally {
                _updatingCodeFromInput = false;
              }
            },
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

  Widget _receiptCard(
    GiftReceipt receipt, {
    required bool showOpenProfiles,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
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
            message: '${l.purchaseSuccess}\n${l.purchaseSuccessDescription}',
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
          if (showOpenProfiles) ...[
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
          MergeSemantics(
            key: const Key('purchase-history-toggle'),
            child: Semantics(
              button: true,
              expanded: _historyExpanded,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () =>
                    setState(() => _historyExpanded = !_historyExpanded),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
                          onPressed:
                              manager.busy || history.page >= history.lastPage
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
    final chatUrl = _purchaseChannels?.resolveChatwootWidgetUrl();
    final hasSelfServiceRow = manager.cardStoreUrl != null || chatUrl != null;

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
          if (manager.channelError != null && !hasSelfServiceRow) ...[
            const SizedBox(height: 12),
            _Notice(message: l.purchaseChannelError),
          ],
          if (hasSelfServiceRow) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (manager.cardStoreUrl != null)
                  OutlinedButton.icon(
                    key: const Key('purchase-support-store'),
                    onPressed: () => _open(manager.cardStoreUrl!),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(l.purchaseCardStore),
                  ),
                if (chatUrl != null)
                  FilledButton.tonalIcon(
                    key: const Key('purchase-support-chat'),
                    onPressed: _openSupport,
                    icon: const Icon(Icons.forum_outlined, size: 18),
                    label: Text(l.purchaseOnlineSupport),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Text(
            l.purchaseBackupContactsLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
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

  String _date(DateTime value) {
    final local = value.toLocal();
    final material = MaterialLocalizations.of(context);
    final time = material.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return '${material.formatFullDate(local)} $time';
  }

  String _errorMessage(XboardException error) {
    final retryAfter = error.retryAfterSeconds;
    return switch (error.code) {
      'purchase_failed' => l.purchaseGenericError,
      'secure_storage_failed' => l.purchaseStorageError,
      'purchase_account_unsupported' => l.purchaseUnsupportedAccount,
      'logout_remote_failed' => l.purchaseLogoutRemoteError,
      'gift_code_format' => l.purchaseCodeFormatError,
      'gift_result_unconfirmed' => l.purchaseUnresolvedDescription,
      'subscription_sync_failed' => l.purchaseSyncError,
      'email_exists' => l.purchaseEmailExistsError,
      'email_domain_not_allowed' => l.purchaseEmailDomainError,
      'gmail_alias_not_allowed' => l.purchaseGmailAliasError,
      'registration_closed' => l.purchaseRegistrationClosedError,
      'register_web_required' => l.purchaseRegisterWebRequiredError,
      'invitation_code_required' => l.purchaseInviteCodeRequiredError,
      'invitation_code_invalid' => l.purchaseInviteCodeInvalidError,
      'invitation_unavailable' => l.purchaseInvitationUnavailableError,
      'registration_email_invalid' ||
      'password_reset_invalid' =>
        l.purchaseEmailCodeInvalidError,
      'registration_email_locked' ||
      'password_reset_locked' =>
        l.purchaseEmailCodeLockedError,
      'registration_email_cooldown' ||
      'password_reset_cooldown' ||
      'passport_email_cooldown' =>
        retryAfter != null
            ? l.purchaseCooldownWithSecondsError(retryAfter)
            : l.purchaseEmailCooldownError,
      'registration_email_rate_limited' ||
      'password_reset_rate_limited' ||
      'passport_email_rate_limited' ||
      'rate_limited' =>
        retryAfter != null
            ? l.purchaseCooldownWithSecondsError(retryAfter)
            : l.purchaseEmailRateLimitedError,
      'registration_email_disabled' => l.purchaseEmailVerifyDisabledError,
      'mail_unavailable' => l.purchaseMailUnavailableError,
      _ => error.message.trim().isEmpty ? l.purchaseGenericError : error.message,
    };
  }

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

String _formatMinorAmount(int amount) =>
    '${amount ~/ 100}.${(amount % 100).toString().padLeft(2, '0')}';

String _formatPeriodLabel(AppLocalizations l, String period) =>
    switch (period) {
      'monthly' => l.purchasePeriodMonthly,
      'quarterly' => l.purchasePeriodQuarterly,
      'half_yearly' => l.purchasePeriodHalfYearly,
      'yearly' => l.purchasePeriodYearly,
      'two_yearly' => l.purchasePeriodTwoYearly,
      'three_yearly' => l.purchasePeriodThreeYearly,
      'onetime' => l.purchasePeriodOnetime,
      _ => period,
    };

class _AcquirePlanSheet extends StatefulWidget {
  const _AcquirePlanSheet({
    required this.plan,
    required this.manager,
    required this.wechatContacts,
    required this.openLink,
    this.onOpenSupport,
  });

  final XboardPlanOffer plan;
  final PurchaseManager manager;
  final List<String> wechatContacts;
  final Future<void> Function(Uri) openLink;
  final void Function(String inquiryText)? onOpenSupport;

  @override
  State<_AcquirePlanSheet> createState() => _AcquirePlanSheetState();
}

class _AcquirePlanSheetState extends State<_AcquirePlanSheet> {
  String? _copiedKey;
  String? _feedbackMessage;
  bool _feedbackError = false;

  Future<void> _copy(String key, String value, String successMessage) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    setState(() {
      _copiedKey = key;
      _feedbackMessage = successMessage;
      _feedbackError = false;
    });
  }

  Future<void> _open(Uri uri, String errorMessage) async {
    try {
      await widget.openLink(uri);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _feedbackMessage = errorMessage;
        _feedbackError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.manager,
        builder: (context, _) {
          final l = AppLocalizations.of(context);
          final theme = Theme.of(context);
          final colors = theme.colorScheme;
          final plan = widget.plan;
          final priceSummary = plan.prices
              .map(
                (price) =>
                    '${_formatPeriodLabel(l, price.period)} ${_formatMinorAmount(price.amount)}',
              )
              .join(' / ');
          final inquiryText = l.purchaseInquiryTemplate(
            plan.name,
            plan.transferGiB,
            priceSummary,
          );
          final regionBadge = resolvePlanRegionBadge(plan.name);
          final storeUrl = PurchaseManager.isRealInstance(widget.manager)
              ? widget.manager.resolvePlanStoreUrl(plan)
              : (XboardPurchaseChannels.extractPlanContentPurchaseUrl(
                      plan.content) ??
                  widget.manager.cardStoreUrl);

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
                      if (regionBadge != null) ...[
                        EmojiText(
                          regionBadge,
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
                      IconButton(
                        key: const Key('purchase-acquire-close'),
                        tooltip: MaterialLocalizations.of(context)
                            .closeButtonTooltip,
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
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
                  if (widget.manager.channelError != null && storeUrl == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _Notice(message: l.purchaseChannelError),
                    ),
                  if (_feedbackMessage != null)
                    Padding(
                      key: const Key('purchase-acquire-feedback'),
                      padding: const EdgeInsets.only(top: 12),
                      child: _Notice(
                        message: _feedbackMessage!,
                        error: _feedbackError,
                        success: !_feedbackError,
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (storeUrl != null) ...[
                    FilledButton.icon(
                      key: const Key('purchase-acquire-store'),
                      onPressed: () {
                        if (PurchaseManager.isRealInstance(widget.manager)) {
                          widget.manager.markPlanHandoff(plan);
                        }
                        unawaited(
                          _open(
                            storeUrl,
                            l.purchaseOpenLinkFailed,
                          ),
                        );
                      },
                      icon: const Icon(Icons.storefront_rounded, size: 18),
                      label: Text(l.purchaseCardStore),
                    ),
                    const SizedBox(height: 10),
                  ],
                  FilledButton.tonalIcon(
                    key: const Key('purchase-acquire-copy-inquiry'),
                    onPressed: () =>
                        _copy('inquiry', inquiryText, l.copySuccess),
                    icon: Icon(
                      _copiedKey == 'inquiry'
                          ? Icons.check_rounded
                          : Icons.chat_bubble_outline_rounded,
                      size: 18,
                    ),
                    label: Text(l.purchaseCopyInquiry),
                  ),
                  if (widget.onOpenSupport != null) ...[
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      key: const Key('purchase-acquire-open-support'),
                      onPressed: () => widget.onOpenSupport!(inquiryText),
                      icon: const Icon(Icons.support_agent_rounded, size: 18),
                      label: Text(l.purchaseAcquireOpenSupport),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  for (final account in widget.wechatContacts)
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
                              onPressed: () => _copy(
                                  'wechat:$account', account, l.copySuccess),
                              icon: Icon(
                                _copiedKey == 'wechat:$account'
                                    ? Icons.check_rounded
                                    : Icons.copy_rounded,
                                size: 16,
                              ),
                              label: Text(l.copy),
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

class _AuthModeTabButton extends StatelessWidget {
  const _AuthModeTabButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        enabled: enabled,
        child: Material(
          color: selected ? colors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          elevation: selected ? 1 : 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? colors.onSurface : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
