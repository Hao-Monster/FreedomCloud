import 'dart:convert';
import 'dart:io';

import 'package:flclashx/common/app_localizations.dart';
import 'package:flclashx/common/print.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/plugins/vpn.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SubscriptionAlertKind {
  expired,
  expiringSoon,
  trafficExhausted,
  trafficLow,
}

class SubscriptionAlert {
  const SubscriptionAlert({
    required this.profileId,
    required this.title,
    required this.message,
    required this.kind,
    this.daysRemaining,
    this.remainingPercent,
    this.actionUrl = '',
  });

  final String profileId;
  final String title;
  final String message;
  final SubscriptionAlertKind kind;
  final int? daysRemaining;
  final int? remainingPercent;
  final String actionUrl;
}

/// Service for showing subscription expiration (<= 3d) and low-quota (< 15%
/// remaining) notifications across both Android and desktop platforms.
class SubscriptionNotificationService {
  static const String _prefsKeyPrefix = 'subscription_notified_';
  static const double lowQuotaRemainingRatioThreshold = 0.15;
  static const double quotaAlertAutoResetUsedRatio = 0.80;

  /// Days before expiration to show notifications
  /// 3 = 3 days left, 2 = 2 days left, 1 = 1 day left, 0 = expires today
  /// -1 is special: means subscription has expired
  static const List<int> notificationDays = [3, 2, 1, 0, -1];

  /// Reactive active alert list for in-app desktop/mobile status surfaces.
  static final ValueNotifier<List<SubscriptionAlert>> activeAlerts =
      ValueNotifier<List<SubscriptionAlert>>(const <SubscriptionAlert>[]);

  @visibleForTesting
  static DateTime Function()? nowProvider;

  @visibleForTesting
  static bool? isAndroidOverride;

  @visibleForTesting
  static Future<void> Function(SubscriptionAlert alert)? desktopNotifierOverride;

  @visibleForTesting
  static Future<bool?> Function({
    required String title,
    required String message,
    required String actionLabel,
    required String actionUrl,
  })? androidNotifierOverride;

  static String _resolveTitle(Profile profile) {
    var title = profile.label ?? profile.id;
    final svc = profile.providerHeaders['flclashx-servicename'];
    if (svc != null && svc.isNotEmpty) {
      try {
        final normalized = base64.normalize(svc);
        final decoded = utf8.decode(base64.decode(normalized)).trim();
        if (decoded.isNotEmpty) {
          title = decoded;
        }
      } catch (_) {
        if (svc.trim().isNotEmpty) {
          title = svc.trim();
        }
      }
    }
    return title;
  }

  /// Pure alert evaluation for both expiry (`<= 3d`) and remaining traffic (`< 15%`).
  static List<SubscriptionAlert> evaluateAlerts(
    Profile profile, {
    DateTime? now,
  }) {
    final subscriptionInfo = profile.subscriptionInfo;
    if (subscriptionInfo == null) return const <SubscriptionAlert>[];

    final currentNow = now ?? (nowProvider?.call() ?? DateTime.now());
    final title = _resolveTitle(profile);
    final supportUrl = profile.providerHeaders['support-url'] ?? '';
    final alerts = <SubscriptionAlert>[];

    final expire = subscriptionInfo.expire;
    if (expire > 0) {
      final expireDate = DateTime.fromMillisecondsSinceEpoch(expire * 1000);
      final isExpired = expireDate.isBefore(currentNow);
      final remaining = expireDate.difference(currentNow);
      final daysUntilExpire = remaining.inDays;
      if (isExpired) {
        alerts.add(
          SubscriptionAlert(
            profileId: profile.id,
            title: title,
            message: appLocalizations.subscriptionExpired,
            kind: SubscriptionAlertKind.expired,
            daysRemaining: -1,
            actionUrl: supportUrl,
          ),
        );
      } else if (remaining <= const Duration(days: 3) &&
          notificationDays.contains(daysUntilExpire)) {
        final message = daysUntilExpire == 0
            ? appLocalizations.subscriptionExpiresToday
            : appLocalizations.subscriptionExpiresInDays(
                daysUntilExpire.toString(),
              );
        alerts.add(
          SubscriptionAlert(
            profileId: profile.id,
            title: title,
            message: message,
            kind: SubscriptionAlertKind.expiringSoon,
            daysRemaining: daysUntilExpire,
            actionUrl: supportUrl,
          ),
        );
      }
    }

    final total = subscriptionInfo.total;
    if (total > 0) {
      final upload = subscriptionInfo.upload < 0 ? 0 : subscriptionInfo.upload;
      final download =
          subscriptionInfo.download < 0 ? 0 : subscriptionInfo.download;
      final used = upload + download;
      final remainingBytes = total - used;
      final remainingRatio = remainingBytes <= 0 ? 0.0 : remainingBytes / total;
      if (used >= total) {
        alerts.add(
          SubscriptionAlert(
            profileId: profile.id,
            title: title,
            message: '订阅流量已耗尽，请及时续费或兑换流量包',
            kind: SubscriptionAlertKind.trafficExhausted,
            remainingPercent: 0,
            actionUrl: supportUrl,
          ),
        );
      } else if (remainingRatio < lowQuotaRemainingRatioThreshold) {
        final remainingPct = (remainingRatio * 100).round().clamp(1, 14);
        alerts.add(
          SubscriptionAlert(
            profileId: profile.id,
            title: title,
            message: '订阅剩余流量不足 15%（剩余 $remainingPct%），请及时续费',
            kind: SubscriptionAlertKind.trafficLow,
            remainingPercent: remainingPct,
            actionUrl: supportUrl,
          ),
        );
      }
    }

    return List<SubscriptionAlert>.unmodifiable(alerts);
  }

  /// Check subscription and show deduplicated notifications on Android & desktop.
  static Future<void> checkAndNotify(Profile profile) async {
    commonPrint.log(
      '[SubscriptionNotification] checkAndNotify called for profile: ${profile.label}',
    );
    final subscriptionInfo = profile.subscriptionInfo;
    if (subscriptionInfo == null) {
      commonPrint.log('[SubscriptionNotification] No subscription info, skipping');
      _updateActiveAlertsForProfile(profile.id, const <SubscriptionAlert>[]);
      return;
    }

    final alerts = evaluateAlerts(profile);
    _updateActiveAlertsForProfile(profile.id, alerts);

    final prefs = await SharedPreferences.getInstance();
    if (subscriptionInfo.total > 0) {
      final used = (subscriptionInfo.upload < 0 ? 0 : subscriptionInfo.upload) +
          (subscriptionInfo.download < 0 ? 0 : subscriptionInfo.download);
      if (used / subscriptionInfo.total < quotaAlertAutoResetUsedRatio) {
        await prefs.remove(_getQuotaPrefsKey(profile.id, 'low15'));
        await prefs.remove(_getQuotaPrefsKey(profile.id, 'exhausted'));
      }
    }

    if (alerts.isEmpty) {
      return;
    }

    final isAndroid = isAndroidOverride ?? Platform.isAndroid;
    final actionLabel = appLocalizations.renew;

    for (final alert in alerts) {
      final String dedupKey;
      final String cycleStamp;
      switch (alert.kind) {
        case SubscriptionAlertKind.expired:
        case SubscriptionAlertKind.expiringSoon:
          final threshold = alert.daysRemaining ?? 0;
          dedupKey = _getPrefsKey(profile.id, threshold);
          final currentExpire = subscriptionInfo.expire;
          if (prefs.getInt(dedupKey) == currentExpire) {
            continue;
          }
          await _dispatchAlert(
            alert,
            isAndroid: isAndroid,
            actionLabel: actionLabel,
          );
          await prefs.setInt(dedupKey, currentExpire);
        case SubscriptionAlertKind.trafficExhausted:
        case SubscriptionAlertKind.trafficLow:
          final tier = alert.kind == SubscriptionAlertKind.trafficExhausted
              ? 'exhausted'
              : 'low15';
          dedupKey = _getQuotaPrefsKey(profile.id, tier);
          cycleStamp = '${subscriptionInfo.expire}:${subscriptionInfo.total}';
          if (prefs.getString(dedupKey) == cycleStamp) {
            continue;
          }
          await _dispatchAlert(
            alert,
            isAndroid: isAndroid,
            actionLabel: actionLabel,
          );
          await prefs.setString(dedupKey, cycleStamp);
      }
    }
  }

  static void _updateActiveAlertsForProfile(
    String profileId,
    List<SubscriptionAlert> profileAlerts,
  ) {
    final next = <SubscriptionAlert>[
      for (final existing in activeAlerts.value)
        if (existing.profileId != profileId) existing,
      ...profileAlerts,
    ];
    activeAlerts.value = List<SubscriptionAlert>.unmodifiable(next);
  }

  static Future<void> _dispatchAlert(
    SubscriptionAlert alert, {
    required bool isAndroid,
    required String actionLabel,
  }) async {
    if (isAndroid) {
      final androidSender = androidNotifierOverride ??
          (({
            required String title,
            required String message,
            required String actionLabel,
            required String actionUrl,
          }) =>
              vpn?.showSubscriptionNotification(
                title: title,
                message: message,
                actionLabel: actionLabel,
                actionUrl: actionUrl,
              ) ??
              Future<bool?>.value(false));
      await androidSender(
        title: alert.title,
        message: alert.message,
        actionLabel: alert.actionUrl.isNotEmpty ? actionLabel : '',
        actionUrl: alert.actionUrl,
      );
      return;
    }

    if (desktopNotifierOverride != null) {
      await desktopNotifierOverride!(alert);
      return;
    }

    try {
      globalState.showNotifier('${alert.title}：${alert.message}');
    } catch (e) {
      commonPrint.log('[SubscriptionNotification] desktop notifier skipped: $e');
    }
  }

  static String _getPrefsKey(String profileId, int days) =>
      '$_prefsKeyPrefix${profileId}_${days}d';

  static String _getQuotaPrefsKey(String profileId, String tier) =>
      '$_prefsKeyPrefix${profileId}_quota_$tier';

  /// Reset notification state for a profile (call when subscription is renewed)
  static Future<void> resetNotifications(String profileId) async {
    _updateActiveAlertsForProfile(profileId, const <SubscriptionAlert>[]);
    final prefs = await SharedPreferences.getInstance();
    for (final days in notificationDays) {
      final key = _getPrefsKey(profileId, days);
      await prefs.remove(key);
    }
    await prefs.remove(_getQuotaPrefsKey(profileId, 'low15'));
    await prefs.remove(_getQuotaPrefsKey(profileId, 'exhausted'));
  }
}
