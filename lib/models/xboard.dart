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
