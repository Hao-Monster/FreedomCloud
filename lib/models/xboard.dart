/// Public catalogue prices use integer minor units; traffic is already in GiB.
class XboardPlanPrice {
  const XboardPlanPrice({required this.period, required this.amount});

  final String period;
  final int amount;
}

class XboardPlanOffer {
  const XboardPlanOffer({
    required this.id,
    required this.name,
    required this.transferGiB,
    this.speedLimit,
    this.deviceLimit,
    required this.prices,
    this.content = '',
    this.tags = const [],
    this.resetTrafficMethod,
    this.capacityRemaining,
    this.resetTrafficPrice,
    bool? hasSpeedLimit,
    bool? hasDeviceLimit,
    bool? hasResetTrafficMethod,
    bool? hasCapacityRemaining,
  })  : hasSpeedLimit = hasSpeedLimit ?? speedLimit != null,
        hasDeviceLimit = hasDeviceLimit ?? deviceLimit != null,
        hasResetTrafficMethod =
            hasResetTrafficMethod ?? resetTrafficMethod != null,
        hasCapacityRemaining =
            hasCapacityRemaining ?? capacityRemaining != null;

  final int id;
  final String name;
  final int transferGiB;
  final int? speedLimit;
  final int? deviceLimit;
  final List<XboardPlanPrice> prices;
  final String content;
  final List<String> tags;
  final int? resetTrafficMethod;
  final int? capacityRemaining;
  final int? resetTrafficPrice;

  // Missing fields from older servers are unknown, not an unlimited benefit
  // (or an inherited reset rule). Explicit null has a defined API meaning.
  final bool hasSpeedLimit;
  final bool hasDeviceLimit;
  final bool hasResetTrafficMethod;
  final bool hasCapacityRemaining;
}

class XboardPlanCatalog {
  const XboardPlanCatalog({required this.plans});

  final List<XboardPlanOffer> plans;
}

/// Xboard account credentials are deliberately kept outside display models.
class XboardAccount {
  const XboardAccount({
    required this.id,
    required this.email,
    this.isDistributor = false,
  });

  final int id;
  final String email;
  final bool isDistributor;
}

class XboardSubscription {
  const XboardSubscription({
    this.planId,
    this.planName,
    required this.valid,
    required this.url,
    this.upload = 0,
    this.download = 0,
    this.total = 0,
    this.expiresAt,
    this.balance,
  });

  final int? planId;
  final String? planName;
  final bool valid;
  final Uri url;
  final int upload;
  final int download;
  final int total;
  final DateTime? expiresAt;
  final int? balance;

  int get usedTraffic => upload + download;
  int get remainingTraffic => (total - usedTraffic).clamp(0, total);
}

class GiftPurchaseSnapshot {
  const GiftPurchaseSnapshot({
    required this.planId,
    required this.planName,
    required this.period,
    required this.transferEnable,
    this.speedLimit = 0,
    this.deviceLimit = 0,
  });

  final int planId;
  final String planName;
  final String period;
  final int transferEnable;
  final int speedLimit;
  final int deviceLimit;
}

class GiftPurchasePreview {
  const GiftPurchasePreview({
    required this.transferBefore,
    required this.transferAfter,
    required this.usedTraffic,
    this.expiresBefore,
    this.expiresAfter,
    required this.renewal,
  });

  final int transferBefore;
  final int transferAfter;
  final int usedTraffic;
  final DateTime? expiresBefore;
  final DateTime? expiresAfter;
  final bool renewal;
}

class GiftReward {
  const GiftReward({
    this.balance = 0,
    this.transferEnable = 0,
    this.expireDays = 0,
    this.deviceLimit = 0,
    this.resetTraffic = false,
    this.planId,
    this.planValidityDays = 0,
    this.purchasePeriod,
    this.purchaseSnapshot,
  });

  /// Monetary values are minor currency units, as returned by Xboard.
  final int balance;
  final int transferEnable;
  final int expireDays;
  final int deviceLimit;
  final bool resetTraffic;
  final int? planId;
  final int planValidityDays;
  final String? purchasePeriod;
  final GiftPurchaseSnapshot? purchaseSnapshot;

  bool get isEmpty =>
      balance == 0 &&
      transferEnable == 0 &&
      expireDays == 0 &&
      deviceLimit == 0 &&
      !resetTraffic &&
      planId == null &&
      planValidityDays == 0 &&
      purchaseSnapshot == null;
}

class GiftPreview {
  const GiftPreview({
    required this.codeId,
    required this.type,
    required this.name,
    required this.canRedeem,
    this.reason,
    required this.rewards,
    this.purchasePreview,
  });

  /// Older Bearer responses omit this ID. Never infer it from a masked code.
  final int? codeId;
  final int type;
  final String name;
  final bool canRedeem;
  final String? reason;

  /// For mystery cards this is only an example, not the eventual reward.
  final GiftReward rewards;
  final GiftPurchasePreview? purchasePreview;

  bool get isMystery => type == 3;
}

class GiftReceipt {
  const GiftReceipt({
    required this.templateName,
    required this.rewards,
    this.orderTradeNo,
    this.codeId,
  });

  final String templateName;
  final GiftReward rewards;
  final String? orderTradeNo;
  final int? codeId;
}

class GiftHistoryEntry {
  const GiftHistoryEntry({
    required this.id,
    required this.codeId,
    required this.maskedCode,
    required this.templateName,
    required this.rewards,
    required this.usedAt,
    this.orderTradeNo,
    this.type,
  });

  final int id;
  final int? codeId;
  final String maskedCode;
  final String templateName;
  final GiftReward rewards;
  final DateTime usedAt;
  final String? orderTradeNo;
  final int? type;
}

class GiftHistoryPage {
  GiftHistoryPage({
    required List<GiftHistoryEntry> entries,
    required this.page,
    required this.lastPage,
    required this.total,
  }) : entries = List.unmodifiable(entries);

  final List<GiftHistoryEntry> entries;
  final int page;
  final int lastPage;
  final int total;
}

class XboardPurchaseChannels {
  const XboardPurchaseChannels({
    this.cardStoreUrl,
    this.cardStore50gUrl,
    this.cardStore100gUrl,
    this.cardStore200gUrl,
    this.cardStore500gUrl,
    this.chatwootBaseUrl,
    this.chatwootWebsiteToken,
  });

  final Uri? cardStoreUrl;
  final Uri? cardStore50gUrl;
  final Uri? cardStore100gUrl;
  final Uri? cardStore200gUrl;
  final Uri? cardStore500gUrl;
  final Uri? chatwootBaseUrl;
  final String? chatwootWebsiteToken;

  bool get hasAnyStoreUrl =>
      cardStoreUrl != null ||
      cardStore50gUrl != null ||
      cardStore100gUrl != null ||
      cardStore200gUrl != null ||
      cardStore500gUrl != null;

  bool get hasChatwoot => resolveChatwootWidgetUrl() != null;

  static final RegExp _chatwootTokenPattern =
      RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  Uri? resolveChatwootWidgetUrl({String locale = 'zh_CN'}) {
    final base = chatwootBaseUrl;
    final token = chatwootWebsiteToken?.trim() ?? '';
    if (base == null ||
        base.scheme != 'https' ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        (base.path.isNotEmpty && base.path != '/') ||
        !_chatwootTokenPattern.hasMatch(token)) {
      return null;
    }
    return base.replace(
      path: '/widget',
      queryParameters: <String, String>{
        'website_token': token,
        'locale': locale,
      },
    );
  }

  static final RegExp _metadataLinePattern = RegExp(
    r'^(?:(?:[•·]|-(?!-)|\+(?!\+))\s*|\*(?!\*)\s+)?(?:\*{1,2}|_{1,2})?(?:购买链接|购卡链接|发卡链接|发卡网|card_store_url|purchase\s*(?:url|link))(?:\*{1,2}|_{1,2})?\s*[:：](?:\*{1,2}|_{1,2})?\s*(.*)$',
    caseSensitive: false,
  );

  static final RegExp _markdownLinkUrlPattern = RegExp(
    r'''\[[^\]]*\]\(\s*<?([^>\s)]+)>?(?:\s+["'][^"']*["'])?\s*\)''',
    caseSensitive: false,
  );

  static final RegExp _angleLinkUrlPattern = RegExp(
    r'^<\s*([^>\s]+)\s*>',
  );

  static final RegExp _leadingUrlQuotes = RegExp(r'''^[`'"“”‘’]+''');

  static final RegExp _bareHttpsUrlPattern = RegExp(
    r'https://[^\s<>\]"”’）]+',
    caseSensitive: false,
  );

  static final RegExp _trailingUrlNoise = RegExp(
    r'''[，。；！？、,.;!?'")\]>*`”’）\s]+$''',
  );

  static Uri? _sanitizeHttpsPurchaseUri(String rawCandidate) {
    final cleaned = rawCandidate
        .trim()
        .replaceFirst(_leadingUrlQuotes, '')
        .replaceAll(_trailingUrlNoise, '');
    if (cleaned.isEmpty || cleaned.contains('#')) return null;
    final parsed = Uri.tryParse(cleaned);
    if (parsed == null ||
        parsed.scheme != 'https' ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasFragment) {
      return null;
    }
    return parsed;
  }

  static Uri? extractPlanContentPurchaseUrl(String content) {
    if (content.trim().isEmpty) return null;
    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      final lineMatch = _metadataLinePattern.firstMatch(rawLine.trim());
      if (lineMatch == null) continue;
      final rhs = lineMatch.group(1)!.trim();
      if (rhs.isEmpty) continue;
      final mdMatch = _markdownLinkUrlPattern.firstMatch(rhs);
      if (mdMatch != null) {
        final mdUri = _sanitizeHttpsPurchaseUri(mdMatch.group(1)!);
        if (mdUri != null) return mdUri;
      }
      final angleMatch = _angleLinkUrlPattern.firstMatch(rhs);
      if (angleMatch != null) {
        final angleUri = _sanitizeHttpsPurchaseUri(angleMatch.group(1)!);
        if (angleUri != null) return angleUri;
      }
      final firstToken =
          rhs.replaceFirst(_leadingUrlQuotes, '').split(RegExp(r'\s+')).first;
      final firstUri = _sanitizeHttpsPurchaseUri(firstToken);
      if (firstUri != null) return firstUri;
      final bareMatch = _bareHttpsUrlPattern.firstMatch(rhs);
      if (bareMatch != null) {
        final bareUri = _sanitizeHttpsPurchaseUri(bareMatch.group(0)!);
        if (bareUri != null) return bareUri;
      }
    }
    return null;
  }

  static String stripPlanPurchaseMetadata(String content) {
    if (content.trim().isEmpty) return content;
    final kept = content
        .split(RegExp(r'\r?\n'))
        .where((line) => !_metadataLinePattern.hasMatch(line.trim()))
        .toList();
    return kept.join('\n').trim();
  }

  static int? detectTierGiB(XboardPlanOffer plan) {
    if (plan.transferGiB > 0) {
      return const {50, 100, 200, 500}.contains(plan.transferGiB)
          ? plan.transferGiB
          : null;
    }
    final match = RegExp(
      r'(?<![0-9.])(50|100|200|500)\s*(?:gib|gb|g)(?![a-z0-9])',
      caseSensitive: false,
    ).firstMatch(plan.name);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  Uri? resolvePlanStoreUrl(XboardPlanOffer plan) {
    final contentUrl = extractPlanContentPurchaseUrl(plan.content);
    if (contentUrl != null) return contentUrl;
    final tierUrl = switch (detectTierGiB(plan)) {
      50 => cardStore50gUrl,
      100 => cardStore100gUrl,
      200 => cardStore200gUrl,
      500 => cardStore500gUrl,
      _ => null,
    };
    return tierUrl ?? cardStoreUrl;
  }
}

class XboardGuestAuthConfig {
  const XboardGuestAuthConfig({
    this.isEmailVerify = false,
    this.isInviteForce = false,
    List<String> emailWhitelistSuffix = const [],
    this.isCaptcha = false,
    this.captchaType,
    this.tosUrl,
    this.isRegistrationStopped = false,
    this.isGmailAliasRestricted,
  }) : _emailWhitelistSuffix = emailWhitelistSuffix;

  final bool isEmailVerify;
  final bool isInviteForce;
  final List<String> _emailWhitelistSuffix;
  final bool isCaptcha;
  final String? captchaType;
  final Uri? tosUrl;
  final bool isRegistrationStopped;
  final bool? isGmailAliasRestricted;

  List<String> get emailWhitelistSuffix =>
      List<String>.unmodifiable(_emailWhitelistSuffix);

  static (String localPart, String domain)? _splitEmail(String email) {
    final trimmed = email.trim();
    final atIndex = trimmed.indexOf('@');
    if (atIndex <= 0 ||
        atIndex != trimmed.lastIndexOf('@') ||
        atIndex == trimmed.length - 1) {
      return null;
    }
    return (
      trimmed.substring(0, atIndex),
      trimmed.substring(atIndex + 1).toLowerCase(),
    );
  }

  bool isEmailDomainAllowed(String email) {
    if (_emailWhitelistSuffix.isEmpty) return true;
    final parts = _splitEmail(email);
    if (parts == null) return false;
    final (_, domain) = parts;
    for (final entry in _emailWhitelistSuffix) {
      var normalized = entry.trim().toLowerCase();
      while (normalized.startsWith('@')) {
        normalized = normalized.substring(1).trim();
      }
      if (normalized.isNotEmpty && normalized == domain) {
        return true;
      }
    }
    return false;
  }

  bool hasGmailPlusAlias(String email) {
    final parts = _splitEmail(email);
    if (parts == null) return false;
    final (localPart, domain) = parts;
    return (domain == 'gmail.com' || domain == 'googlemail.com') &&
        localPart.contains('+');
  }

  bool isRestrictedGmailAlias(String email) {
    if (isGmailAliasRestricted == false) return false;
    final parts = _splitEmail(email);
    if (parts == null) return false;
    final (localPart, domain) = parts;
    if (domain != 'gmail.com' && domain != 'googlemail.com') return false;
    if (localPart.contains('+')) return true;
    return (isGmailAliasRestricted ?? false) && localPart.contains('.');
  }
}
