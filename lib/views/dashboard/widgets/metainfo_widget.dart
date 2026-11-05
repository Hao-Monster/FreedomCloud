import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:emoji_regex/emoji_regex.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/profiles/add_profile.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

class MetainfoWidget extends ConsumerStatefulWidget {
  const MetainfoWidget({super.key});

  @override
  ConsumerState<MetainfoWidget> createState() => _MetainfoWidgetState();
}

class _MetainfoWidgetState extends ConsumerState<MetainfoWidget> {
  final Set<String> _syncingProfileIds = <String>{};
  final List<TapGestureRecognizer> _announceRecognizers =
      <TapGestureRecognizer>[];
  String? _cachedAnnounceSource;

  @override
  void dispose() {
    _disposeAnnounceRecognizers();
    super.dispose();
  }

  void _disposeAnnounceRecognizers() {
    for (final recognizer in _announceRecognizers) {
      recognizer.dispose();
    }
    _announceRecognizers.clear();
  }

  static bool _containsUnsafeHeaderChars(String text) => text.runes.any(
        (r) =>
            (r < 0x20 && r != 0x09 && r != 0x0A && r != 0x0D) ||
            r == 0x7F ||
            (r >= 0x80 && r <= 0x9F) ||
            r == 0xFFFD ||
            (r >= 0xD800 && r <= 0xDFFF) ||
            (r >= 0xE000 && r <= 0xF8FF) ||
            r >= 0xF0000 ||
            (r >= 0x202A && r <= 0x202E) ||
            (r >= 0x2066 && r <= 0x2069),
      );

  static String _truncateRunes(String text, int maxChars) {
    if (text.runes.length <= maxChars) return text;
    return '${String.fromCharCodes(text.runes.take(maxChars))}…';
  }

  static String? _sanitizeHeaderPlainText(String text, int maxChars) {
    final buffer = StringBuffer();
    for (final r in text.runes) {
      if ((r < 0x20 && r != 0x09 && r != 0x0A && r != 0x0D) ||
          r == 0x7F ||
          (r >= 0x80 && r <= 0x9F) ||
          r == 0xFFFD ||
          (r >= 0xD800 && r <= 0xDFFF) ||
          (r >= 0x202A && r <= 0x202E) ||
          (r >= 0x2066 && r <= 0x2069)) {
        continue;
      }
      buffer.writeCharCode(r);
    }
    final cleaned = buffer.toString().trim();
    if (cleaned.isEmpty) return null;
    return _truncateRunes(cleaned, maxChars);
  }

  static String? _decodeSafeHeaderText(String? raw, {int maxChars = 160}) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    var candidate = trimmed;
    final explicitBase64 = candidate.length >= 7 &&
        candidate.substring(0, 7).toLowerCase() == 'base64:';
    if (explicitBase64) {
      candidate = candidate.substring(7).trim();
      if (candidate.isEmpty) return null;
    }
    final looksLikeBase64Token = !explicitBase64 &&
        candidate.length >= 4 &&
        candidate.length % 4 != 1 &&
        RegExp(r'^[A-Za-z0-9+/_-]+={0,2}$').hasMatch(candidate) &&
        (candidate.endsWith('=') ||
            !RegExp(r'^[A-Za-z_-]+$').hasMatch(candidate));
    if (explicitBase64 || looksLikeBase64Token) {
      try {
        final normalized = base64.normalize(
          candidate.replaceAll('-', '+').replaceAll('_', '/'),
        );
        final decoded = utf8
            .decode(base64.decode(normalized), allowMalformed: false)
            .trim();
        if (decoded.isNotEmpty && !_containsUnsafeHeaderChars(decoded)) {
          if (explicitBase64) {
            return _truncateRunes(decoded, maxChars);
          }
          final hasNonAsciiUnicode = decoded.runes.any((r) => r > 0x9F);
          final isPaddedAscii = candidate.endsWith('=') &&
              RegExp(r'^[\x20-\x7E\r\n\t]+$').hasMatch(decoded);
          final isUnpaddedAsciiProse = !candidate.endsWith('=') &&
              candidate.length >= 12 &&
              !candidate.contains('-') &&
              !candidate.contains('_') &&
              decoded.contains(' ') &&
              RegExp(r'^[A-Za-z0-9 .,!?:;()\[\]\-/\r\n\t]+$')
                  .hasMatch(decoded);
          if (hasNonAsciiUnicode || isPaddedAscii || isUnpaddedAsciiProse) {
            return _truncateRunes(decoded, maxChars);
          }
        } else if (explicitBase64) {
          return null;
        }
      } catch (_) {
        if (explicitBase64) return null;
      }
    }
    return _sanitizeHeaderPlainText(trimmed, maxChars);
  }

  static DateTime? _parseSubscriptionExpireLocal(int rawExpire) {
    if (rawExpire <= 0) return null;
    final ms = rawExpire >= 100000000000 ? rawExpire : rawExpire * 1000;
    if (ms <= 0 || ms > 253402300799000) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  }

  static String _formatTraffic(int bytes) {
    final tv = TrafficValue(value: math.max(0, bytes));
    return '${tv.showValue} ${tv.showUnit}';
  }

  Widget _buildAdaptiveText(
    String text, {
    TextStyle? style,
    int? maxLines,
    TextOverflow? overflow,
  }) {
    if (emojiRegex().hasMatch(text)) {
      return EmojiText(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      );
    }
    return Text(
      text,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  List<InlineSpan> _emojiAwareSpans(String text, TextStyle? style) {
    final spans = <InlineSpan>[];
    final emoji = emojiRegex();
    var last = 0;
    for (final match in emoji.allMatches(text)) {
      if (match.start > last) {
        spans.add(
          TextSpan(
            text: text.substring(last, match.start),
            style: style,
          ),
        );
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: style?.copyWith(fontFamily: FontFamily.twEmoji.value),
        ),
      );
      last = match.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: style));
    }
    return spans;
  }

  List<InlineSpan> _buildAnnouncementSpans(
    BuildContext context,
    String announceText,
  ) {
    if (_cachedAnnounceSource != announceText) {
      _disposeAnnounceRecognizers();
      _cachedAnnounceSource = announceText;
    } else {
      _disposeAnnounceRecognizers();
    }

    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface,
      height: 1.38,
    );
    final linkStyle = baseStyle?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary.withValues(alpha: 0.6),
    );
    final urlPattern = RegExp(r'https?://[^\s]+', caseSensitive: false);
    final spans = <InlineSpan>[];
    var lastIndex = 0;

    for (final match in urlPattern.allMatches(announceText)) {
      if (match.start > lastIndex) {
        spans.addAll(
          _emojiAwareSpans(
            announceText.substring(lastIndex, match.start),
            baseStyle,
          ),
        );
      }
      final url = match.group(0)!;
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          unawaited(globalState.openUrl(url));
        };
      _announceRecognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: url,
          style: linkStyle,
          recognizer: recognizer,
        ),
      );
      lastIndex = match.end;
    }

    if (lastIndex < announceText.length) {
      spans.addAll(
        _emojiAwareSpans(
          announceText.substring(lastIndex),
          baseStyle,
        ),
      );
    }
    return spans;
  }

  Future<void> _handleSyncSubscription(Profile targetProfile) async {
    if (_syncingProfileIds.contains(targetProfile.id)) return;
    final current =
        ref.read(profilesProvider).getProfile(targetProfile.id) ??
            targetProfile;
    if (current.type != ProfileType.url || current.isUpdating) return;
    if (!globalState.isAppControllerReady) return;
    final appController = globalState.appController;

    setState(() {
      _syncingProfileIds.add(current.id);
    });
    try {
      await globalState.safeRun(silence: false, () async {
        try {
          appController.setProfile(
            current.copyWith(isUpdating: true),
          );
          await appController.updateProfile(current);
        } catch (_) {
          final latest = mounted
              ? ref.read(profilesProvider).getProfile(current.id)
              : globalState.config.profiles.getProfile(current.id);
          final rollback = rollbackFailedProfileUpdate(latest);
          if (rollback != null) {
            appController.setProfile(rollback);
          }
          rethrow;
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _syncingProfileIds.remove(current.id);
        });
      } else {
        _syncingProfileIds.remove(current.id);
      }
    }
  }

  Widget _buildServiceLogo(BuildContext context, String logoUrl) {
    const logoSize = 36.0;
    final fallback = Container(
      width: logoSize,
      height: logoSize,
      decoration: BoxDecoration(
        color: context.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.cloud_done_outlined,
        size: 20,
        color: context.colorScheme.primary,
      ),
    );

    final isSvg = logoUrl.toLowerCase().endsWith('.svg');
    final image = isSvg
        ? SvgPicture.network(
            logoUrl,
            width: logoSize,
            height: logoSize,
            placeholderBuilder: (_) => fallback,
          )
        : CachedNetworkImage(
            imageUrl: logoUrl,
            width: logoSize,
            height: logoSize,
            fit: BoxFit.cover,
            placeholder: (_, __) => fallback,
            errorWidget: (_, __, ___) => fallback,
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: image,
    );
  }

  Widget _buildTagPill(
    BuildContext context, {
    required IconData icon,
    required String text,
    Color? foreground,
    Color? background,
    Color? border,
    VoidCallback? onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    final fg = foreground ?? colors.onSurfaceVariant;
    final bg =
        background ?? colors.surfaceContainerHighest.withValues(alpha: 0.55);
    final bd = border ?? colors.outlineVariant.withValues(alpha: 0.45);

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: bd, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: _buildAdaptiveText(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: content,
      ),
    );
  }

  Widget _buildInfoTile(
    BuildContext context, {
    required IconData icon,
    required String text,
    Color? accentColor,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final fg = accentColor ?? colors.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accentColor != null
            ? accentColor.withValues(alpha: 0.10)
            : colors.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: accentColor != null
              ? accentColor.withValues(alpha: 0.30)
              : colors.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: _buildAdaptiveText(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: accentColor ?? colors.onSurface.withValues(alpha: 0.88),
                fontWeight:
                    accentColor != null ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            trailing,
          ],
        ],
      ),
    );
  }

  Widget _buildUpdateSubscriptionButton(
    BuildContext context, {
    required Profile profile,
    required bool isSyncing,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isSyncing
        ? colors.surfaceContainerHighest.withValues(alpha: 0.65)
        : colors.primary.withValues(alpha: isDark ? 0.20 : 0.12);
    final borderColor = isSyncing
        ? colors.outlineVariant.withValues(alpha: 0.5)
        : colors.primary.withValues(alpha: 0.42);
    final fgColor = isSyncing ? colors.onSurfaceVariant : colors.primary;

    return Semantics(
      button: true,
      enabled: !isSyncing,
      label: isSyncing
          ? appLocalizations.nodeOverviewUpdatingShort
          : appLocalizations.dashboardClickUpdateSubscription,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('metainfo-update-subscription-button'),
          borderRadius: BorderRadius.circular(8),
          onTap: isSyncing
              ? null
              : () => unawaited(_handleSyncSubscription(profile)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSyncing) ...[
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: fgColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    isSyncing
                        ? appLocalizations.nodeOverviewUpdatingShort
                        : appLocalizations.dashboardClickUpdateSubscription,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: fgColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ({String nodeName, String? testUrl})? _resolveActiveNode(
    Profile profile,
    List<Group> visibleGroups,
    List<Group> allGroups,
    SelectedMap selectedMap,
  ) {
    final sourceGroups =
        visibleGroups.isNotEmpty ? visibleGroups : allGroups;
    if (sourceGroups.isEmpty) return null;

    final serverInfoGroup = _decodeSafeHeaderText(
      profile.providerHeaders['flclashx-serverinfo'],
      maxChars: 80,
    );
    Group? group;
    if (serverInfoGroup != null && serverInfoGroup.isNotEmpty) {
      group = allGroups.getGroup(serverInfoGroup);
    }
    if (group == null && profile.currentGroupName != null) {
      group = sourceGroups.getGroup(profile.currentGroupName!);
    }
    group ??= sourceGroups.first;

    final selectedRaw =
        group.getCurrentSelectedName(selectedMap[group.name] ?? '');
    final resolved = allGroups.resolveToDisplayName(
      selectedRaw.isNotEmpty ? selectedRaw : group.realNow,
    );
    if (resolved.isEmpty) return null;
    return (nodeName: resolved, testUrl: group.testUrl);
  }

  int _countUniqueLeafProxies(List<Group> allGroups) {
    if (allGroups.isEmpty) return 0;
    final groupNames = allGroups.map((g) => g.name).toSet();
    const builtInLiterals = <String>{
      'DIRECT',
      'REJECT',
      'REJECT-DROP',
      'PASS',
      'COMPATIBLE',
    };
    final leafNames = <String>{};
    for (final group in allGroups) {
      for (final proxy in group.all) {
        if (!groupNames.contains(proxy.name) &&
            !builtInLiterals.contains(proxy.name.toUpperCase())) {
          leafNames.add(proxy.name);
        }
      }
    }
    return leafNames.length;
  }

  @override
  Widget build(BuildContext context) {
    final allProfiles = ref.watch(profilesProvider);
    final currentProfile = ref.watch(currentProfileProvider);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    if (allProfiles.isEmpty) {
      return CommonCard(
        onPressed: () async {
          final url = await globalState.showCommonDialog<String>(
            child: const URLFormDialog(),
          );
          if (url != null) {
            await globalState.appController.addProfileFormURL(url);
          }
        },
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.add_circle_outline,
                  size: 48,
                ),
                const SizedBox(height: 8),
                Text(appLocalizations.addProfile),
              ],
            ),
          ),
        ),
      );
    }

    if (currentProfile == null) {
      return const SizedBox.shrink();
    }

    final headers = currentProfile.providerHeaders;
    final announceText = _decodeSafeHeaderText(
      headers['announce'],
      maxChars: 500,
    );
    final profileTitle = (currentProfile.label?.trim().isNotEmpty ?? false)
        ? currentProfile.label!.trim()
        : currentProfile.id;
    final rawServiceName = _decodeSafeHeaderText(
      headers['flclashx-servicename'],
      maxChars: 80,
    );
    final serviceName = rawServiceName != null && rawServiceName != profileTitle
        ? rawServiceName
        : null;
    final serviceLogoUrl = _decodeSafeHeaderText(
      headers['flclashx-servicelogo'],
      maxChars: 300,
    );
    final supportUrl = headers['support-url']?.trim();
    final hasSupportUrl = supportUrl != null && supportUrl.isNotEmpty;

    final deviceLimitReached =
        headers['x-hwid-max-devices-reached']?.trim().toLowerCase() == 'true';
    final hwidNotSupported =
        headers['x-hwid-not-supported']?.trim().toLowerCase() == 'true';

    final isUrlProfile = currentProfile.type == ProfileType.url;
    final isSyncing = currentProfile.isUpdating ||
        _syncingProfileIds.contains(currentProfile.id);

    // Update policy badge
    final String updatePolicyText;
    final IconData updatePolicyIcon;
    if (isUrlProfile) {
      final minutes = currentProfile.autoUpdateDuration.inMinutes;
      if (currentProfile.realAutoUpdate && minutes > 0) {
        updatePolicyIcon = Icons.autorenew_rounded;
        if (minutes % 60 == 0 && currentProfile.autoUpdateDuration.inHours >= 1) {
          updatePolicyText = appLocalizations.nodeOverviewAutoUpdateHours(
            currentProfile.autoUpdateDuration.inHours,
          );
        } else {
          updatePolicyText =
              appLocalizations.nodeOverviewAutoUpdateMinutes(minutes);
        }
      } else {
        updatePolicyIcon = Icons.sync_disabled_rounded;
        updatePolicyText = appLocalizations.nodeOverviewManualUpdate;
      }
    } else {
      updatePolicyIcon = Icons.description_outlined;
      updatePolicyText = appLocalizations.nodeOverviewLocalProfile;
    }

    final globalOverrideRulesCount = ref.watch(
      globalOverrideProvider.select((state) => state.runningRule.length),
    );
    final activeOverrideRulesCount =
        currentProfile.overrideData.runningRule.length +
            globalOverrideRulesCount;

    final sub = currentProfile.subscriptionInfo;
    final allGroups = ref.watch(groupsProvider);
    final visibleGroups = ref.watch(currentGroupsStateProvider).value;
    final selectedMap = ref.watch(selectedMapProvider);
    final activeNode = _resolveActiveNode(
      currentProfile,
      visibleGroups,
      allGroups,
      selectedMap,
    );
    final leafProxyCount = _countUniqueLeafProxies(allGroups);
    final activeNodeDelay = activeNode == null
        ? null
        : ref.watch(
            getDelayProvider(
              proxyName: activeNode.nodeName,
              testUrl: activeNode.testUrl,
            ),
          );

    final textScale = MediaQuery.textScalerOf(context).scale(1.0);

    return CommonCard(
      onPressed: null,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stackHeaderActions =
                constraints.maxWidth < 360 || textScale > 1.35;

            final actionWidgets = <Widget>[
              if (hasSupportUrl)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const ValueKey('metainfo-support-button'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => unawaited(globalState.openUrl(supportUrl)),
                    child: Tooltip(
                      message: appLocalizations.dashboardContactSupport,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest.withValues(
                            alpha: 0.55,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: colors.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Icon(
                          Icons.contact_support_outlined,
                          size: 16,
                          color: colors.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              if (isUrlProfile)
                _buildUpdateSubscriptionButton(
                  context,
                  profile: currentProfile,
                  isSyncing: isSyncing,
                ),
            ];

            final titleColumn = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (serviceLogoUrl != null && serviceLogoUrl.isNotEmpty) ...[
                      _buildServiceLogo(context, serviceLogoUrl),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      key: const ValueKey('metainfo-profile-title'),
                      child: _buildAdaptiveText(
                        profileTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (serviceName != null)
                      _buildTagPill(
                        context,
                        icon: Icons.verified_user_outlined,
                        text: serviceName,
                        foreground: colors.primary,
                        background: colors.primary.withValues(
                          alpha: isDark ? 0.16 : 0.10,
                        ),
                        border: colors.primary.withValues(alpha: 0.30),
                      ),
                    _buildTagPill(
                      context,
                      icon: updatePolicyIcon,
                      text: updatePolicyText,
                    ),
                    if (activeOverrideRulesCount > 0)
                      _buildTagPill(
                        context,
                        icon: Icons.tune_rounded,
                        text: appLocalizations.dashboardRuleOverrideCount(
                          activeOverrideRulesCount,
                        ),
                      ),
                  ],
                ),
              ],
            );

            // Expiry resolution
            final now = DateTime.now();
            final expireDate = sub == null
                ? null
                : _parseSubscriptionExpireLocal(sub.expire);
            String? expiryTileText;
            Color? expiryAccent;
            var expiryIcon = Icons.verified_outlined;
            if (sub != null) {
              if (expireDate == null) {
                expiryTileText = appLocalizations.subscriptionEternal;
              } else {
                final formattedDate =
                    DateFormat('yyyy-MM-dd HH:mm').format(expireDate);
                final diff = expireDate.difference(now);
                final String countdown;
                if (diff.isNegative) {
                  countdown = appLocalizations.nodeOverviewStatusExpired;
                  expiryAccent = colors.error;
                  expiryIcon = Icons.error_outline_rounded;
                } else if (diff.inDays >= 1) {
                  countdown =
                      appLocalizations.nodeOverviewExpireDaysLeft(diff.inDays);
                  expiryIcon = Icons.event_outlined;
                  if (diff.inDays <= 3) {
                    expiryAccent = Colors.orange;
                  }
                } else if (diff.inHours >= 1) {
                  countdown = appLocalizations
                      .nodeOverviewExpireHoursLeft(diff.inHours);
                  expiryAccent = Colors.orange;
                  expiryIcon = Icons.schedule_rounded;
                } else {
                  countdown = appLocalizations.nodeOverviewExpireSoon;
                  expiryAccent = Colors.orange;
                  expiryIcon = Icons.schedule_rounded;
                }
                expiryTileText =
                    '${appLocalizations.nodeOverviewExpireAt(formattedDate)} · $countdown';
              }
            }

            final String? syncTimeText;
            if (currentProfile.lastUpdateDate != null) {
              syncTimeText = appLocalizations.nodeOverviewLastSync(
                DateFormat('yyyy-MM-dd HH:mm')
                    .format(currentProfile.lastUpdateDate!),
              );
            } else if (isUrlProfile) {
              syncTimeText = appLocalizations.dashboardNotSyncedYet;
            } else {
              syncTimeText = null;
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Row 1: Announcement strictly at the top when present
                if (announceText != null && announceText.isNotEmpty) ...[
                  Container(
                    key: const ValueKey('metainfo-announce-row'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer.withValues(
                        alpha: isDark ? 0.28 : 0.45,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: colors.primary.withValues(alpha: 0.26),
                      ),
                    ),
                    child: Builder(
                      builder: (context) {
                        final badge = Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(
                              alpha: isDark ? 0.24 : 0.14,
                            ),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.campaign_outlined,
                                size: 14,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  appLocalizations.dashboardAnnouncementBadge,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                        final body = RichText(
                          text: TextSpan(
                            children: _buildAnnouncementSpans(
                              context,
                              announceText,
                            ),
                          ),
                        );
                        if (stackHeaderActions) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              badge,
                              const SizedBox(height: 6),
                              body,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            badge,
                            const SizedBox(width: 8),
                            Expanded(child: body),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Row 2: Profile Identity + "点击更新订阅" Text Button
                if (stackHeaderActions) ...[
                  titleColumn,
                  if (actionWidgets.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: actionWidgets,
                    ),
                  ],
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: titleColumn),
                      if (actionWidgets.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: actionWidgets,
                        ),
                      ],
                    ],
                  ),

                // Row 3: Device / HWID warnings
                if (deviceLimitReached || hwidNotSupported) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (deviceLimitReached)
                        _buildTagPill(
                          context,
                          icon: Icons.devices_other_rounded,
                          text: appLocalizations.nodeOverviewDeviceLimitReached,
                          foreground: colors.error,
                          background: colors.errorContainer.withValues(
                            alpha: isDark ? 0.35 : 0.55,
                          ),
                          border: colors.error.withValues(alpha: 0.45),
                        ),
                      if (hwidNotSupported)
                        _buildTagPill(
                          context,
                          icon: Icons.phonelink_erase_rounded,
                          text: appLocalizations.dashboardHwidNotSupported,
                          foreground: Colors.orange,
                          background: Colors.orange.withValues(alpha: 0.14),
                          border: Colors.orange.withValues(alpha: 0.40),
                        ),
                    ],
                  ),
                ],

                // Row 4: Subscription Traffic Quota & Upload/Download Breakdown
                if (sub != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest.withValues(
                        alpha: isDark ? 0.30 : 0.42,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: colors.outlineVariant.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Builder(
                      builder: (context) {
                        final upload = math.max(0, sub.upload);
                        final download = math.max(0, sub.download);
                        final used = upload + download;
                        final total = math.max(0, sub.total);

                        if (total > 0) {
                          final remaining = math.max(0, total - used);
                          final progress = (used / total).clamp(0.0, 1.0);
                          final rawRemainPct =
                              ((1.0 - progress) * 100).round();
                          final remainingPct = remaining <= 0
                              ? 0
                              : remaining >= total
                                  ? 100
                                  : rawRemainPct.clamp(1, 99);
                          final progressColor = progress > 0.90
                              ? colors.error
                              : progress > 0.70
                                  ? Colors.orange
                                  : Colors.green;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.data_usage_rounded,
                                    size: 15,
                                    color: progressColor,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      appLocalizations
                                          .nodeOverviewRemainingTraffic(
                                        _formatTraffic(remaining),
                                      ),
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: progress > 0.90
                                            ? colors.error
                                            : colors.onSurface,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: progressColor.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '$remainingPct%',
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: progressColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 6,
                                  backgroundColor:
                                      colors.surfaceContainerHighest,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    progressColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 10,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    appLocalizations
                                        .nodeOverviewUsedOfTotalTraffic(
                                      _formatTraffic(used),
                                      _formatTraffic(total),
                                    ),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    '↑ ${_formatTraffic(upload)} · ↓ ${_formatTraffic(download)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        }

                        // Unlimited plan: show localized "不限流量" AND cumulative upload/download breakdown
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.all_inclusive_rounded,
                                  size: 16,
                                  color: colors.primary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    appLocalizations.trafficUnlimited,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: colors.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 10,
                              runSpacing: 4,
                              children: [
                                if (used > 0)
                                  Text(
                                    appLocalizations.nodeOverviewUsedTrafficOnly(
                                      _formatTraffic(used),
                                    ),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                Text(
                                  '↑ ${_formatTraffic(upload)} · ↓ ${_formatTraffic(download)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],

                // Row 5: Comprehensive Metadata Footer (Expiry, Sync Time, Active Node & Delay, Node Count)
                if (expiryTileText != null ||
                    syncTimeText != null ||
                    activeNode != null ||
                    leafProxyCount > 0) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (expiryTileText != null)
                        _buildInfoTile(
                          context,
                          icon: expiryIcon,
                          text: expiryTileText,
                          accentColor: expiryAccent,
                        ),
                      if (syncTimeText != null)
                        _buildInfoTile(
                          context,
                          icon: Icons.history_rounded,
                          text: syncTimeText,
                        ),
                      if (activeNode != null)
                        _buildInfoTile(
                          context,
                          icon: Icons.route_rounded,
                          text: appLocalizations.dashboardCurrentNodeLabel(
                            activeNode.nodeName,
                          ),
                          trailing: (activeNodeDelay != null &&
                                  activeNodeDelay > 0)
                              ? Builder(
                                  builder: (context) {
                                    final delayColor =
                                        utils.getDelayColor(activeNodeDelay) ??
                                            colors.primary;
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            delayColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Text(
                                        '$activeNodeDelay ms',
                                        style:
                                            theme.textTheme.labelSmall?.copyWith(
                                          color: delayColor,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    );
                                  },
                                )
                              : null,
                        ),
                      if (leafProxyCount > 0)
                        _buildInfoTile(
                          context,
                          icon: Icons.hub_outlined,
                          text: appLocalizations.dashboardTotalNodesCount(
                            leafProxyCount,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
