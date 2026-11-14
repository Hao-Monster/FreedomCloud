import 'dart:async';

import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/manager/support_manager.dart';
import 'package:flclashx/models/chatwoot.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/widgets/side_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final Expando<bool> _activeSupportSheets = Expando<bool>('activeSupportSheet');

Uri? _resolveEffectiveExternalUri(
  ChatwootChannelConfig? config, {
  required String locale,
  Uri? fallback,
}) {
  if (config == null) return fallback;
  final base = config.baseUrl;
  final direct = XboardPurchaseChannels(
    chatwootBaseUrl: base,
    chatwootWebsiteToken: config.websiteToken,
  ).resolveChatwootWidgetUrl(locale: locale);
  if (direct != null) return direct;
  final rootResolved = XboardPurchaseChannels(
    chatwootBaseUrl: base.replace(path: '/'),
    chatwootWebsiteToken: config.websiteToken,
  ).resolveChatwootWidgetUrl(locale: locale);
  if (rootResolved == null) return fallback;
  var normalizedPath = base.path;
  while (normalizedPath.endsWith('/')) {
    normalizedPath = normalizedPath.substring(0, normalizedPath.length - 1);
  }
  final widgetPath = normalizedPath.isEmpty ? '/widget' : '$normalizedPath/widget';
  return rootResolved.replace(path: widgetPath);
}

/// Opens the native in-app customer support chat sheet.
///
/// Renders as a right-hand modal side sheet (without BackdropFilter) on wide
/// viewports (`width >= 600`) and a bottom modal sheet on compact screens.
Future<void> openSupportChatSheet(
  BuildContext context, {
  required SupportManager supportManager,
  Future<void> Function(Uri)? openLink,
  Uri? externalWidgetUri,
  String? initialDraft,
  List<String> wechatContacts = const ['ChasingDream_2021', 'dxm_qa'],
  Future<void> Function()? onRetryChannel,
}) async {
  if (_activeSupportSheets[supportManager] ?? false) return;
  _activeSupportSheets[supportManager] = true;
  int? sheetPanelToken;
  final width = MediaQuery.sizeOf(context).width;
  final surfaceColor = Theme.of(context).colorScheme.surface;
  try {
    if (width >= 600) {
      await showModalSideSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        constraints: const BoxConstraints(maxWidth: 440),
        backgroundColor: surfaceColor,
        filter: null,
        builder: (_) => SupportChatSheet(
          supportManager: supportManager,
          openLink: openLink,
          externalWidgetUri: externalWidgetUri,
          initialDraft: initialDraft,
          wechatContacts: wechatContacts,
          onRetryChannel: onRetryChannel,
          onPanelTokenAcquired: (token) => sheetPanelToken = token,
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: surfaceColor,
        builder: (sheetContext) => SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.86,
          child: SupportChatSheet(
            supportManager: supportManager,
            openLink: openLink,
            externalWidgetUri: externalWidgetUri,
            initialDraft: initialDraft,
            wechatContacts: wechatContacts,
            onRetryChannel: onRetryChannel,
            onPanelTokenAcquired: (token) => sheetPanelToken = token,
          ),
        ),
      );
    }
  } finally {
    _activeSupportSheets[supportManager] = null;
    if (sheetPanelToken != null) {
      await supportManager.closePanel(panelToken: sheetPanelToken);
    }
  }
}

/// Native pure-Flutter Chatwoot support chat panel.
class SupportChatSheet extends StatefulWidget {
  const SupportChatSheet({
    super.key,
    required this.supportManager,
    this.openLink,
    this.externalWidgetUri,
    this.initialDraft,
    this.wechatContacts = const ['ChasingDream_2021', 'dxm_qa'],
    this.onRetryChannel,
    this.onPanelTokenAcquired,
  });

  final SupportManager supportManager;
  final Future<void> Function(Uri)? openLink;
  final Uri? externalWidgetUri;
  final String? initialDraft;
  final List<String> wechatContacts;
  final Future<void> Function()? onRetryChannel;
  final ValueChanged<int>? onPanelTokenAcquired;

  @override
  State<SupportChatSheet> createState() => _SupportChatSheetState();
}

@immutable
class _MessageBodySnapshot {
  const _MessageBodySnapshot({
    required this.messages,
    required this.config,
    required this.hasMoreHistory,
    required this.isLoadingOlder,
  });

  factory _MessageBodySnapshot.fromManager(SupportManager manager) =>
      _MessageBodySnapshot(
        messages: List<ChatwootMessage>.unmodifiable(manager.messages),
        config: manager.channelConfig,
        hasMoreHistory: manager.hasMoreHistory,
        isLoadingOlder: manager.isLoadingOlder,
      );

  final List<ChatwootMessage> messages;
  final ChatwootChannelConfig? config;
  final bool hasMoreHistory;
  final bool isLoadingOlder;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _MessageBodySnapshot &&
          other.config == config &&
          other.hasMoreHistory == hasMoreHistory &&
          other.isLoadingOlder == isLoadingOlder &&
          listEquals(other.messages, messages);

  @override
  int get hashCode => Object.hash(
        config,
        hasMoreHistory,
        isLoadingOlder,
        Object.hashAll(messages),
      );
}

class _SupportChatSheetState extends State<SupportChatSheet> {
  late final TextEditingController _composer;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _showBackupWechat = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _retryingChannel = ValueNotifier<bool>(false);
  late final ValueNotifier<_MessageBodySnapshot> _bodyState;
  late int _panelToken;
  bool _isNearBottom = true;

  @override
  void initState() {
    super.initState();
    _panelToken = widget.supportManager.acquirePanelToken();
    widget.onPanelTokenAcquired?.call(_panelToken);
    final queuedDraft = widget.supportManager.takePendingDraft();
    final initialText = (widget.initialDraft?.trim().isNotEmpty ?? false)
        ? widget.initialDraft!
        : (queuedDraft ?? '');
    _composer = TextEditingController(text: initialText);
    _bodyState = ValueNotifier<_MessageBodySnapshot>(
      _MessageBodySnapshot.fromManager(widget.supportManager),
    );
    _scrollController.addListener(_onScroll);
    widget.supportManager.addListener(_onSupportManagerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(widget.supportManager.openPanel(panelToken: _panelToken));
    });
  }

  @override
  void didUpdateWidget(covariant SupportChatSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.supportManager != widget.supportManager) {
      final oldToken = _panelToken;
      oldWidget.supportManager.removeListener(_onSupportManagerChanged);
      unawaited(oldWidget.supportManager.closePanel(panelToken: oldToken));
      _panelToken = widget.supportManager.acquirePanelToken();
      widget.onPanelTokenAcquired?.call(_panelToken);
      widget.supportManager.addListener(_onSupportManagerChanged);
      _bodyState.value = _MessageBodySnapshot.fromManager(widget.supportManager);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(widget.supportManager.openPanel(panelToken: _panelToken));
      });
    }
  }

  @override
  void dispose() {
    widget.supportManager.removeListener(_onSupportManagerChanged);
    _showBackupWechat.dispose();
    _retryingChannel.dispose();
    _bodyState.dispose();
    _composer.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    unawaited(widget.supportManager.closePanel(panelToken: _panelToken));
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    _isNearBottom = pos.pixels <= 48.0;
    if (pos.maxScrollExtent > 0 &&
        pos.extentAfter <= 120.0 &&
        widget.supportManager.hasMoreHistory &&
        !widget.supportManager.isLoadingOlder) {
      unawaited(widget.supportManager.loadOlderMessages());
    }
  }

  void _onSupportManagerChanged() {
    final prev = _bodyState.value;
    final next = _MessageBodySnapshot.fromManager(widget.supportManager);
    if (prev != next) {
      final prevLastKey =
          prev.messages.isEmpty ? null : prev.messages.last.stableKey;
      final nextLastKey =
          next.messages.isEmpty ? null : next.messages.last.stableKey;
      final appendedNewBottomMessage = nextLastKey != null &&
          nextLastKey != prevLastKey &&
          next.messages.length >= prev.messages.length;
      _bodyState.value = next;
      if (appendedNewBottomMessage && _isNearBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
            _scrollController.jumpTo(0);
            _isNearBottom = true;
          }
        });
      }
    }
  }

  Future<void> _sendCurrentDraft() async {
    final manager = widget.supportManager;
    if (!manager.isConfigured || manager.isConversationLocked) return;
    final text = _composer.text;
    if (text.trim().isEmpty) return;
    _composer.clear();
    await manager.sendMessage(text);
    if (mounted && _scrollController.hasClients) {
      _scrollController.jumpTo(0);
      _isNearBottom = true;
    }
  }

  Future<void> _handleRefreshOrRetry() async {
    final manager = widget.supportManager;
    if (!manager.isConfigured && widget.onRetryChannel != null) {
      if (_retryingChannel.value) return;
      _retryingChannel.value = true;
      try {
        await widget.onRetryChannel!.call();
        if (mounted && manager.isConfigured) {
          await manager.openPanel(panelToken: _panelToken);
        }
      } finally {
        if (mounted) {
          _retryingChannel.value = false;
        }
      }
      return;
    }
    if (manager.error != null && manager.contact == null) {
      await manager.openPanel(panelToken: _panelToken);
      return;
    }
    await manager.refreshMessages();
  }

  Future<void> _openExternalFallback(Uri? uri) async {
    if (uri == null || widget.openLink == null) return;
    try {
      await widget.openLink!.call(uri);
    } catch (_) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.purchaseOpenLinkFailed)));
    }
  }

  Future<void> _copyWechat(String account) async {
    await Clipboard.setData(ClipboardData(text: account));
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l.copySuccess)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toString();
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final headerListenable =
        Listenable.merge([widget.supportManager, _retryingChannel]);
    final footerListenable = Listenable.merge([
      widget.supportManager,
      _retryingChannel,
      _showBackupWechat,
    ]);

    return Material(
      key: const Key('support-chat-sheet'),
      color: colors.surface,
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListenableBuilder(
                    listenable: headerListenable,
                    builder: (context, _) {
                      final manager = widget.supportManager;
                      final config = manager.channelConfig;
                      final effectiveExternalUri = _resolveEffectiveExternalUri(
                        config,
                        locale: localeTag,
                        fallback: widget.externalWidgetUri,
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SupportHeader(
                            title: (config?.websiteName?.trim().isNotEmpty ??
                                    false)
                                ? config!.websiteName!.trim()
                                : l.supportSheetTitle,
                            replyTime: config?.replyTime,
                            isConfigured: manager.isConfigured,
                            isRealtimeConnected: manager.isRealtimeConnected,
                            isConnecting:
                                manager.isConnecting || manager.isLoading,
                            showNewConversation: manager.isConversationLocked ||
                                manager.isConversationResolved,
                            externalWidgetUri: effectiveExternalUri,
                            onRefresh: _retryingChannel.value
                                ? null
                                : _handleRefreshOrRetry,
                            onNewConversation: manager.isConfigured
                                ? manager.startNewConversation
                                : null,
                            onOpenExternal: effectiveExternalUri != null &&
                                    widget.openLink != null
                                ? () =>
                                    _openExternalFallback(effectiveExternalUri)
                                : null,
                            onClose: () => Navigator.of(context).maybePop(),
                          ),
                          if (manager.isLoading || _retryingChannel.value)
                            const LinearProgressIndicator(minHeight: 2)
                          else
                            Divider(height: 1, color: colors.outlineVariant),
                        ],
                      );
                    },
                  ),
                  Expanded(
                    child: ValueListenableBuilder<_MessageBodySnapshot>(
                      valueListenable: _bodyState,
                      builder: (context, snapshot, _) => _SupportMessageBody(
                        manager: widget.supportManager,
                        snapshot: snapshot,
                        scrollController: _scrollController,
                      ),
                    ),
                  ),
                  ListenableBuilder(
                    listenable: widget.supportManager,
                    builder: (context, _) {
                      final manager = widget.supportManager;
                      return AnimatedSize(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        child: manager.isAgentTyping
                            ? Container(
                                key: const Key('support-typing-banner'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                color: colors.surfaceContainerLow,
                                child: Text(
                                  l.supportTypingIndicator(
                                    (manager.typingAgentName
                                                ?.trim()
                                                .isNotEmpty ??
                                            false)
                                        ? manager.typingAgentName!.trim()
                                        : l.supportTypingAnonymous,
                                  ),
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: colors.primary,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      );
                    },
                  ),
                  ListenableBuilder(
                    listenable: footerListenable,
                    builder: (context, _) {
                      final manager = widget.supportManager;
                      final showWechatPanel = _showBackupWechat.value ||
                          manager.error != null ||
                          !manager.isConfigured;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!manager.isConfigured)
                            _SupportNoticeBanner(
                              key: const Key('support-not-configured-banner'),
                              message: l.supportNotConfiguredNotice,
                              actionLabel: l.supportRetryAction,
                              onAction: _retryingChannel.value
                                  ? null
                                  : _handleRefreshOrRetry,
                            )
                          else if (manager.error != null)
                            _SupportNoticeBanner(
                              key: const Key('support-error-banner'),
                              message: _supportErrorText(l, manager.error!),
                              isError: true,
                              actionLabel: l.supportRetryAction,
                              onAction: _handleRefreshOrRetry,
                            ),
                          if (manager.isConversationLocked)
                            _SupportNoticeBanner(
                              key: const Key('support-locked-banner'),
                              message: l.supportConversationLockedNotice,
                              actionLabel: l.supportNewConversation,
                              actionKey:
                                  const Key('support-locked-new-conversation'),
                              onAction: manager.startNewConversation,
                            ),
                          if (showWechatPanel &&
                              widget.wechatContacts.isNotEmpty)
                            _BackupWechatStrip(
                              contacts: widget.wechatContacts,
                              onCopy: _copyWechat,
                            ),
                          _SupportFooterControls(
                            showBackupWechat: _showBackupWechat.value,
                            hasWechatContacts: widget.wechatContacts.isNotEmpty,
                            onToggleBackupWechat: () => _showBackupWechat.value =
                                !_showBackupWechat.value,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.outlineVariant),
            _SupportComposerBar(
              composer: _composer,
              supportManager: widget.supportManager,
              onSend: _sendCurrentDraft,
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportHeader extends StatelessWidget {
  const _SupportHeader({
    required this.title,
    required this.replyTime,
    required this.isConfigured,
    required this.isRealtimeConnected,
    required this.isConnecting,
    required this.showNewConversation,
    required this.externalWidgetUri,
    required this.onRefresh,
    required this.onNewConversation,
    required this.onOpenExternal,
    required this.onClose,
  });

  final String title;
  final String? replyTime;
  final bool isConfigured;
  final bool isRealtimeConnected;
  final bool isConnecting;
  final bool showNewConversation;
  final Uri? externalWidgetUri;
  final VoidCallback? onRefresh;
  final VoidCallback? onNewConversation;
  final VoidCallback? onOpenExternal;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l = AppLocalizations.of(context);

    final statusLabel = !isConfigured
        ? l.supportStatusOffline
        : isRealtimeConnected
            ? l.supportStatusConnected
            : isConnecting
                ? l.supportStatusConnecting
                : l.supportStatusOffline;
    final statusColor = !isConfigured
        ? colors.outline
        : isRealtimeConnected
            ? colors.primary
            : isConnecting
                ? colors.tertiary
                : colors.outline;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              statusLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (replyTime != null && replyTime!.trim().isNotEmpty)
                      Text(
                        replyTime!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (showNewConversation && onNewConversation != null)
            TextButton(
              key: const Key('support-new-conversation'),
              onPressed: onNewConversation,
              child: Text(l.supportNewConversation),
            ),
          IconButton(
            key: const Key('support-refresh'),
            tooltip: l.supportRefreshTooltip,
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
          if (externalWidgetUri != null)
            IconButton(
              key: const Key('support-open-external'),
              tooltip: l.supportOpenExternalFallback,
              onPressed: onOpenExternal,
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
            ),
          IconButton(
            key: const Key('support-close'),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _SupportMessageBody extends StatelessWidget {
  const _SupportMessageBody({
    required this.manager,
    required this.snapshot,
    required this.scrollController,
  });

  final SupportManager manager;
  final _MessageBodySnapshot snapshot;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final messages = snapshot.messages;
    final config = snapshot.config;
    final hasWelcome =
        (config?.welcomeTitle?.trim().isNotEmpty ?? false) ||
            (config?.welcomeTagline?.trim().isNotEmpty ?? false) ||
            messages.isEmpty;

    if (messages.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _WelcomeBanner(config: config),
      );
    }

    final showOlderHeader =
        snapshot.hasMoreHistory || snapshot.isLoadingOlder;
    final welcomeCount = hasWelcome ? 1 : 0;
    final olderCount = showOlderHeader ? 1 : 0;
    final itemCount = messages.length + welcomeCount + olderCount;
    return RepaintBoundary(
      child: ListView.builder(
        key: const Key('support-message-list'),
        controller: scrollController,
        reverse: true,
        addAutomaticKeepAlives: true,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (showOlderHeader && index == itemCount - 1) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Center(
                child: snapshot.isLoadingOlder
                    ? const SizedBox(
                        key: Key('support-loading-older'),
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        key: const Key('support-load-older'),
                        tooltip: l.supportRefreshTooltip,
                        onPressed: manager.loadOlderMessages,
                        icon: const Icon(Icons.expand_less_rounded, size: 20),
                      ),
              ),
            );
          }
          if (hasWelcome && index == messages.length) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _WelcomeBanner(config: config),
            );
          }
          final msg = messages[messages.length - 1 - index];
          return _MessageBubble(
            key: ValueKey('support-msg-${msg.stableKey}'),
            message: msg,
            onRetry: msg.echoId != null
                ? () => manager.retryMessage(msg.echoId!)
                : null,
          );
        },
      ),
    );
  }
}

class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner({required this.config});

  final ChatwootChannelConfig? config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final title = (config?.welcomeTitle?.trim().isNotEmpty ?? false)
        ? config!.welcomeTitle!.trim()
        : l.supportWelcomeFallbackTitle;
    final tagline = (config?.welcomeTagline?.trim().isNotEmpty ?? false)
        ? config!.welcomeTagline!.trim()
        : l.supportWelcomeFallbackSubtitle;

    return Container(
      key: const Key('support-welcome-banner'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.support_agent_rounded, size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tagline,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    this.onRetry,
  });

  final ChatwootMessage message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final timeStr = _formatMessageTime(message.createdAt);

    if (message.type == ChatwootMessageType.activity ||
        message.type == ChatwootMessageType.template) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${message.content} · $timeStr',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    final isVisitor = message.type == ChatwootMessageType.visitor;
    final bubbleColor = isVisitor
        ? colors.primaryContainer
        : colors.surfaceContainerHighest;
    final textColor =
        isVisitor ? colors.onPrimaryContainer : colors.onSurface;
    final metaColor = textColor.withValues(alpha: 0.7);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: isVisitor ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            crossAxisAlignment:
                isVisitor ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isVisitor &&
                  message.senderName != null &&
                  message.senderName!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                  child: Text(
                    message.senderName!.trim(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(14),
                    topRight: const Radius.circular(14),
                    bottomLeft: Radius.circular(isVisitor ? 14 : 4),
                    bottomRight: Radius.circular(isVisitor ? 4 : 14),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      message.content,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: textColor,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          timeStr,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: metaColor,
                            fontSize: 10.5,
                          ),
                        ),
                        if (isVisitor &&
                            message.deliveryState ==
                                ChatwootDeliveryState.sending) ...[
                          const SizedBox(width: 6),
                          Text(
                            l.supportMessageSending,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: metaColor,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                        if (isVisitor &&
                            message.deliveryState ==
                                ChatwootDeliveryState.failed) ...[
                          const SizedBox(width: 6),
                          Text(
                            l.supportMessageFailed,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.error,
                              fontWeight: FontWeight.w700,
                              fontSize: 10.5,
                            ),
                          ),
                          if (onRetry != null) ...[
                            const SizedBox(width: 2),
                            IconButton(
                              key: Key(
                                'support-retry-${message.echoId ?? message.stableKey}',
                              ),
                              tooltip: l.supportRetryAction,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              iconSize: 16,
                              color: colors.error,
                              onPressed: onRetry,
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatMessageTime(DateTime createdAt) {
    final local = createdAt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _SupportNoticeBanner extends StatelessWidget {
  const _SupportNoticeBanner({
    super.key,
    required this.message,
    this.isError = false,
    this.actionLabel,
    this.actionKey,
    this.onAction,
  });

  final String message;
  final bool isError;
  final String? actionLabel;
  final Key? actionKey;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bg = isError
        ? colors.errorContainer.withValues(alpha: 0.7)
        : colors.surfaceContainerHighest.withValues(alpha: 0.65);
    final fg = isError ? colors.onErrorContainer : colors.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: bg,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(color: fg),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              key: actionKey,
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class _BackupWechatStrip extends StatelessWidget {
  const _BackupWechatStrip({
    required this.contacts,
    required this.onCopy,
  });

  final List<String> contacts;
  final Future<void> Function(String) onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l = AppLocalizations.of(context);

    return Container(
      key: const Key('support-backup-wechat-strip'),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: colors.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.purchaseBackupContactsLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final account in contacts)
                ActionChip(
                  key: Key('support-wechat-copy-$account'),
                  avatar: const Icon(Icons.copy_rounded, size: 15),
                  label: Text('${l.wechatId}: $account'),
                  onPressed: () => onCopy(account),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SupportFooterControls extends StatelessWidget {
  const _SupportFooterControls({
    required this.showBackupWechat,
    required this.hasWechatContacts,
    required this.onToggleBackupWechat,
  });

  final bool showBackupWechat;
  final bool hasWechatContacts;
  final VoidCallback onToggleBackupWechat;

  @override
  Widget build(BuildContext context) {
    if (!hasWechatContacts) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Row(
        children: [
          Flexible(
            child: TextButton.icon(
              key: const Key('support-backup-wechat-toggle'),
              onPressed: onToggleBackupWechat,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                foregroundColor: colors.onSurfaceVariant,
              ),
              icon: Icon(
                showBackupWechat
                    ? Icons.expand_more_rounded
                    : Icons.qr_code_2_rounded,
                size: 16,
              ),
              label: Text(
                l.supportBackupWechatToggle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportComposerBar extends StatelessWidget {
  const _SupportComposerBar({
    required this.composer,
    required this.supportManager,
    required this.onSend,
  });

  final TextEditingController composer;
  final SupportManager supportManager;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: (_, event) {
                if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
                    (event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
                  final keys = HardwareKeyboard.instance.logicalKeysPressed;
                  final isShift = keys.contains(LogicalKeyboardKey.shiftLeft) ||
                      keys.contains(LogicalKeyboardKey.shiftRight);
                  final isModifier =
                      keys.contains(LogicalKeyboardKey.controlLeft) ||
                          keys.contains(LogicalKeyboardKey.controlRight) ||
                          keys.contains(LogicalKeyboardKey.altLeft) ||
                          keys.contains(LogicalKeyboardKey.altRight) ||
                          keys.contains(LogicalKeyboardKey.metaLeft) ||
                          keys.contains(LogicalKeyboardKey.metaRight);
                  final value = composer.value;
                  final isComposing =
                      value.isComposingRangeValid && !value.composing.isCollapsed;
                  if (!isShift && !isModifier && !isComposing) {
                    if (event is KeyDownEvent) {
                      onSend();
                    }
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: ListenableBuilder(
                listenable: supportManager,
                builder: (context, _) {
                  final canType = supportManager.isConfigured &&
                      !supportManager.isConversationLocked;
                  return TextField(
                    key: const Key('support-composer'),
                    controller: composer,
                    enabled: canType,
                    minLines: 1,
                    maxLines: 4,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: l.supportComposerHint,
                      filled: true,
                      fillColor:
                          colors.surfaceContainerHighest.withValues(alpha: 0.4),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: colors.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: colors.outlineVariant),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          ListenableBuilder(
            listenable: supportManager,
            builder: (context, _) => ValueListenableBuilder<TextEditingValue>(
              valueListenable: composer,
              builder: (context, value, _) {
                final hasText = value.text.trim().isNotEmpty;
                final canSend = hasText &&
                    supportManager.isConfigured &&
                    !supportManager.isConversationLocked;
                return IconButton.filled(
                  key: const Key('support-send'),
                  tooltip: l.supportSendTooltip,
                  onPressed: canSend ? onSend : null,
                  icon: const Icon(Icons.send_rounded, size: 18),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _supportErrorText(AppLocalizations l, ChatwootException error) {
  if (error.code == 'not_configured') return l.supportNotConfiguredNotice;
  if (error.isResolvedLocked) return l.supportConversationLockedNotice;
  return error.message.trim().isNotEmpty
      ? error.message
      : l.purchaseGenericError;
}
