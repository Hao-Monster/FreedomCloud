// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a ja locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'ja';

  static String m0(node) => "現在のノード：${node}";

  static String m1(count) => "ルール上書き ${count}";

  static String m2(count) => "計 ${count} ノード";

  static String m3(label) => "選択された${label}を削除してもよろしいですか？";

  static String m4(label) => "現在の${label}を削除してもよろしいですか？";

  static String m5(label) => "${label}は空欄にできません";

  static String m6(label) => "現在の${label}は既に存在しています";

  static String m7(time, elapsed) => "前回 ${time} · ${elapsed}";

  static String m8(mb) => "IPC 正常 · ${mb} MB";

  static String m9(exitPart) => "プロキシ経由を確認${exitPart}";

  static String m10(node) => "ノード ${node} で通信テストに失敗しました";

  static String m11(node) => "ノード ${node} の遅延が高めです";

  static String m12(count) => "適用済み（${count} グループ）";

  static String m13(days) => "残り ${days} 日";

  static String m14(percent) => "通信量 ${percent}% 使用済み";

  static String m15(flag) => " · 出口 ${flag}";

  static String m16(delay) => "ダイレクトモード · ${delay} ms";

  static String m17(node, delay, exitPart) =>
      "ノード ${node} · ${delay} ms${exitPart}";

  static String m18(available, tested, total) =>
      "ノード：利用可能 ${available} / 測定済 ${tested} / 計 ${total}";

  static String m19(count) => "計 ${count} 件の設定";

  static String m20(text) => "お知らせ：${text}";

  static String m21(profile, node, delay) =>
      "最速ノードに自動接続しました：${profile} · ${node}（${delay} ms）";

  static String m22(profile, node, delay) =>
      "スマート選択を開始：${profile}（最速：${node} · ${delay} ms）";

  static String m23(node) =>
      "ノード ${node} を自動選択しました（全ノード応答なし。通信できない場合は更新または別ノードをお試しください）";

  static String m24(node) => "ノード ${node} を選択しましたが、このサブスクリプションは期限切れです";

  static String m25(node) => "ノード ${node} を選択しましたが、通信量が上限に達しています";

  static String m26(hours) => "自動更新 ${hours}h";

  static String m27(minutes) => "自動更新 ${minutes}m";

  static String m28(count) => "不可 ${count}";

  static String m29(count) => "快適 ${count}";

  static String m30(count) => "やや遅 ${count}";

  static String m31(count) => "未測定 ${count}";

  static String m32(completed, failed, untested, profiles) =>
      "測定済み ${completed} · 失敗 ${failed} · 未測定 ${untested} · 問題のあるプロファイル ${profiles}";

  static String m33(name) => "使用中：${name}";

  static String m34(date) => "有効期限：${date}";

  static String m35(days) => "残り ${days} 日";

  static String m36(hours) => "残り ${hours} 時間";

  static String m37(count) => "${count} 件期限切れ";

  static String m38(count) => "${count} 件期限間近";

  static String m39(provider) => "設定ファイル · ${provider}";

  static String m40(median) => "全体中央値：${median}";

  static String m41(median, best) => "中央値：${median} · 最速 ${best}";

  static String m42(available, tested, total) =>
      "利用可能 ${available} / 測定済み ${tested} / 合計 ${total}";

  static String m43(time) => "前回使用時の測定：${time}";

  static String m44(time) => "同期日時：${time}";

  static String m45(time) => "最終測定：${time}";

  static String m46(profile, node) => "固定ノードにロック：${profile} · ${node}";

  static String m47(delay) => "中央値：${delay}";

  static String m48(count) => "ほかに ${count} 種類の問題";

  static String m49(available, total) => "利用可能 ${available} / ${total}";

  static String m50(date) => "期限 ${date}";

  static String m51(count) => "全 ${count} 件";

  static String m52(completed, total) => "${completed} / ${total}";

  static String m53(provider) => "${provider}：有効化後にノードを表示";

  static String m54(profile) => "プロキシ有効 · スマート：${profile}（自動最適化中）";

  static String m55(profile, node) => "プロキシ有効 · スマート：${profile} · ${node}";

  static String m56(profile, node) => "プロキシ有効 · ${profile} · ${node}";

  static String m57(traffic) => "残り通信量：${traffic}";

  static String m58(profile, node) => "${profile} · ${node} に切り替えました";

  static String m59(profile) => "スマート選択を有効化：${profile}";

  static String m60(profile, node) => "スマート選択を有効化：${profile}（現在：${node}）";

  static String m61(used, total) => "使用済み ${used} / ${total}";

  static String m62(used) => "使用済み：${used}";

  static String m63(label) => "現在${label}はありません";

  static String m64(label) => "${label}は数字でなければなりません";

  static String m65(label) => "${label} は 1024 から 49151 の間でなければなりません";

  static String m66(plan) => "「${plan}」の購入ページを開きました";

  static String m67(plan, quota, price) =>
      "こんにちは。【${plan} · ${quota} GiB（${price}）】の引き換えコードを購入したいです。";

  static String m68(count) => "残り ${count} 枠";

  static String m69(code) => "不明なルール（${code}）";

  static String m70(count) => "${count} 項目が選択されています";

  static String m71(days) => "サブスクリプションは${days}日後に期限切れになります";

  static String m72(reason) => "TUN: ${reason}";

  static String m73(label) => "${label}はURLである必要があります";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "about": MessageLookupByLibrary.simpleMessage("について"),
    "accessControl": MessageLookupByLibrary.simpleMessage("アクセス制御"),
    "accessControlAllowDesc": MessageLookupByLibrary.simpleMessage(
      "選択したアプリのみVPNを許可",
    ),
    "accessControlDesc": MessageLookupByLibrary.simpleMessage(
      "アプリケーションのプロキシアクセスを設定",
    ),
    "accessControlNotAllowDesc": MessageLookupByLibrary.simpleMessage(
      "選択したアプリをVPNから除外",
    ),
    "account": MessageLookupByLibrary.simpleMessage("アカウント"),
    "action": MessageLookupByLibrary.simpleMessage("アクション"),
    "action_mode": MessageLookupByLibrary.simpleMessage("モード切替"),
    "action_proxy": MessageLookupByLibrary.simpleMessage("システムプロキシ"),
    "action_start": MessageLookupByLibrary.simpleMessage("開始/停止"),
    "action_tun": MessageLookupByLibrary.simpleMessage("TUN"),
    "action_view": MessageLookupByLibrary.simpleMessage("表示/非表示"),
    "add": MessageLookupByLibrary.simpleMessage("追加"),
    "addRule": MessageLookupByLibrary.simpleMessage("ルールを追加"),
    "addedOriginRules": MessageLookupByLibrary.simpleMessage("元のルールに追加"),
    "address": MessageLookupByLibrary.simpleMessage("アドレス"),
    "addressHelp": MessageLookupByLibrary.simpleMessage("WebDAVサーバーアドレス"),
    "addressTip": MessageLookupByLibrary.simpleMessage("有効なWebDAVアドレスを入力"),
    "adminAutoLaunch": MessageLookupByLibrary.simpleMessage("管理者自動起動"),
    "adminAutoLaunchDesc": MessageLookupByLibrary.simpleMessage("管理者モードで起動"),
    "ago": MessageLookupByLibrary.simpleMessage("前"),
    "agree": MessageLookupByLibrary.simpleMessage("同意"),
    "allApps": MessageLookupByLibrary.simpleMessage("全アプリ"),
    "allowBypass": MessageLookupByLibrary.simpleMessage("アプリがVPNをバイパスすることを許可"),
    "allowBypassDesc": MessageLookupByLibrary.simpleMessage(
      "有効化すると一部アプリがVPNをバイパス",
    ),
    "allowLan": MessageLookupByLibrary.simpleMessage("LANを許可"),
    "allowLanDesc": MessageLookupByLibrary.simpleMessage("LAN経由でのプロキシアクセスを許可"),
    "announcement": MessageLookupByLibrary.simpleMessage("お知らせ"),
    "app": MessageLookupByLibrary.simpleMessage("アプリ"),
    "appAccessControl": MessageLookupByLibrary.simpleMessage("アプリアクセス制御"),
    "appDesc": MessageLookupByLibrary.simpleMessage("アプリ関連設定の処理"),
    "application": MessageLookupByLibrary.simpleMessage("アプリケーション設定"),
    "applicationDesc": MessageLookupByLibrary.simpleMessage("標準アプリ設定"),
    "auto": MessageLookupByLibrary.simpleMessage("自動"),
    "autoCheckUpdate": MessageLookupByLibrary.simpleMessage("自動更新チェック"),
    "autoCheckUpdateDesc": MessageLookupByLibrary.simpleMessage(
      "起動時に更新を自動チェック",
    ),
    "autoCloseConnections": MessageLookupByLibrary.simpleMessage("接続を自動閉じる"),
    "autoCloseConnectionsDesc": MessageLookupByLibrary.simpleMessage(
      "ノード変更後に接続を自動閉じる",
    ),
    "autoLaunch": MessageLookupByLibrary.simpleMessage("自動起動"),
    "autoLaunchDesc": MessageLookupByLibrary.simpleMessage("システムの自動起動に従う"),
    "autoRun": MessageLookupByLibrary.simpleMessage("自動実行"),
    "autoRunDesc": MessageLookupByLibrary.simpleMessage("アプリ起動時に自動実行"),
    "autoSetSystemDns": MessageLookupByLibrary.simpleMessage("オートセットシステムDNS"),
    "autoStart": MessageLookupByLibrary.simpleMessage("自動起動"),
    "autoStartDesc": MessageLookupByLibrary.simpleMessage(
      "再起動や更新後もVPNが復帰するよう自動起動を許可します（MIUI/EMUIなど）",
    ),
    "autoUpdate": MessageLookupByLibrary.simpleMessage("自動更新"),
    "autoUpdateInterval": MessageLookupByLibrary.simpleMessage("自動更新間隔（分）"),
    "backup": MessageLookupByLibrary.simpleMessage("バックアップ"),
    "backupAndRecovery": MessageLookupByLibrary.simpleMessage("バックアップと復元"),
    "backupAndRecoveryDesc": MessageLookupByLibrary.simpleMessage(
      "WebDAVまたはファイルでデータを同期",
    ),
    "backupSuccess": MessageLookupByLibrary.simpleMessage("バックアップ成功"),
    "basicConfig": MessageLookupByLibrary.simpleMessage("基本設定"),
    "basicConfigDesc": MessageLookupByLibrary.simpleMessage("基本設定をグローバルに変更"),
    "batteryOptimization": MessageLookupByLibrary.simpleMessage("バッテリー最適化"),
    "batteryOptimizationDesc": MessageLookupByLibrary.simpleMessage(
      "バックグラウンドでVPNが終了されないようアプリを除外します",
    ),
    "bind": MessageLookupByLibrary.simpleMessage("バインド"),
    "blacklistMode": MessageLookupByLibrary.simpleMessage("ブラックリストモード"),
    "bypassDomain": MessageLookupByLibrary.simpleMessage("バイパスドメイン"),
    "bypassDomainDesc": MessageLookupByLibrary.simpleMessage("システムプロキシ有効時のみ適用"),
    "cacheCorrupt": MessageLookupByLibrary.simpleMessage(
      "キャッシュが破損しています。クリアしますか？",
    ),
    "cancel": MessageLookupByLibrary.simpleMessage("キャンセル"),
    "cancelFilterSystemApp": MessageLookupByLibrary.simpleMessage(
      "システムアプリの除外を解除",
    ),
    "cancelSelectAll": MessageLookupByLibrary.simpleMessage("全選択解除"),
    "change": MessageLookupByLibrary.simpleMessage("変更"),
    "changeServer": MessageLookupByLibrary.simpleMessage("サーバーを変更"),
    "checkError": MessageLookupByLibrary.simpleMessage("確認エラー"),
    "checkUpdate": MessageLookupByLibrary.simpleMessage("更新を確認"),
    "checkUpdateError": MessageLookupByLibrary.simpleMessage("アプリは最新版です"),
    "checking": MessageLookupByLibrary.simpleMessage("確認中..."),
    "clearData": MessageLookupByLibrary.simpleMessage("データを消去"),
    "clearDataTip": MessageLookupByLibrary.simpleMessage(
      "これによりすべてのアプリデータが削除され、アプリケーションが再起動されます。よろしいですか？",
    ),
    "clipboardExport": MessageLookupByLibrary.simpleMessage("クリップボードにエクスポート"),
    "clipboardImport": MessageLookupByLibrary.simpleMessage("クリップボードからインポート"),
    "color": MessageLookupByLibrary.simpleMessage("カラー"),
    "colorSchemes": MessageLookupByLibrary.simpleMessage("カラースキーム"),
    "columns": MessageLookupByLibrary.simpleMessage("列"),
    "compatible": MessageLookupByLibrary.simpleMessage("互換モード"),
    "compatibleDesc": MessageLookupByLibrary.simpleMessage(
      "有効化すると一部機能を失いますが、Clashの完全サポートを獲得",
    ),
    "confirm": MessageLookupByLibrary.simpleMessage("確認"),
    "connections": MessageLookupByLibrary.simpleMessage("接続"),
    "connectionsDesc": MessageLookupByLibrary.simpleMessage("現在の接続データを表示"),
    "connectivity": MessageLookupByLibrary.simpleMessage("接続性："),
    "contactMe": MessageLookupByLibrary.simpleMessage("連絡する"),
    "content": MessageLookupByLibrary.simpleMessage("内容"),
    "contentScheme": MessageLookupByLibrary.simpleMessage("コンテンツテーマ"),
    "copy": MessageLookupByLibrary.simpleMessage("コピー"),
    "copyEnvVar": MessageLookupByLibrary.simpleMessage("環境変数をコピー"),
    "copyLink": MessageLookupByLibrary.simpleMessage("リンクをコピー"),
    "copySuccess": MessageLookupByLibrary.simpleMessage("コピー成功"),
    "core": MessageLookupByLibrary.simpleMessage("コア"),
    "coreInfo": MessageLookupByLibrary.simpleMessage("コア情報"),
    "country": MessageLookupByLibrary.simpleMessage("国"),
    "crashTest": MessageLookupByLibrary.simpleMessage("クラッシュテスト"),
    "crashlytics": MessageLookupByLibrary.simpleMessage("クラッシュレポート"),
    "crashlyticsDesc": MessageLookupByLibrary.simpleMessage(
      "Firebase Crashlytics でクラッシュログを自動送信します。機密情報は含まれません",
    ),
    "create": MessageLookupByLibrary.simpleMessage("作成"),
    "cut": MessageLookupByLibrary.simpleMessage("切り取り"),
    "dark": MessageLookupByLibrary.simpleMessage("ダーク"),
    "dashboard": MessageLookupByLibrary.simpleMessage("ダッシュボード"),
    "dashboardAnnouncementBadge": MessageLookupByLibrary.simpleMessage("お知らせ"),
    "dashboardClickUpdateSubscription": MessageLookupByLibrary.simpleMessage(
      "クリックして購読を更新",
    ),
    "dashboardContactSupport": MessageLookupByLibrary.simpleMessage("サポート"),
    "dashboardCurrentNodeLabel": m0,
    "dashboardHwidNotSupported": MessageLookupByLibrary.simpleMessage(
      "このサーバーは HWID バインドに対応していません",
    ),
    "dashboardNotSyncedYet": MessageLookupByLibrary.simpleMessage("同期時刻：未同期"),
    "dashboardRuleOverrideCount": m1,
    "dashboardTotalNodesCount": m2,
    "days": MessageLookupByLibrary.simpleMessage("日"),
    "defaultNameserver": MessageLookupByLibrary.simpleMessage("デフォルトネームサーバー"),
    "defaultNameserverDesc": MessageLookupByLibrary.simpleMessage(
      "DNSサーバーの解決用",
    ),
    "defaultProxyAutoTarget": MessageLookupByLibrary.simpleMessage(
      "デフォルトプロキシ (自動適応)",
    ),
    "defaultSort": MessageLookupByLibrary.simpleMessage("デフォルト順"),
    "defaultText": MessageLookupByLibrary.simpleMessage("デフォルト"),
    "delay": MessageLookupByLibrary.simpleMessage("遅延"),
    "delaySort": MessageLookupByLibrary.simpleMessage("遅延順"),
    "delete": MessageLookupByLibrary.simpleMessage("削除"),
    "deleteMultipTip": m3,
    "deleteTip": m4,
    "desc": MessageLookupByLibrary.simpleMessage(
      "ClashMetaベースのマルチプラットフォームプロキシクライアント。シンプルで使いやすく、オープンソースで広告なし。",
    ),
    "detectionTip": MessageLookupByLibrary.simpleMessage("サードパーティAPIに依存（参考値）"),
    "determiningIp": MessageLookupByLibrary.simpleMessage("IPを確認中..."),
    "developerMode": MessageLookupByLibrary.simpleMessage("デベロッパーモード"),
    "developerModeEnableTip": MessageLookupByLibrary.simpleMessage(
      "デベロッパーモードが有効になりました。",
    ),
    "direct": MessageLookupByLibrary.simpleMessage("ダイレクト"),
    "disclaimer": MessageLookupByLibrary.simpleMessage("免責事項"),
    "disclaimerDesc": MessageLookupByLibrary.simpleMessage(
      "本ソフトウェアは学習交流や科学研究などの非営利目的でのみ使用されます。商用利用は厳禁です。いかなる商用活動も本ソフトウェアとは無関係です。",
    ),
    "discoverNewVersion": MessageLookupByLibrary.simpleMessage("新バージョンを発見"),
    "discovery": MessageLookupByLibrary.simpleMessage("新しいバージョンを発見"),
    "dnsDesc": MessageLookupByLibrary.simpleMessage("DNS関連設定の更新"),
    "dnsMode": MessageLookupByLibrary.simpleMessage("DNSモード"),
    "doYouWantToPass": MessageLookupByLibrary.simpleMessage("プロファイルを追加中"),
    "domain": MessageLookupByLibrary.simpleMessage("ドメイン"),
    "download": MessageLookupByLibrary.simpleMessage("ダウンロード"),
    "downloadingZashboard": MessageLookupByLibrary.simpleMessage(
      "Zashboard をダウンロード中…",
    ),
    "edit": MessageLookupByLibrary.simpleMessage("編集"),
    "emptyTip": m5,
    "en": MessageLookupByLibrary.simpleMessage("英語"),
    "enableGlobalOverride": MessageLookupByLibrary.simpleMessage(
      "グローバル上書きを有効化",
    ),
    "enableOverride": MessageLookupByLibrary.simpleMessage("上書きを有効化"),
    "entries": MessageLookupByLibrary.simpleMessage(" エントリ"),
    "exclude": MessageLookupByLibrary.simpleMessage("最近のタスクから非表示"),
    "excludeDesc": MessageLookupByLibrary.simpleMessage(
      "アプリがバックグラウンド時に最近のタスクから非表示",
    ),
    "existsTip": m6,
    "exit": MessageLookupByLibrary.simpleMessage("終了"),
    "expand": MessageLookupByLibrary.simpleMessage("標準"),
    "expertMode": MessageLookupByLibrary.simpleMessage("上級者モード"),
    "expirationTime": MessageLookupByLibrary.simpleMessage("有効期限"),
    "expiresOn": MessageLookupByLibrary.simpleMessage("有効期限"),
    "exportFile": MessageLookupByLibrary.simpleMessage("ファイルをエクスポート"),
    "exportLogs": MessageLookupByLibrary.simpleMessage("ログをエクスポート"),
    "exportSuccess": MessageLookupByLibrary.simpleMessage("エクスポート成功"),
    "expressiveScheme": MessageLookupByLibrary.simpleMessage("エクスプレッシブ"),
    "externalController": MessageLookupByLibrary.simpleMessage("外部コントローラー"),
    "externalControllerDesc": MessageLookupByLibrary.simpleMessage(
      "有効化するとClashコアをポート9090で制御可能",
    ),
    "externalLink": MessageLookupByLibrary.simpleMessage("外部リンク"),
    "externalResources": MessageLookupByLibrary.simpleMessage("外部リソース"),
    "fakeipFilter": MessageLookupByLibrary.simpleMessage("Fakeipフィルター"),
    "fakeipRange": MessageLookupByLibrary.simpleMessage("Fakeip範囲"),
    "fallback": MessageLookupByLibrary.simpleMessage("フォールバック"),
    "fallbackDesc": MessageLookupByLibrary.simpleMessage("通常はオフショアDNSを使用"),
    "fallbackFilter": MessageLookupByLibrary.simpleMessage("フォールバックフィルター"),
    "fidelityScheme": MessageLookupByLibrary.simpleMessage("ハイファイデリティー"),
    "file": MessageLookupByLibrary.simpleMessage("ファイル"),
    "fileDesc": MessageLookupByLibrary.simpleMessage("プロファイルを直接アップロード"),
    "fileIsUpdate": MessageLookupByLibrary.simpleMessage(
      "ファイルが変更されました。保存しますか？",
    ),
    "fileTooLarge": MessageLookupByLibrary.simpleMessage("ファイルが大きすぎます"),
    "filterSystemApp": MessageLookupByLibrary.simpleMessage("システムアプリを除外"),
    "findProcessMode": MessageLookupByLibrary.simpleMessage("プロセス検出"),
    "findProcessModeDesc": MessageLookupByLibrary.simpleMessage(
      "有効化するとパフォーマンスが若干低下します",
    ),
    "fontFamily": MessageLookupByLibrary.simpleMessage("フォントファミリー"),
    "fourColumns": MessageLookupByLibrary.simpleMessage("4列"),
    "fruitSaladScheme": MessageLookupByLibrary.simpleMessage("フルーツサラダ"),
    "general": MessageLookupByLibrary.simpleMessage("一般"),
    "generalDesc": MessageLookupByLibrary.simpleMessage("一般設定を変更"),
    "geoData": MessageLookupByLibrary.simpleMessage("地域データ"),
    "geodataLoader": MessageLookupByLibrary.simpleMessage("Geo低メモリモード"),
    "geodataLoaderDesc": MessageLookupByLibrary.simpleMessage(
      "有効化するとGeo低メモリローダーを使用",
    ),
    "geoipCode": MessageLookupByLibrary.simpleMessage("GeoIPコード"),
    "getOriginRules": MessageLookupByLibrary.simpleMessage("元のルールを取得"),
    "global": MessageLookupByLibrary.simpleMessage("グローバル"),
    "globalOverride": MessageLookupByLibrary.simpleMessage("グローバルルール上書き"),
    "globalOverrideDesc": MessageLookupByLibrary.simpleMessage(
      "すべてのプロファイルで共通して適用されます",
    ),
    "go": MessageLookupByLibrary.simpleMessage("移動"),
    "goDownload": MessageLookupByLibrary.simpleMessage("ダウンロードへ"),
    "goToPurchasePrompt": MessageLookupByLibrary.simpleMessage(
      "サブスクリプションをお持ちでない方：購入・引換へ",
    ),
    "gratitude": MessageLookupByLibrary.simpleMessage("感謝"),
    "hasCacheChange": MessageLookupByLibrary.simpleMessage("変更をキャッシュしますか？"),
    "healthActionOpenDns": MessageLookupByLibrary.simpleMessage("DNS 設定"),
    "healthActionOpenNetwork": MessageLookupByLibrary.simpleMessage("ネットワーク設定"),
    "healthActionOpenProfiles": MessageLookupByLibrary.simpleMessage("プロファイルへ"),
    "healthActionOpenProxies": MessageLookupByLibrary.simpleMessage("ノード切替"),
    "healthActionOpenPurchase": MessageLookupByLibrary.simpleMessage("更新・引き換え"),
    "healthActionOpenTun": MessageLookupByLibrary.simpleMessage("TUN 設定"),
    "healthActionReapplySystemProxy": MessageLookupByLibrary.simpleMessage(
      "システムプロキシを復元",
    ),
    "healthActionRestartCore": MessageLookupByLibrary.simpleMessage("コア再起動"),
    "healthActionStartProxy": MessageLookupByLibrary.simpleMessage("プロキシ開始"),
    "healthCheckCancel": MessageLookupByLibrary.simpleMessage("キャンセル"),
    "healthCheckChecking": MessageLookupByLibrary.simpleMessage("チェック中…"),
    "healthCheckCopied": MessageLookupByLibrary.simpleMessage("診断の要約をコピーしました"),
    "healthCheckCopySummary": MessageLookupByLibrary.simpleMessage("要約をコピー"),
    "healthCheckDiagnoseAction": MessageLookupByLibrary.simpleMessage("診断"),
    "healthCheckExport": MessageLookupByLibrary.simpleMessage("レポート出力"),
    "healthCheckExportDialogTitle": MessageLookupByLibrary.simpleMessage(
      "匿名化診断レポートを出力",
    ),
    "healthCheckExportFailed": MessageLookupByLibrary.simpleMessage(
      "レポートの出力に失敗しました",
    ),
    "healthCheckExportSuccess": MessageLookupByLibrary.simpleMessage(
      "診断レポートを出力しました",
    ),
    "healthCheckLastChecked": m7,
    "healthCheckPrivacyNote": MessageLookupByLibrary.simpleMessage(
      "出力には状態コードと所要時間のみ含まれ、ノード名・IP・URL・ログは含まれません。",
    ),
    "healthCheckRecheck": MessageLookupByLibrary.simpleMessage("再チェック"),
    "healthCheckSubtitle": MessageLookupByLibrary.simpleMessage(
      "プロファイル・コア・トラフィック制御・通信経路を診断",
    ),
    "healthCheckTitle": MessageLookupByLibrary.simpleMessage("ヘルスチェック"),
    "healthDetailCancelled": MessageLookupByLibrary.simpleMessage("キャンセル済み"),
    "healthDetailCoreDelayBusy": MessageLookupByLibrary.simpleMessage(
      "一括テスト実行中のため混雑しています",
    ),
    "healthDetailCoreFailed": MessageLookupByLibrary.simpleMessage(
      "コア制御インターフェースのエラーまたはタイムアウト",
    ),
    "healthDetailCoreHealthy": m8,
    "healthDetailCoreSlow": MessageLookupByLibrary.simpleMessage(
      "コア応答が遅延しています（> 500 ms）",
    ),
    "healthDetailDirectFailed": MessageLookupByLibrary.simpleMessage(
      "直接通信に失敗しました。回線やルーターを確認してください",
    ),
    "healthDetailDirectMode": MessageLookupByLibrary.simpleMessage(
      "ダイレクトモード選択中",
    ),
    "healthDetailDirectOk": MessageLookupByLibrary.simpleMessage("直接通信可能"),
    "healthDetailDirectSlow": MessageLookupByLibrary.simpleMessage(
      "直接通信の遅延が高めです",
    ),
    "healthDetailDnsFailed": MessageLookupByLibrary.simpleMessage(
      "DNS 解決失敗またはタイムアウト",
    ),
    "healthDetailDnsFakeIp": MessageLookupByLibrary.simpleMessage(
      "Core DNS (fake-ip)",
    ),
    "healthDetailDnsOk": MessageLookupByLibrary.simpleMessage("名前解決正常"),
    "healthDetailDnsPoisoned": MessageLookupByLibrary.simpleMessage(
      "DNS が無効なアドレスを返しました",
    ),
    "healthDetailDnsStaleFakeIp": MessageLookupByLibrary.simpleMessage(
      "TUN無効時に残留Fake-IPキャッシュを検出しました",
    ),
    "healthDetailE2eBypassed": MessageLookupByLibrary.simpleMessage(
      "外部到達しましたがコアを経由していません",
    ),
    "healthDetailE2eDirectRule": MessageLookupByLibrary.simpleMessage(
      "コア到達済み（DIRECT ルール一致）",
    ),
    "healthDetailE2eFailed": MessageLookupByLibrary.simpleMessage(
      "エンドツーエンド検証がすべて失敗しました",
    ),
    "healthDetailE2eVerified": m9,
    "healthDetailLocalProfile": MessageLookupByLibrary.simpleMessage(
      "ローカル設定ファイル",
    ),
    "healthDetailNoProfile": MessageLookupByLibrary.simpleMessage("プロファイル未選択"),
    "healthDetailOutboundDirectSelected": MessageLookupByLibrary.simpleMessage(
      "グループで DIRECT が選択されています",
    ),
    "healthDetailOutboundFailed": m10,
    "healthDetailOutboundRejectSelected": MessageLookupByLibrary.simpleMessage(
      "グループで REJECT が選択されています",
    ),
    "healthDetailOutboundSlow": m11,
    "healthDetailProfileFileMissing": MessageLookupByLibrary.simpleMessage(
      "設定ファイルが見つからないか空です",
    ),
    "healthDetailProxyRunning": MessageLookupByLibrary.simpleMessage("稼働中"),
    "healthDetailProxyStopped": MessageLookupByLibrary.simpleMessage("停止中"),
    "healthDetailRuntimeMismatch": MessageLookupByLibrary.simpleMessage(
      "現在の設定がコアに未適用です",
    ),
    "healthDetailRuntimeSynced": m12,
    "healthDetailSkipPrerequisite": MessageLookupByLibrary.simpleMessage(
      "前提項目の未通過によりスキップ",
    ),
    "healthDetailSkipProxyStopped": MessageLookupByLibrary.simpleMessage(
      "プロキシ停止中のためスキップ",
    ),
    "healthDetailSubDeviceLimit": MessageLookupByLibrary.simpleMessage(
      "端末数上限に達しています",
    ),
    "healthDetailSubExhausted": MessageLookupByLibrary.simpleMessage("容量超過"),
    "healthDetailSubExpired": MessageLookupByLibrary.simpleMessage("有効期限切れ"),
    "healthDetailSubExpiringSoon": m13,
    "healthDetailSubHealthy": MessageLookupByLibrary.simpleMessage("有効"),
    "healthDetailSubHealthyEternal": MessageLookupByLibrary.simpleMessage(
      "無期限 · 無制限",
    ),
    "healthDetailSubNeverSynced": MessageLookupByLibrary.simpleMessage(
      "未同期です。購読を更新してください",
    ),
    "healthDetailSubNoMeta": MessageLookupByLibrary.simpleMessage("期限・容量情報なし"),
    "healthDetailSubTrafficLow": m14,
    "healthDetailSysProxyDisabled": MessageLookupByLibrary.simpleMessage(
      "設定でオフ",
    ),
    "healthDetailSysProxyDisabledExternally":
        MessageLookupByLibrary.simpleMessage("OSのシステムプロキシがオフになっています"),
    "healthDetailSysProxyHijacked": MessageLookupByLibrary.simpleMessage(
      "システムプロキシが外部で変更または無効化されています",
    ),
    "healthDetailSysProxyInvalidPort": MessageLookupByLibrary.simpleMessage(
      "混合ポートが無効です (mixed-port = 0)",
    ),
    "healthDetailSysProxyNotApplied": MessageLookupByLibrary.simpleMessage(
      "システムプロキシがまだ適用されていません",
    ),
    "healthDetailSysProxyReadFailed": MessageLookupByLibrary.simpleMessage(
      "システムプロキシ設定を読み取れません",
    ),
    "healthDetailSysProxyUnexpectedPac": MessageLookupByLibrary.simpleMessage(
      "残存する PAC URL を検出しました",
    ),
    "healthDetailSysProxyUnsupported": MessageLookupByLibrary.simpleMessage(
      "この環境では対象外",
    ),
    "healthDetailTakeoverBoth": MessageLookupByLibrary.simpleMessage(
      "TUN + システムプロキシ稼働中",
    ),
    "healthDetailTakeoverNone": MessageLookupByLibrary.simpleMessage(
      "TUN もシステムプロキシも有効ではありません",
    ),
    "healthDetailTakeoverPartial": MessageLookupByLibrary.simpleMessage(
      "有効な制御方式の一部が異常です",
    ),
    "healthDetailTakeoverSysProxy": MessageLookupByLibrary.simpleMessage(
      "システムプロキシで制御中",
    ),
    "healthDetailTakeoverTun": MessageLookupByLibrary.simpleMessage(
      "TUN 仮想アダプタで制御中",
    ),
    "healthDetailTunBypassedSystemProxyOk":
        MessageLookupByLibrary.simpleMessage("TUN 経路が失敗し、システムプロキシ経由で確認済み"),
    "healthDetailTunDisabled": MessageLookupByLibrary.simpleMessage("設定でオフ"),
    "healthDetailTunReady": MessageLookupByLibrary.simpleMessage("仮想アダプタ稼働中"),
    "healthDetailTunReadyElevated": MessageLookupByLibrary.simpleMessage(
      "稼働中 · 管理者権限",
    ),
    "healthExitCountryPart": m15,
    "healthItemCoreResponsive": MessageLookupByLibrary.simpleMessage("Core 応答"),
    "healthItemDirect": MessageLookupByLibrary.simpleMessage("ローカル直接通信"),
    "healthItemDns": MessageLookupByLibrary.simpleMessage("DNS 名前解決"),
    "healthItemEndToEnd": MessageLookupByLibrary.simpleMessage("エンドツーエンド検証"),
    "healthItemOutbound": MessageLookupByLibrary.simpleMessage("現在の出力ノード"),
    "healthItemProfileSelected": MessageLookupByLibrary.simpleMessage(
      "現在のプロファイル",
    ),
    "healthItemProxyStarted": MessageLookupByLibrary.simpleMessage("プロキシ稼働状態"),
    "healthItemRuntimeConfig": MessageLookupByLibrary.simpleMessage("実行時設定の適用"),
    "healthItemSubscription": MessageLookupByLibrary.simpleMessage(
      "サブスクリプション状態",
    ),
    "healthItemSystemProxy": MessageLookupByLibrary.simpleMessage("システムプロキシ"),
    "healthItemTrafficTakeover": MessageLookupByLibrary.simpleMessage("制御まとめ"),
    "healthItemTunTakeover": MessageLookupByLibrary.simpleMessage("TUN 仮想アダプタ"),
    "healthLayerConfig": MessageLookupByLibrary.simpleMessage("プロファイルと購読"),
    "healthLayerCore": MessageLookupByLibrary.simpleMessage("プロキシコア"),
    "healthLayerNetwork": MessageLookupByLibrary.simpleMessage("ネットワーク経路"),
    "healthLayerTakeover": MessageLookupByLibrary.simpleMessage("トラフィック制御"),
    "healthStatusFailed": MessageLookupByLibrary.simpleMessage("失敗"),
    "healthStatusPassed": MessageLookupByLibrary.simpleMessage("正常"),
    "healthStatusRunning": MessageLookupByLibrary.simpleMessage("確認中"),
    "healthStatusSkipped": MessageLookupByLibrary.simpleMessage("スキップ"),
    "healthStatusTimeout": MessageLookupByLibrary.simpleMessage("タイムアウト"),
    "healthStatusWarning": MessageLookupByLibrary.simpleMessage("警告"),
    "healthVerdictCancelledTitle": MessageLookupByLibrary.simpleMessage(
      "ヘルスチェックはキャンセルされました",
    ),
    "healthVerdictCheckingTitle": MessageLookupByLibrary.simpleMessage(
      "通信経路を順番に診断しています…",
    ),
    "healthVerdictCoreUnresponsive": MessageLookupByLibrary.simpleMessage(
      "プロキシコアが応答していません",
    ),
    "healthVerdictDnsFailed": MessageLookupByLibrary.simpleMessage(
      "DNS 名前解決に失敗したか不正な応答を検出しました",
    ),
    "healthVerdictEndToEndFailed": MessageLookupByLibrary.simpleMessage(
      "エンドツーエンド検証に失敗しました",
    ),
    "healthVerdictHealthyDirectSubtitle": m16,
    "healthVerdictHealthySubtitle": m17,
    "healthVerdictHealthyTitle": MessageLookupByLibrary.simpleMessage(
      "接続は正常です",
    ),
    "healthVerdictLocalNetworkDown": MessageLookupByLibrary.simpleMessage(
      "端末のネットワークが利用できません（ノードの問題ではありません）",
    ),
    "healthVerdictOutboundFailed": MessageLookupByLibrary.simpleMessage(
      "端末の通信は正常ですが、現在のノードに接続できません",
    ),
    "healthVerdictProfileMissing": MessageLookupByLibrary.simpleMessage(
      "有効なプロファイルが未選択かファイルがありません",
    ),
    "healthVerdictProxyNotStarted": MessageLookupByLibrary.simpleMessage(
      "プロキシ停止中のため直接通信しています",
    ),
    "healthVerdictSubscriptionExhausted": MessageLookupByLibrary.simpleMessage(
      "通信量の上限に達しています",
    ),
    "healthVerdictSubscriptionExpired": MessageLookupByLibrary.simpleMessage(
      "サブスクリプションの有効期限切れです",
    ),
    "healthVerdictTakeoverFailed": MessageLookupByLibrary.simpleMessage(
      "トラフィック未制御：TUN またはシステムプロキシを確認してください",
    ),
    "healthVerdictTrafficBypassed": MessageLookupByLibrary.simpleMessage(
      "外部通信は可能ですがプロキシコアを経由していません",
    ),
    "healthVerdictTunBypassedTitle": MessageLookupByLibrary.simpleMessage(
      "TUN 仮想アダプタが通信を捕捉できず、システムプロキシのみ稼働中",
    ),
    "healthVerdictWarningsTitle": MessageLookupByLibrary.simpleMessage(
      "利用可能ですが確認が必要な項目があります",
    ),
    "hostsDesc": MessageLookupByLibrary.simpleMessage("ホストを追加"),
    "hotkeyConflict": MessageLookupByLibrary.simpleMessage("ホットキー競合"),
    "hotkeyManagement": MessageLookupByLibrary.simpleMessage("ホットキー管理"),
    "hotkeyManagementDesc": MessageLookupByLibrary.simpleMessage(
      "キーボードでアプリを制御",
    ),
    "hours": MessageLookupByLibrary.simpleMessage("時間"),
    "icon": MessageLookupByLibrary.simpleMessage("アイコン"),
    "iconConfiguration": MessageLookupByLibrary.simpleMessage("アイコン設定"),
    "iconStyle": MessageLookupByLibrary.simpleMessage("アイコンスタイル"),
    "import": MessageLookupByLibrary.simpleMessage("インポート"),
    "importFile": MessageLookupByLibrary.simpleMessage("ファイルからインポート"),
    "importFromURL": MessageLookupByLibrary.simpleMessage(
      "サブスクリプションURLを貼り付けて確定してください",
    ),
    "importUrl": MessageLookupByLibrary.simpleMessage("URLからインポート"),
    "infiniteTime": MessageLookupByLibrary.simpleMessage("長期有効"),
    "init": MessageLookupByLibrary.simpleMessage("初期化"),
    "inputCorrectHotkey": MessageLookupByLibrary.simpleMessage("正しいホットキーを入力"),
    "intelligentSelected": MessageLookupByLibrary.simpleMessage("インテリジェント選択"),
    "internet": MessageLookupByLibrary.simpleMessage("インターネット"),
    "interval": MessageLookupByLibrary.simpleMessage("インターバル"),
    "intranetIP": MessageLookupByLibrary.simpleMessage("イントラネットIP"),
    "ipcidr": MessageLookupByLibrary.simpleMessage("IPCIDR"),
    "ipv6Desc": MessageLookupByLibrary.simpleMessage("有効化するとIPv6トラフィックを受信可能"),
    "ipv6InboundDesc": MessageLookupByLibrary.simpleMessage("IPv6インバウンドを許可"),
    "ja": MessageLookupByLibrary.simpleMessage("日本語"),
    "just": MessageLookupByLibrary.simpleMessage("たった今"),
    "keepAliveIntervalDesc": MessageLookupByLibrary.simpleMessage(
      "TCPキープアライブ間隔",
    ),
    "key": MessageLookupByLibrary.simpleMessage("キー"),
    "language": MessageLookupByLibrary.simpleMessage("言語"),
    "layout": MessageLookupByLibrary.simpleMessage("レイアウト"),
    "light": MessageLookupByLibrary.simpleMessage("ライト"),
    "list": MessageLookupByLibrary.simpleMessage("リスト"),
    "listen": MessageLookupByLibrary.simpleMessage("リスン"),
    "local": MessageLookupByLibrary.simpleMessage("ローカル"),
    "localBackupDesc": MessageLookupByLibrary.simpleMessage("ローカルにデータをバックアップ"),
    "localRecoveryDesc": MessageLookupByLibrary.simpleMessage("ファイルからデータを復元"),
    "localSplitMode": MessageLookupByLibrary.simpleMessage("国内・LAN スマート振り分け"),
    "localSplitModeDesc": MessageLookupByLibrary.simpleMessage(
      "購読に分流ルールがない場合、国内・LAN 直接接続を自動補完します",
    ),
    "localSplitMode_always": MessageLookupByLibrary.simpleMessage(
      "常に国内直接接続を追加",
    ),
    "localSplitMode_auto": MessageLookupByLibrary.simpleMessage(
      "裸設定を自動判定 (自動)",
    ),
    "localSplitMode_off": MessageLookupByLibrary.simpleMessage("オフ"),
    "locations": MessageLookupByLibrary.simpleMessage("ロケーション"),
    "logLevel": MessageLookupByLibrary.simpleMessage("ログレベル"),
    "logcat": MessageLookupByLibrary.simpleMessage("ログキャット"),
    "logcatDesc": MessageLookupByLibrary.simpleMessage("無効化するとログエントリを非表示"),
    "logs": MessageLookupByLibrary.simpleMessage("ログ"),
    "logsDesc": MessageLookupByLibrary.simpleMessage("ログキャプチャ記録"),
    "logsTest": MessageLookupByLibrary.simpleMessage("ログテスト"),
    "loopback": MessageLookupByLibrary.simpleMessage("ループバック解除ツール"),
    "loopbackDesc": MessageLookupByLibrary.simpleMessage("UWPループバック解除用"),
    "loose": MessageLookupByLibrary.simpleMessage("疎"),
    "managedByProvider": MessageLookupByLibrary.simpleMessage(
      "これらの設定はプロバイダーによって管理されています",
    ),
    "managedByProviderNetwork": MessageLookupByLibrary.simpleMessage(
      "これらのパラメータはプロバイダーによって管理されています",
    ),
    "memoryInfo": MessageLookupByLibrary.simpleMessage("メモリ情報"),
    "messageTest": MessageLookupByLibrary.simpleMessage("メッセージテスト"),
    "messageTestTip": MessageLookupByLibrary.simpleMessage("これはメッセージです。"),
    "min": MessageLookupByLibrary.simpleMessage("最小化"),
    "minimizeOnExit": MessageLookupByLibrary.simpleMessage("終了時に最小化"),
    "minimizeOnExitDesc": MessageLookupByLibrary.simpleMessage(
      "システムの終了イベントを変更",
    ),
    "minutes": MessageLookupByLibrary.simpleMessage("分"),
    "mixedPort": MessageLookupByLibrary.simpleMessage("混合ポート"),
    "mode": MessageLookupByLibrary.simpleMessage("モード"),
    "monochromeScheme": MessageLookupByLibrary.simpleMessage("モノクローム"),
    "months": MessageLookupByLibrary.simpleMessage("月"),
    "more": MessageLookupByLibrary.simpleMessage("詳細"),
    "name": MessageLookupByLibrary.simpleMessage("名前"),
    "nameSort": MessageLookupByLibrary.simpleMessage("名前順"),
    "nameserver": MessageLookupByLibrary.simpleMessage("ネームサーバー"),
    "nameserverDesc": MessageLookupByLibrary.simpleMessage("ドメイン解決用"),
    "nameserverPolicy": MessageLookupByLibrary.simpleMessage("ネームサーバーポリシー"),
    "nameserverPolicyDesc": MessageLookupByLibrary.simpleMessage(
      "対応するネームサーバーポリシーを指定",
    ),
    "network": MessageLookupByLibrary.simpleMessage("ネットワーク"),
    "networkDesc": MessageLookupByLibrary.simpleMessage("ネットワーク関連設定の変更"),
    "networkDetection": MessageLookupByLibrary.simpleMessage("あなたのIPアドレス"),
    "networkSpeed": MessageLookupByLibrary.simpleMessage("ネットワーク速度"),
    "neutralScheme": MessageLookupByLibrary.simpleMessage("ニュートラル"),
    "noData": MessageLookupByLibrary.simpleMessage("データなし"),
    "noHotKey": MessageLookupByLibrary.simpleMessage("ホットキーなし"),
    "noIcon": MessageLookupByLibrary.simpleMessage("なし"),
    "noInfo": MessageLookupByLibrary.simpleMessage("情報なし"),
    "noMoreInfoDesc": MessageLookupByLibrary.simpleMessage("追加情報なし"),
    "noNetwork": MessageLookupByLibrary.simpleMessage("ネットワークなし"),
    "noNetworkApp": MessageLookupByLibrary.simpleMessage("ネットワークなしアプリ"),
    "noProxy": MessageLookupByLibrary.simpleMessage("プロキシなし"),
    "noProxyDesc": MessageLookupByLibrary.simpleMessage(
      "プロファイルを作成するか、有効なプロファイルを追加してください",
    ),
    "noResolve": MessageLookupByLibrary.simpleMessage("IPを解決しない"),
    "nodeOverviewActive": MessageLookupByLibrary.simpleMessage("使用中"),
    "nodeOverviewAddSubscription": MessageLookupByLibrary.simpleMessage(
      "購読を追加",
    ),
    "nodeOverviewAllHealthCounts": m18,
    "nodeOverviewAllProfiles": MessageLookupByLibrary.simpleMessage("すべての設定"),
    "nodeOverviewAllProfilesCount": m19,
    "nodeOverviewAmbiguousNode": MessageLookupByLibrary.simpleMessage(
      "ノード定義が重複しているため、識別できません",
    ),
    "nodeOverviewAnnouncement": m20,
    "nodeOverviewAutoConnectedBest": m21,
    "nodeOverviewAutoConnectedSmartBest": m22,
    "nodeOverviewAutoSelectedAllFailedWarning": m23,
    "nodeOverviewAutoSelectedExpiredWarning": m24,
    "nodeOverviewAutoSelectedTrafficExhaustedWarning": m25,
    "nodeOverviewAutoUpdateHours": m26,
    "nodeOverviewAutoUpdateMinutes": m27,
    "nodeOverviewAvailableFilterEmpty": MessageLookupByLibrary.simpleMessage(
      "現在利用可能な測定済みノードがありません（未測定またはタイムアウト）",
    ),
    "nodeOverviewAvailableOnly": MessageLookupByLibrary.simpleMessage("利用可能のみ"),
    "nodeOverviewBandFailed": m28,
    "nodeOverviewBandFast": m29,
    "nodeOverviewBandSlow": m30,
    "nodeOverviewBandUntested": m31,
    "nodeOverviewBatchSummary": m32,
    "nodeOverviewChainUnsupported": MessageLookupByLibrary.simpleMessage(
      "プロキシチェーンの分離テストは未対応です",
    ),
    "nodeOverviewCurrentActiveProfile": m33,
    "nodeOverviewCurrentProfile": MessageLookupByLibrary.simpleMessage("現在の設定"),
    "nodeOverviewDeviceLimitReached": MessageLookupByLibrary.simpleMessage(
      "端末数の上限に達しました",
    ),
    "nodeOverviewEmptySubtitle": MessageLookupByLibrary.simpleMessage(
      "サブスクリプションURLを貼り付けて確定すると、自動で速度測定し最速ノードに接続します",
    ),
    "nodeOverviewEmptyTitle": MessageLookupByLibrary.simpleMessage(
      "サブスクリプションがまだありません",
    ),
    "nodeOverviewExpireAt": m34,
    "nodeOverviewExpireDaysLeft": m35,
    "nodeOverviewExpireHoursLeft": m36,
    "nodeOverviewExpireSoon": MessageLookupByLibrary.simpleMessage("残り 1 時間未満"),
    "nodeOverviewExpired": MessageLookupByLibrary.simpleMessage(
      "サブスクリプションの有効期限切れ",
    ),
    "nodeOverviewExpiredCountBadge": m37,
    "nodeOverviewExpiringSoonCountBadge": m38,
    "nodeOverviewFileMissing": MessageLookupByLibrary.simpleMessage(
      "設定ファイルがありません",
    ),
    "nodeOverviewFileSource": m39,
    "nodeOverviewGlobalMedian": m40,
    "nodeOverviewGlobalMedianAndBest": m41,
    "nodeOverviewHealthCapacityExceeded": MessageLookupByLibrary.simpleMessage(
      "履歴の保存容量が不足し、一部の結果を保存できませんでした",
    ),
    "nodeOverviewHealthCounts": m42,
    "nodeOverviewHealthStoreUnavailable": MessageLookupByLibrary.simpleMessage(
      "一部の遅延テスト結果を保存できませんでした",
    ),
    "nodeOverviewHistoryNotice": MessageLookupByLibrary.simpleMessage(
      "遅延結果は次の有効なテストまで保持されます。テスト時刻は各ノードの下に表示されます。",
    ),
    "nodeOverviewInUse": MessageLookupByLibrary.simpleMessage("使用中"),
    "nodeOverviewIndependentTest": MessageLookupByLibrary.simpleMessage(
      "独立した遅延テスト",
    ),
    "nodeOverviewLastActiveTest": m43,
    "nodeOverviewLastSync": m44,
    "nodeOverviewLastTest": m45,
    "nodeOverviewLive": MessageLookupByLibrary.simpleMessage("リアルタイム"),
    "nodeOverviewLocalProfile": MessageLookupByLibrary.simpleMessage("ローカル設定"),
    "nodeOverviewLockedManualNode": m46,
    "nodeOverviewManageProfiles": MessageLookupByLibrary.simpleMessage(
      "設定管理 / サブスクリプション更新",
    ),
    "nodeOverviewManualSelectSubtitle": MessageLookupByLibrary.simpleMessage(
      "固定IP",
    ),
    "nodeOverviewManualSelectTitle": MessageLookupByLibrary.simpleMessage(
      "手動選択",
    ),
    "nodeOverviewManualUpdate": MessageLookupByLibrary.simpleMessage("手動更新"),
    "nodeOverviewMedian": m47,
    "nodeOverviewMoreIssues": m48,
    "nodeOverviewNeverExpires": MessageLookupByLibrary.simpleMessage(
      "有効期限：無期限",
    ),
    "nodeOverviewNoActiveProfile": MessageLookupByLibrary.simpleMessage(
      "使用中：未選択",
    ),
    "nodeOverviewNoNodes": MessageLookupByLibrary.simpleMessage(
      "一致するノードがありません",
    ),
    "nodeOverviewNodeUnidentified": MessageLookupByLibrary.simpleMessage(
      "ノードを識別できません",
    ),
    "nodeOverviewParseFailed": MessageLookupByLibrary.simpleMessage(
      "設定の解析に失敗しました",
    ),
    "nodeOverviewPartialSummary": MessageLookupByLibrary.simpleMessage(
      "概要は読み込み済みノードのみを集計します",
    ),
    "nodeOverviewPickerAvailableNodes": m49,
    "nodeOverviewPickerExpireDate": m50,
    "nodeOverviewPickerPerpetual": MessageLookupByLibrary.simpleMessage("無期限"),
    "nodeOverviewPreviewUnsupported": MessageLookupByLibrary.simpleMessage(
      "このプレビューではローカルプロバイダーノードは未対応です",
    ),
    "nodeOverviewProfileCountBadge": m51,
    "nodeOverviewProgress": m52,
    "nodeOverviewProviderDownloadFailed": MessageLookupByLibrary.simpleMessage(
      "プロバイダーのダウンロードに失敗しました",
    ),
    "nodeOverviewProviderNotCached": MessageLookupByLibrary.simpleMessage(
      "プロバイダーのキャッシュを利用できません",
    ),
    "nodeOverviewProviderOptionsUnsupported":
        MessageLookupByLibrary.simpleMessage("これらのプロバイダー設定には対応していません"),
    "nodeOverviewProviderPending": m53,
    "nodeOverviewProviderTooLarge": MessageLookupByLibrary.simpleMessage(
      "プロバイダーがサイズまたはノード数の上限を超えています",
    ),
    "nodeOverviewProviderUnloaded": MessageLookupByLibrary.simpleMessage(
      "プロバイダーのノードはまだ読み込まれていません。全ノードの遅延テスト時に読み込み、不足するキャッシュを取得します。",
    ),
    "nodeOverviewProviderUnsafePath": MessageLookupByLibrary.simpleMessage(
      "プロバイダーファイルが許可されたディレクトリの外にあります",
    ),
    "nodeOverviewProviderUnsafeUrl": MessageLookupByLibrary.simpleMessage(
      "プロバイダーのURLが安全要件を満たしていません",
    ),
    "nodeOverviewProxyConnected": MessageLookupByLibrary.simpleMessage(
      "プロキシ有効 · 接続済み",
    ),
    "nodeOverviewProxyConnectedSmart": m54,
    "nodeOverviewProxyConnectedSmartWithNode": m55,
    "nodeOverviewProxyConnectedWithNode": m56,
    "nodeOverviewProxyDisconnected": MessageLookupByLibrary.simpleMessage(
      "プロキシ無効 · 有効化またはノードの「使用」を押して接続",
    ),
    "nodeOverviewProxyStarting": MessageLookupByLibrary.simpleMessage(
      "プロキシを起動中…",
    ),
    "nodeOverviewProxyStopping": MessageLookupByLibrary.simpleMessage(
      "プロキシを停止中…",
    ),
    "nodeOverviewQuickUse": MessageLookupByLibrary.simpleMessage("最速に接続"),
    "nodeOverviewRemainingTraffic": m57,
    "nodeOverviewRuntimeSource": MessageLookupByLibrary.simpleMessage(
      "実行中のノード",
    ),
    "nodeOverviewSelectProfileTitle": MessageLookupByLibrary.simpleMessage(
      "プロファイル切替",
    ),
    "nodeOverviewShowAllNodes": MessageLookupByLibrary.simpleMessage(
      "すべてのノードを表示",
    ),
    "nodeOverviewSmartInUse": MessageLookupByLibrary.simpleMessage("自動使用中"),
    "nodeOverviewSmartSelectSubtitle": MessageLookupByLibrary.simpleMessage(
      "より快適",
    ),
    "nodeOverviewSmartSelectTitle": MessageLookupByLibrary.simpleMessage(
      "スマート選択",
    ),
    "nodeOverviewStale": MessageLookupByLibrary.simpleMessage("古い可能性あり"),
    "nodeOverviewStatusExpired": MessageLookupByLibrary.simpleMessage("期限切れ"),
    "nodeOverviewStrictUnsupported": MessageLookupByLibrary.simpleMessage(
      "厳格モードでは分離テストを利用できません",
    ),
    "nodeOverviewSwitchedToNode": m58,
    "nodeOverviewSwitchedToSmart": m59,
    "nodeOverviewSwitchedToSmartWithNode": m60,
    "nodeOverviewTestAll": MessageLookupByLibrary.simpleMessage("全ノードの遅延を測定"),
    "nodeOverviewTestCurrent": MessageLookupByLibrary.simpleMessage(
      "現在のプロファイルをテスト",
    ),
    "nodeOverviewTestFailed": MessageLookupByLibrary.simpleMessage("テスト失敗"),
    "nodeOverviewTestInterrupted": MessageLookupByLibrary.simpleMessage(
      "テストを中断しました。以前の測定結果は保持されています",
    ),
    "nodeOverviewTestNode": MessageLookupByLibrary.simpleMessage("遅延テスト"),
    "nodeOverviewTestTimedOut": MessageLookupByLibrary.simpleMessage(
      "テストまたはプロバイダーの読み取りがタイムアウトしました",
    ),
    "nodeOverviewTestUnavailable": MessageLookupByLibrary.simpleMessage(
      "テストを開始できません。バックグラウンドのバージョンを確認してください。",
    ),
    "nodeOverviewTooManyNodes": MessageLookupByLibrary.simpleMessage(
      "ノードが多すぎるためプレビューでは表示できません",
    ),
    "nodeOverviewTrafficUnlimited": MessageLookupByLibrary.simpleMessage(
      "通信量：無制限",
    ),
    "nodeOverviewTurnOffProxy": MessageLookupByLibrary.simpleMessage("停止"),
    "nodeOverviewTurnOnProxy": MessageLookupByLibrary.simpleMessage("有効化"),
    "nodeOverviewTypeUnsupported": MessageLookupByLibrary.simpleMessage(
      "このプロトコルの分離テストは未対応です",
    ),
    "nodeOverviewUntested": MessageLookupByLibrary.simpleMessage("未測定"),
    "nodeOverviewUpdateAllSubscriptions": MessageLookupByLibrary.simpleMessage(
      "すべて更新",
    ),
    "nodeOverviewUpdateSubscription": MessageLookupByLibrary.simpleMessage(
      "購読を更新",
    ),
    "nodeOverviewUpdating": MessageLookupByLibrary.simpleMessage(
      "サブスクリプションを更新中",
    ),
    "nodeOverviewUpdatingShort": MessageLookupByLibrary.simpleMessage("更新中"),
    "nodeOverviewUseNode": MessageLookupByLibrary.simpleMessage("使用"),
    "nodeOverviewUsedOfTotalTraffic": m61,
    "nodeOverviewUsedTrafficOnly": m62,
    "none": MessageLookupByLibrary.simpleMessage("なし"),
    "notSelectedTip": MessageLookupByLibrary.simpleMessage(
      "現在のプロキシグループは選択できません",
    ),
    "noviceMode": MessageLookupByLibrary.simpleMessage("かんたんモード"),
    "nullProfileDesc": MessageLookupByLibrary.simpleMessage(
      "プロファイルがありません。追加してください",
    ),
    "nullScriptTip": MessageLookupByLibrary.simpleMessage("スクリプトはありません"),
    "nullTip": m63,
    "numberTip": m64,
    "oneColumn": MessageLookupByLibrary.simpleMessage("1列"),
    "oneline": MessageLookupByLibrary.simpleMessage("オンライン"),
    "onlyIcon": MessageLookupByLibrary.simpleMessage("アイコンのみ"),
    "onlyOtherApps": MessageLookupByLibrary.simpleMessage("サードパーティアプリのみ"),
    "onlyStatisticsProxy": MessageLookupByLibrary.simpleMessage("プロキシのみ統計"),
    "onlyStatisticsProxyDesc": MessageLookupByLibrary.simpleMessage(
      "有効化するとプロキシトラフィックのみ統計",
    ),
    "openLogsFolder": MessageLookupByLibrary.simpleMessage("ログフォルダを開く"),
    "openPanel": MessageLookupByLibrary.simpleMessage("パネルを開く"),
    "options": MessageLookupByLibrary.simpleMessage("オプション"),
    "originalRepository": MessageLookupByLibrary.simpleMessage("オリジナルリポジトリ"),
    "other": MessageLookupByLibrary.simpleMessage("その他"),
    "otherContributors": MessageLookupByLibrary.simpleMessage("貢献者"),
    "outboundMode": MessageLookupByLibrary.simpleMessage("アウトバウンドモード"),
    "override": MessageLookupByLibrary.simpleMessage("上書き"),
    "overrideAutoSavedHint": MessageLookupByLibrary.simpleMessage(
      "変更は自動保存され即座に反映されます",
    ),
    "overrideDesc": MessageLookupByLibrary.simpleMessage("プロキシ関連設定を上書き"),
    "overrideDns": MessageLookupByLibrary.simpleMessage("DNS上書き"),
    "overrideDnsDesc": MessageLookupByLibrary.simpleMessage(
      "有効化するとプロファイルのDNS設定を上書き",
    ),
    "overrideInvalidTip": MessageLookupByLibrary.simpleMessage(
      "スクリプトモードでは有効になりません",
    ),
    "overrideNetworkSettings": MessageLookupByLibrary.simpleMessage(
      "ネットワーク設定を上書き",
    ),
    "overrideNetworkSettingsDesc": MessageLookupByLibrary.simpleMessage(
      "プロバイダー設定のネットワーク設定を無視",
    ),
    "overrideOriginRules": MessageLookupByLibrary.simpleMessage("元のルールを上書き"),
    "overrideProviderSettings": MessageLookupByLibrary.simpleMessage("上書き"),
    "overrideProviderSettingsDesc": MessageLookupByLibrary.simpleMessage(
      "プロバイダーの設定を無視して手動で管理",
    ),
    "palette": MessageLookupByLibrary.simpleMessage("パレット"),
    "password": MessageLookupByLibrary.simpleMessage("パスワード"),
    "paste": MessageLookupByLibrary.simpleMessage("貼り付け"),
    "pasteFromClipboard": MessageLookupByLibrary.simpleMessage("貼り付け"),
    "pleaseBindWebDAV": MessageLookupByLibrary.simpleMessage(
      "WebDAVをバインドしてください",
    ),
    "pleaseEnterScriptName": MessageLookupByLibrary.simpleMessage(
      "スクリプト名を入力してください",
    ),
    "pleaseInputAdminPassword": MessageLookupByLibrary.simpleMessage(
      "管理者パスワードを入力",
    ),
    "pleaseUploadFile": MessageLookupByLibrary.simpleMessage(
      "ファイルをアップロードしてください",
    ),
    "pleaseUploadValidQrcode": MessageLookupByLibrary.simpleMessage(
      "有効なQRコードをアップロードしてください",
    ),
    "port": MessageLookupByLibrary.simpleMessage("ポート"),
    "portConflictTip": MessageLookupByLibrary.simpleMessage("別のポートを入力してください"),
    "portTip": m65,
    "preferH3Desc": MessageLookupByLibrary.simpleMessage("DOHのHTTP/3を優先使用"),
    "pressKeyboard": MessageLookupByLibrary.simpleMessage("キーボードを押してください"),
    "preview": MessageLookupByLibrary.simpleMessage("プレビュー"),
    "profile": MessageLookupByLibrary.simpleMessage("プロファイル"),
    "profileAutoUpdateIntervalInvalidValidationDesc":
        MessageLookupByLibrary.simpleMessage("有効な間隔形式を入力してください"),
    "profileAutoUpdateIntervalNullValidationDesc":
        MessageLookupByLibrary.simpleMessage("自動更新間隔を入力してください"),
    "profileHasUpdate": MessageLookupByLibrary.simpleMessage(
      "プロファイルが変更されました。自動更新を無効化しますか？",
    ),
    "profileNameNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "プロファイル名を入力してください",
    ),
    "profileParseErrorDesc": MessageLookupByLibrary.simpleMessage(
      "プロファイル解析エラー",
    ),
    "profileUrlInvalidValidationDesc": MessageLookupByLibrary.simpleMessage(
      "有効なプロファイルURLを入力してください",
    ),
    "profileUrlNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "プロファイルURLを入力してください",
    ),
    "profiles": MessageLookupByLibrary.simpleMessage("プロファイル一覧"),
    "profilesSort": MessageLookupByLibrary.simpleMessage("プロファイルの並び替え"),
    "project": MessageLookupByLibrary.simpleMessage("プロジェクト"),
    "providers": MessageLookupByLibrary.simpleMessage("プロバイダー"),
    "proxies": MessageLookupByLibrary.simpleMessage("プロキシ"),
    "proxiesSetting": MessageLookupByLibrary.simpleMessage("プロキシ設定"),
    "proxyGroup": MessageLookupByLibrary.simpleMessage("プロキシグループ"),
    "proxyNameserver": MessageLookupByLibrary.simpleMessage("プロキシネームサーバー"),
    "proxyNameserverDesc": MessageLookupByLibrary.simpleMessage(
      "プロキシノード解決用ドメイン",
    ),
    "proxyPort": MessageLookupByLibrary.simpleMessage("プロキシポート"),
    "proxyPortDesc": MessageLookupByLibrary.simpleMessage("Clashのリスニングポートを設定"),
    "proxyProviders": MessageLookupByLibrary.simpleMessage("プロキシプロバイダー"),
    "purchase": MessageLookupByLibrary.simpleMessage("購入"),
    "purchaseAcquirePlanCode": MessageLookupByLibrary.simpleMessage(
      "このプランのコードを取得",
    ),
    "purchaseAcquireSheetSubtitle": MessageLookupByLibrary.simpleMessage(
      "下記のストアまたは WeChat サポートでコードを取得し、この画面で引き換えてください。アプリ内で注文は作成されません。",
    ),
    "purchaseAuthTabLogin": MessageLookupByLibrary.simpleMessage("ログイン"),
    "purchaseAuthTabRegister": MessageLookupByLibrary.simpleMessage(
      "無料登録で2G受取",
    ),
    "purchaseAvailablePlans": MessageLookupByLibrary.simpleMessage("購入可能なプラン"),
    "purchaseBackupContactsLabel": MessageLookupByLibrary.simpleMessage(
      "バックアップ窓口（WeChat）",
    ),
    "purchaseClearCode": MessageLookupByLibrary.simpleMessage("コードをクリア"),
    "purchaseClipboardEmpty": MessageLookupByLibrary.simpleMessage(
      "クリップボードに有効な引き換えコードが見つかりません。",
    ),
    "purchaseContactDescription": MessageLookupByLibrary.simpleMessage(
      "オンライン決済は現在ご利用いただけません。購入または更新については、以下のいずれかのWeChatアカウントを追加してください。",
    ),
    "purchaseCopyInquiry": MessageLookupByLibrary.simpleMessage("問い合わせ文をコピー"),
    "purchaseEmailDomainError": MessageLookupByLibrary.simpleMessage(
      "このメールドメインは利用できません。別のメールアドレスをお試しください。",
    ),
    "purchaseEmailExistsError": MessageLookupByLibrary.simpleMessage(
      "このメールアドレスは登録済みです。「ログイン」に切り替えてください。",
    ),
    "purchaseFilterAll": MessageLookupByLibrary.simpleMessage("すべて"),
    "purchaseFilterOnetime": MessageLookupByLibrary.simpleMessage("通信量パック"),
    "purchaseFilterPeriod": MessageLookupByLibrary.simpleMessage("定期プラン"),
    "purchaseGetCardDescription": MessageLookupByLibrary.simpleMessage(
      "セルフストア、オンラインサポート、または下記の WeChat からギフトカードの購入・相談ができます。",
    ),
    "purchaseGmailAliasError": MessageLookupByLibrary.simpleMessage(
      "Gmail エイリアス（+ 付き）は利用できません。通常のアドレスをご使用ください。",
    ),
    "purchaseHandoffDescription": MessageLookupByLibrary.simpleMessage(
      "購入後にコードをコピーしてこのウィンドウに戻ると、特典を自動確認します（確認なしでは消費されません）。",
    ),
    "purchaseHandoffPasteAction": MessageLookupByLibrary.simpleMessage(
      "貼り付けて確認",
    ),
    "purchaseHandoffTitle": m66,
    "purchaseHeaderSyncedBadge": MessageLookupByLibrary.simpleMessage(
      "高速ノード準備完了",
    ),
    "purchaseHeaderTrialBadge": MessageLookupByLibrary.simpleMessage(
      "新規登録で 2 GiB 無料体験 · 無期限データパック",
    ),
    "purchaseHidePassword": MessageLookupByLibrary.simpleMessage("パスワードを隠す"),
    "purchaseInquiryTemplate": m67,
    "purchaseJumpToWorkbench": MessageLookupByLibrary.simpleMessage(
      "コードをお持ちの方はこちら",
    ),
    "purchaseLoginDescription": MessageLookupByLibrary.simpleMessage(
      "アカウントにサインインしてコードを引き換えると、プランと高速ノードが自動的に同期されます。",
    ),
    "purchaseNewActivationBadge": MessageLookupByLibrary.simpleMessage("新規有効化"),
    "purchaseOnlineSupport": MessageLookupByLibrary.simpleMessage("オンラインサポート"),
    "purchaseOpenNodesAction": MessageLookupByLibrary.simpleMessage(
      "プロファイルとノードを表示",
    ),
    "purchasePasswordMinLength": MessageLookupByLibrary.simpleMessage(
      "パスワードは8文字以上で入力してください。",
    ),
    "purchasePlanBuyNow": MessageLookupByLibrary.simpleMessage("購入する"),
    "purchasePlanCollapseDetails": MessageLookupByLibrary.simpleMessage(
      "詳細を折りたたむ",
    ),
    "purchasePlanDetails": MessageLookupByLibrary.simpleMessage("プランの詳細"),
    "purchasePlanDevices": MessageLookupByLibrary.simpleMessage("デバイス数の上限"),
    "purchasePlanExpandDetails": MessageLookupByLibrary.simpleMessage(
      "詳細をすべて表示",
    ),
    "purchasePlanFeaturedBadge": MessageLookupByLibrary.simpleMessage("おすすめ"),
    "purchasePlanImageNotLoaded": MessageLookupByLibrary.simpleMessage(
      "外部画像は読み込まれていません",
    ),
    "purchasePlanLowStock": m68,
    "purchasePlanNotProvided": MessageLookupByLibrary.simpleMessage("未提供"),
    "purchasePlanResetMonthStart": MessageLookupByLibrary.simpleMessage("毎月1日"),
    "purchasePlanResetMonthlyExpiry": MessageLookupByLibrary.simpleMessage(
      "毎月の有効期限日",
    ),
    "purchasePlanResetNever": MessageLookupByLibrary.simpleMessage("自動リセットなし"),
    "purchasePlanResetPrice": MessageLookupByLibrary.simpleMessage(
      "通信量リセットの表示価格",
    ),
    "purchasePlanResetSystem": MessageLookupByLibrary.simpleMessage(
      "システム設定に従う",
    ),
    "purchasePlanResetUnknown": m69,
    "purchasePlanResetYearStart": MessageLookupByLibrary.simpleMessage(
      "毎年1月1日",
    ),
    "purchasePlanResetYearlyExpiry": MessageLookupByLibrary.simpleMessage(
      "毎年の有効期限月日",
    ),
    "purchasePlanSalesCapacity": MessageLookupByLibrary.simpleMessage("残りの販売枠"),
    "purchasePlanSoldOut": MessageLookupByLibrary.simpleMessage("売り切れ"),
    "purchasePlanSpeed": MessageLookupByLibrary.simpleMessage("速度上限"),
    "purchasePlanTrafficReset": MessageLookupByLibrary.simpleMessage(
      "通信量のリセット",
    ),
    "purchasePlanUnlimited": MessageLookupByLibrary.simpleMessage("無制限"),
    "purchasePlansDescription": MessageLookupByLibrary.simpleMessage(
      "価格はサイトの表示額です。「購入する」からセルフストアでギフトカードを取得し、ここで引き換えてください。",
    ),
    "purchasePlansEmpty": MessageLookupByLibrary.simpleMessage(
      "現在購入可能なプランはありません。",
    ),
    "purchasePlansError": MessageLookupByLibrary.simpleMessage(
      "プランを読み込めませんでした。もう一度お試しください。",
    ),
    "purchasePlansErrorHint": MessageLookupByLibrary.simpleMessage(
      "右側のログイン・無料登録・ギフトカード引換はそのまま利用できます。",
    ),
    "purchasePlansLoading": MessageLookupByLibrary.simpleMessage("プランを読み込み中…"),
    "purchasePlansRetry": MessageLookupByLibrary.simpleMessage("プランを再読み込み"),
    "purchasePreloginCodeHint": MessageLookupByLibrary.simpleMessage(
      "コードをお持ちですか？ここに入力するとログイン後に自動で確認します",
    ),
    "purchaseRegisterSubmit": MessageLookupByLibrary.simpleMessage(
      "無料登録してノードを同期",
    ),
    "purchaseRegisterTrialBanner": MessageLookupByLibrary.simpleMessage(
      "登録するとすぐに 2 GiB の無期限体験通信量が付与され、高速ノードが自動設定されます。",
    ),
    "purchaseRegisterWebRequiredError": MessageLookupByLibrary.simpleMessage(
      "メール認証またはCAPTCHAが有効です。下の「Webサイトでアカウント作成」をご利用ください。",
    ),
    "purchaseRegistering": MessageLookupByLibrary.simpleMessage("登録して有効化中…"),
    "purchaseRegistrationClosedError": MessageLookupByLibrary.simpleMessage(
      "現在、新規登録は停止されています。",
    ),
    "purchaseRenewalBadge": MessageLookupByLibrary.simpleMessage("更新"),
    "purchaseShowPassword": MessageLookupByLibrary.simpleMessage("パスワードを表示"),
    "purchaseStepBrowse": MessageLookupByLibrary.simpleMessage("① プラン確認・コード取得"),
    "purchaseStepRedeem": MessageLookupByLibrary.simpleMessage("② サインインして確認"),
    "purchaseStepSync": MessageLookupByLibrary.simpleMessage("③ ノード自動同期"),
    "purchaseTitle": MessageLookupByLibrary.simpleMessage("購入と更新"),
    "pureBlackMode": MessageLookupByLibrary.simpleMessage("純黒モード"),
    "qrcode": MessageLookupByLibrary.simpleMessage("QRコード"),
    "qrcodeDesc": MessageLookupByLibrary.simpleMessage("QRコードをスキャンしてプロファイルを取得"),
    "rainbowScheme": MessageLookupByLibrary.simpleMessage("レインボー"),
    "recovery": MessageLookupByLibrary.simpleMessage("復元"),
    "recoveryAll": MessageLookupByLibrary.simpleMessage("全データ復元"),
    "recoveryProfiles": MessageLookupByLibrary.simpleMessage("プロファイルのみ復元"),
    "recoveryStrategy": MessageLookupByLibrary.simpleMessage("リカバリー戦略"),
    "recoveryStrategy_compatible": MessageLookupByLibrary.simpleMessage("互換性"),
    "recoveryStrategy_override": MessageLookupByLibrary.simpleMessage(
      "オーバーライド",
    ),
    "recoverySuccess": MessageLookupByLibrary.simpleMessage("復元成功"),
    "redirPort": MessageLookupByLibrary.simpleMessage("Redirポート"),
    "redo": MessageLookupByLibrary.simpleMessage("やり直す"),
    "regExp": MessageLookupByLibrary.simpleMessage("正規表現"),
    "remote": MessageLookupByLibrary.simpleMessage("リモート"),
    "remoteBackupDesc": MessageLookupByLibrary.simpleMessage(
      "WebDAVにデータをバックアップ",
    ),
    "remoteRecoveryDesc": MessageLookupByLibrary.simpleMessage(
      "WebDAVからデータを復元",
    ),
    "remove": MessageLookupByLibrary.simpleMessage("削除"),
    "rename": MessageLookupByLibrary.simpleMessage("リネーム"),
    "renew": MessageLookupByLibrary.simpleMessage("更新"),
    "requests": MessageLookupByLibrary.simpleMessage("リクエスト"),
    "requestsDesc": MessageLookupByLibrary.simpleMessage("最近のリクエスト記録を表示"),
    "reset": MessageLookupByLibrary.simpleMessage("リセット"),
    "resetTip": MessageLookupByLibrary.simpleMessage("リセットを確定"),
    "resources": MessageLookupByLibrary.simpleMessage("リソース"),
    "resourcesDesc": MessageLookupByLibrary.simpleMessage("外部リソース関連情報"),
    "respectRules": MessageLookupByLibrary.simpleMessage("ルール尊重"),
    "respectRulesDesc": MessageLookupByLibrary.simpleMessage(
      "DNS接続がルールに従う（proxy-server-nameserverの設定が必要）",
    ),
    "restart": MessageLookupByLibrary.simpleMessage("再起動"),
    "routeAddress": MessageLookupByLibrary.simpleMessage("ルートアドレス"),
    "routeAddressDesc": MessageLookupByLibrary.simpleMessage("ルートアドレスを設定"),
    "routeMode": MessageLookupByLibrary.simpleMessage("ルートモード"),
    "routeMode_bypassPrivate": MessageLookupByLibrary.simpleMessage(
      "プライベートルートをバイパス",
    ),
    "routeMode_config": MessageLookupByLibrary.simpleMessage("設定を使用"),
    "ru": MessageLookupByLibrary.simpleMessage("ロシア語"),
    "rule": MessageLookupByLibrary.simpleMessage("ルールに従って"),
    "ruleName": MessageLookupByLibrary.simpleMessage("ルール名"),
    "ruleProviders": MessageLookupByLibrary.simpleMessage("ルールプロバイダー"),
    "ruleTarget": MessageLookupByLibrary.simpleMessage("ルール対象"),
    "running": MessageLookupByLibrary.simpleMessage("実行中"),
    "save": MessageLookupByLibrary.simpleMessage("保存"),
    "saveChanges": MessageLookupByLibrary.simpleMessage("変更を保存しますか？"),
    "saveTip": MessageLookupByLibrary.simpleMessage("保存してもよろしいですか？"),
    "scan": MessageLookupByLibrary.simpleMessage("スキャン"),
    "script": MessageLookupByLibrary.simpleMessage("スクリプト"),
    "search": MessageLookupByLibrary.simpleMessage("検索"),
    "seconds": MessageLookupByLibrary.simpleMessage("秒"),
    "selectAll": MessageLookupByLibrary.simpleMessage("すべて選択"),
    "selected": MessageLookupByLibrary.simpleMessage("選択済み"),
    "selectedCountTitle": m70,
    "settings": MessageLookupByLibrary.simpleMessage("設定"),
    "show": MessageLookupByLibrary.simpleMessage("表示"),
    "shrink": MessageLookupByLibrary.simpleMessage("縮小"),
    "silentLaunch": MessageLookupByLibrary.simpleMessage("バックグラウンド起動"),
    "silentLaunchDesc": MessageLookupByLibrary.simpleMessage("バックグラウンドで起動"),
    "size": MessageLookupByLibrary.simpleMessage("サイズ"),
    "socksPort": MessageLookupByLibrary.simpleMessage("Socksポート"),
    "sort": MessageLookupByLibrary.simpleMessage("並び替え"),
    "source": MessageLookupByLibrary.simpleMessage("ソース"),
    "sourceIp": MessageLookupByLibrary.simpleMessage("送信元IP"),
    "stackMode": MessageLookupByLibrary.simpleMessage("スタックモード"),
    "standard": MessageLookupByLibrary.simpleMessage("標準"),
    "start": MessageLookupByLibrary.simpleMessage("開始"),
    "startVpn": MessageLookupByLibrary.simpleMessage("VPNを開始中..."),
    "status": MessageLookupByLibrary.simpleMessage("ステータス"),
    "statusDesc": MessageLookupByLibrary.simpleMessage("無効時はシステムDNSを使用"),
    "stop": MessageLookupByLibrary.simpleMessage("停止"),
    "stopVpn": MessageLookupByLibrary.simpleMessage("VPNを停止中..."),
    "stopped": MessageLookupByLibrary.simpleMessage("停止中"),
    "style": MessageLookupByLibrary.simpleMessage("スタイル"),
    "subRule": MessageLookupByLibrary.simpleMessage("サブルール"),
    "submit": MessageLookupByLibrary.simpleMessage("送信"),
    "subscriptionClipboardEmptyError": MessageLookupByLibrary.simpleMessage(
      "クリップボードが空です。先にURLをコピーしてください",
    ),
    "subscriptionEternal": MessageLookupByLibrary.simpleMessage("無期限"),
    "subscriptionExpired": MessageLookupByLibrary.simpleMessage(
      "サブスクリプションが期限切れになりました",
    ),
    "subscriptionExpiresInDays": m71,
    "subscriptionExpiresSoon": MessageLookupByLibrary.simpleMessage(
      "サブスクリプションがまもなく期限切れ",
    ),
    "subscriptionExpiresToday": MessageLookupByLibrary.simpleMessage(
      "サブスクリプションは本日期限切れになります",
    ),
    "subscriptionImportAuthOrNotFoundError":
        MessageLookupByLibrary.simpleMessage("サブスクリプションURLが無効または期限切れです"),
    "subscriptionImportGenericError": MessageLookupByLibrary.simpleMessage(
      "サブスクリプションのインポートに失敗しました。URLを確認してください",
    ),
    "subscriptionImportInvalidConfigError":
        MessageLookupByLibrary.simpleMessage(
          "有効なサブスクリプション設定ではありません（WebページのURLの可能性があります）",
        ),
    "subscriptionImportTimeoutError": MessageLookupByLibrary.simpleMessage(
      "サブスクリプションの取得がタイムアウトしました。通信環境を確認してください",
    ),
    "subscriptionUrlEmptyError": MessageLookupByLibrary.simpleMessage(
      "先にサブスクリプションURLを貼り付けてください",
    ),
    "subscriptionUrlInvalidError": MessageLookupByLibrary.simpleMessage(
      "有効な http(s):// サブスクリプションURLが見つかりません",
    ),
    "support": MessageLookupByLibrary.simpleMessage("サポート"),
    "sync": MessageLookupByLibrary.simpleMessage("同期"),
    "system": MessageLookupByLibrary.simpleMessage("システム"),
    "systemApp": MessageLookupByLibrary.simpleMessage("システムアプリ"),
    "systemFont": MessageLookupByLibrary.simpleMessage("システムフォント"),
    "systemProxy": MessageLookupByLibrary.simpleMessage("システムプロキシ"),
    "systemProxyDesc": MessageLookupByLibrary.simpleMessage(
      "HTTPプロキシをVpnServiceに接続",
    ),
    "tab": MessageLookupByLibrary.simpleMessage("タブ"),
    "tabAnimation": MessageLookupByLibrary.simpleMessage("タブアニメーション"),
    "tabAnimationDesc": MessageLookupByLibrary.simpleMessage("モバイル表示でのみ有効"),
    "tcpConcurrent": MessageLookupByLibrary.simpleMessage("TCP並列処理"),
    "tcpConcurrentDesc": MessageLookupByLibrary.simpleMessage("TCP並列処理を許可"),
    "testUrl": MessageLookupByLibrary.simpleMessage("URLテスト"),
    "textScale": MessageLookupByLibrary.simpleMessage("テキストスケーリング"),
    "thanks": MessageLookupByLibrary.simpleMessage("貢献に感謝"),
    "theme": MessageLookupByLibrary.simpleMessage("テーマ"),
    "themeColor": MessageLookupByLibrary.simpleMessage("テーマカラー"),
    "themeDesc": MessageLookupByLibrary.simpleMessage("ダークモードの設定、色の調整"),
    "themeMode": MessageLookupByLibrary.simpleMessage("テーマモード"),
    "threeColumns": MessageLookupByLibrary.simpleMessage("3列"),
    "tight": MessageLookupByLibrary.simpleMessage("密"),
    "time": MessageLookupByLibrary.simpleMessage("時間"),
    "tip": MessageLookupByLibrary.simpleMessage("ヒント"),
    "toggle": MessageLookupByLibrary.simpleMessage("トグル"),
    "tonalSpotScheme": MessageLookupByLibrary.simpleMessage("トーンスポット"),
    "tooFrequentOperation": MessageLookupByLibrary.simpleMessage(
      "再度更新する前に15秒お待ちください",
    ),
    "tools": MessageLookupByLibrary.simpleMessage("設定"),
    "tproxyPort": MessageLookupByLibrary.simpleMessage("Tproxyポート"),
    "trafficUnlimited": MessageLookupByLibrary.simpleMessage("無制限トラフィック"),
    "trafficUsage": MessageLookupByLibrary.simpleMessage("トラフィック使用量"),
    "tun": MessageLookupByLibrary.simpleMessage("TUN"),
    "tunDesc": MessageLookupByLibrary.simpleMessage("管理者モードでのみ有効"),
    "tunDisableAction": MessageLookupByLibrary.simpleMessage("停止を要求"),
    "tunErrorAdapterCreate": MessageLookupByLibrary.simpleMessage(
      "Windows が仮想アダプターを追加できませんでした。しばらくしてから再試行してください",
    ),
    "tunErrorAuthorization": MessageLookupByLibrary.simpleMessage(
      "管理者の許可が必要です。再度有効にしてください",
    ),
    "tunErrorComponents": MessageLookupByLibrary.simpleMessage(
      "バックグラウンドの構成が異なります。再度有効にして更新してください",
    ),
    "tunErrorConfiguration": MessageLookupByLibrary.simpleMessage(
      "設定が適用されませんでした",
    ),
    "tunErrorLegacyAgent": MessageLookupByLibrary.simpleMessage(
      "古いバックグラウンドアプリを終了してから、このバージョンを開き直してください",
    ),
    "tunErrorProfileRequired": MessageLookupByLibrary.simpleMessage(
      "接続する前に、読み取り可能な空でない設定を選択してください",
    ),
    "tunErrorStart": MessageLookupByLibrary.simpleMessage(
      "インターフェースを起動できません。再度有効にしてください",
    ),
    "tunErrorStop": MessageLookupByLibrary.simpleMessage(
      "停止できませんでした。現在の状態を確認してください",
    ),
    "tunErrorUnavailable": MessageLookupByLibrary.simpleMessage(
      "状態を確認できません。バックグラウンドのバージョンを確認してください",
    ),
    "tunStatusFailure": m72,
    "tunStatusOff": MessageLookupByLibrary.simpleMessage("停止中"),
    "tunStatusOn": MessageLookupByLibrary.simpleMessage("起動済み"),
    "tunStatusStarting": MessageLookupByLibrary.simpleMessage("起動しています…"),
    "tunStatusStopping": MessageLookupByLibrary.simpleMessage("停止しています…"),
    "tunStatusUnknown": MessageLookupByLibrary.simpleMessage("状態不明"),
    "tunStatusWaiting": MessageLookupByLibrary.simpleMessage("プロキシの起動時に有効化"),
    "twoColumns": MessageLookupByLibrary.simpleMessage("2列"),
    "unableToUpdateCurrentProfileDesc": MessageLookupByLibrary.simpleMessage(
      "現在のプロファイルを更新できません",
    ),
    "undo": MessageLookupByLibrary.simpleMessage("元に戻す"),
    "unifiedDelay": MessageLookupByLibrary.simpleMessage("統一遅延"),
    "unifiedDelayDesc": MessageLookupByLibrary.simpleMessage(
      "ハンドシェイクなどの余分な遅延を削除",
    ),
    "unknown": MessageLookupByLibrary.simpleMessage("不明"),
    "unnamed": MessageLookupByLibrary.simpleMessage("無題"),
    "update": MessageLookupByLibrary.simpleMessage("更新"),
    "updateAllGeoData": MessageLookupByLibrary.simpleMessage("すべての地理データを更新"),
    "upload": MessageLookupByLibrary.simpleMessage("アップロード"),
    "url": MessageLookupByLibrary.simpleMessage("URL"),
    "urlDesc": MessageLookupByLibrary.simpleMessage("URL経由でプロファイルを取得"),
    "urlTip": m73,
    "useHosts": MessageLookupByLibrary.simpleMessage("ホストを使用"),
    "useSystemHosts": MessageLookupByLibrary.simpleMessage("システムホストを使用"),
    "value": MessageLookupByLibrary.simpleMessage("値"),
    "vibrantScheme": MessageLookupByLibrary.simpleMessage("ビブラント"),
    "view": MessageLookupByLibrary.simpleMessage("表示"),
    "vpnDesc": MessageLookupByLibrary.simpleMessage("VPN関連設定の変更"),
    "vpnEnableDesc": MessageLookupByLibrary.simpleMessage(
      "VpnService経由で全システムトラフィックをルーティング",
    ),
    "vpnSystemProxyDesc": MessageLookupByLibrary.simpleMessage(
      "HTTPプロキシをVpnServiceに接続",
    ),
    "vpnTip": MessageLookupByLibrary.simpleMessage("変更はVPN再起動後に有効"),
    "webDAVConfiguration": MessageLookupByLibrary.simpleMessage("WebDAV設定"),
    "wechatId": MessageLookupByLibrary.simpleMessage("WeChat ID"),
    "whitelistMode": MessageLookupByLibrary.simpleMessage("ホワイトリストモード"),
    "years": MessageLookupByLibrary.simpleMessage("年"),
    "zashboardInApp": MessageLookupByLibrary.simpleMessage(
      "アプリ内で zashboard を開く",
    ),
    "zashboardInAppDesc": MessageLookupByLibrary.simpleMessage(
      "外部ブラウザに切り替えず、内蔵ブラウザでパネルを表示します",
    ),
    "zh_CN": MessageLookupByLibrary.simpleMessage("簡体字中国語"),
  };
}
