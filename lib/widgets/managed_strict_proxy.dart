import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'dart:math';

import 'package:flclashx/clash/service.dart';
import 'package:flclashx/common/per_app_policy.dart';
import 'package:flclashx/common/path.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The OS-owned MDM mapping remains authoritative even while this view is closed.
class ManagedStrictProxyPanel extends StatefulWidget {
  const ManagedStrictProxyPanel({super.key});
  @override
  State<ManagedStrictProxyPanel> createState() => _ManagedStrictProxyPanelState();
}

class _ManagedStrictProxyPanelState extends State<ManagedStrictProxyPanel> {
  static const _channel = MethodChannel('freedomcloud/managed_strict');
  final _dns = TextEditingController();
  List<Map<String, dynamic>> _profiles = [];
  String? _account;
  String _message = '加载受管配置后，选择 DNS 并应用当前 PROXY / BLOCK 应用策略。';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run(_refresh));
  }
  @override
  void dispose() { _dns.dispose(); super.dispose(); }

  Future<Map<String, dynamic>> _call(String method, [Map<String, dynamic>? arguments]) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(method, arguments)
        .timeout(const Duration(seconds: 30));
    if (result == null) throw StateError('系统未返回结果');
    return result;
  }
  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try { await operation(); }
    catch (error) {
      if (mounted) setState(() => _message = error is PlatformException
          ? (error.message ?? error.code) : '操作未完成：${error is StateError ? error.message : error.runtimeType}');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _refresh() async {
    final raw = await _channel.invokeListMethod<dynamic>('profiles')
        .timeout(const Duration(seconds: 15));
    final profiles = (raw ?? []).map((item) => Map<String, dynamic>.from(item as Map)).toList();
    if (!mounted) return;
    setState(() {
      _profiles = profiles.where((item) => (item['account'] as String? ?? '').isNotEmpty).toList();
      if (!_profiles.any((item) => item['account'] == _account)) {
        _account = _profiles.isEmpty ? null : _profiles.first['account'] as String;
      }
      if (_profiles.isEmpty) _message = '尚未找到受管按应用 VPN 配置。请由 MDM 下发配置和应用映射。';
    });
  }
  String _secret() {
    final random = Random.secure();
    return List.generate(32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
  Future<void> _apply() async {
    final account = _account;
    final service = clashService;
    if (account == null || service == null) throw StateError('请选择受管配置，并启动 Core');
    final dns = _dns.text.split(RegExp(r'[,\s]+')).where((item) => item.isNotEmpty).toList();
    if (dns.isEmpty) throw StateError('填写受管 DNS 的 IP 地址；不会使用隐式本机 DNS');
    await perAppPolicyStore.ensureLoaded();
    final entries = perAppPolicyStore.entries.where((entry) =>
        entry.policy == ApplicationRoutingPolicy.proxy || entry.policy == ApplicationRoutingPolicy.block).toList();
    if (entries.isEmpty) throw StateError('至少选择一个 PROXY 或 BLOCK 应用');
    await _call('prepare', {'account': account});
    Map<String, dynamic>? status;
    for (var attempt = 0; attempt < 10; attempt++) {
      try { status = await _call('status', {'account': account}); break; }
      on PlatformException { if (attempt == 9) rethrow; await Future<void>.delayed(const Duration(milliseconds: 500)); }
    }
    final generation = max(DateTime.now().microsecondsSinceEpoch, ((status?['generation'] as num?)?.toInt() ?? 0) + 1);
    final identities = <Map<String, dynamic>>[];
    final credentials = <String, Map<String, String>>{};
    for (final entry in entries) {
      final identity = await _channel.invokeMapMethod<String, dynamic>('inspectIdentity', entry.path);
      if (identity == null) throw StateError('无法解析签名应用身份');
      identities.add(identity);
      if (entry.policy == ApplicationRoutingPolicy.proxy) {
        final group = entry.targetGroup ?? 'GLOBAL';
        credentials.putIfAbsent(group, () => {'targetGroup': group, 'username': _secret(), 'password': _secret()});
      }
    }
    final ingress = await service.invoke<Map>(method: ActionMethod.configureStrictIngress,
      data: jsonEncode({'protocol': 2, 'generation': generation, 'entries': credentials.values.toList()}),
      defaultValue: const {}, timeout: const Duration(seconds: 15));
    if (ingress['generation'] != generation || ingress['entries'] is! List) throw StateError('Core 严格入口配置被拒绝');
    final endpoints = <String, String>{for (final item in ingress['entries'] as List)
      (item as Map)['targetGroup'] as String: item['endpoint'] as String};
    final policies = <Map<String, dynamic>>[];
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final group = entry.targetGroup ?? 'GLOBAL';
      final credential = credentials[group];
      final endpoint = endpoints[group];
      final port = endpoint == null ? 0 : int.tryParse(endpoint.split(':').last);
      if (entry.policy == ApplicationRoutingPolicy.proxy && (port == null || port == 0)) throw StateError('Core 未返回应用代理入口');
      policies.add({'signingIdentifier': identities[index]['signingIdentifier'],
        'codeDirectoryHash': identities[index]['codeDirectoryHash'],
        'action': entry.policy == ApplicationRoutingPolicy.block ? 'block' : 'proxy',
        'port': port ?? 0, 'username': credential?['username'] ?? '', 'password': credential?['password'] ?? '',
        'udpPort': int.tryParse((ingress['udpEndpoint'] as String? ?? '').split(':').last) ?? 0,
        'generation': generation});
    }
    final reply = await _call('configure', {'account': account, 'paths': entries.map((entry) => entry.path).toList(),
      'configuration': {'generation': generation, 'policies': policies, 'dnsServers': dns}});
    if (reply['ok'] != true) throw StateError('扩展未接受策略：${reply['code'] ?? 'unknown'}');
    if (mounted) setState(() => _message = '策略已由扩展接收，MDM 应用映射持续生效。');
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('macOS 受管严格代理'),
    content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('MDM 接管 PROXY / BLOCK 应用。修改规则会先阻断受管流量，需重新应用策略；DIRECT / INHERIT 应用须从 MDM 映射移除。'),
        const SizedBox(height: 12),
        DropdownButton<String>(isExpanded: true, value: _account, hint: const Text('选择受管 VPN'),
          items: _profiles.map((item) => DropdownMenuItem<String>(value: item['account'] as String,
            child: Text(item['name'] as String? ?? 'Managed VPN'))).toList(),
          onChanged: _busy ? null : (value) => setState(() => _account = value)),
        TextField(controller: _dns, enabled: !_busy, decoration: const InputDecoration(labelText: '受管 DNS IP（逗号分隔）')),
        const SizedBox(height: 12), Text(_message),
        if (_busy) const LinearProgressIndicator(),
      ]))),
    actions: [
      TextButton(onPressed: _busy ? null : () => _run(() async {
        final reply = await _call('enableBackgroundAgent', {'home': await appPath.homeDirPath});
        if (mounted) setState(() => _message = reply['notice'] as String? ?? '已登记登录后后台 Agent。若已有 Agent 正在运行，请先通过应用正常退出，让登录项接管。');
      }), child: const Text('启用登录后后台恢复')),
      TextButton(onPressed: _busy ? null : () => _run(() async {
        await _call('disableBackgroundAgent');
        if (mounted) setState(() => _message = '已移除后台登录项。MDM 捕获仍保留，缺少 Core 时应用保持阻断。');
      }), child: const Text('移除后台登录项')),
      TextButton(onPressed: _busy ? null : () => _run(() async {
        await perAppPolicyStore.ensureLoaded();
        final paths = perAppPolicyStore.entries.where((entry) => entry.policy == ApplicationRoutingPolicy.proxy ||
            entry.policy == ApplicationRoutingPolicy.block).map((entry) => entry.path).toList();
        final identities = await _channel.invokeMapMethod<String, dynamic>('exportIdentities', paths);
        if (identities == null) throw StateError('无法导出签名身份');
        final destination = await FilePicker.platform.saveFile(dialogTitle: '导出 MDM 应用身份', fileName: 'managed-identities.json');
        if (destination != null) {
          await File(destination).writeAsString(const JsonEncoder.withIndent('  ').convert(identities), flush: true);
          if (mounted) setState(() => _message = '已导出签名身份，用于生成受管配置；不包含代理凭据。');
        }
      }), child: const Text('导出 MDM 身份')),
      TextButton(onPressed: _busy ? null : () => _run(() async {
        final result = await _call('activateExtension');
        if (mounted) setState(() => _message = result['rebootRequired'] == true ? '系统要求重启后激活' : '系统扩展激活请求已完成');
      }), child: const Text('激活扩展')),
      TextButton(onPressed: _busy ? null : () => _run(_refresh), child: const Text('刷新配置')),
      TextButton(onPressed: _busy || _account == null ? null : () => _run(() async {
        final result = await _call('status', {'account': _account});
        if (mounted) setState(() => _message = '扩展状态：${jsonEncode(result)}');
      }), child: const Text('状态')),
      TextButton(onPressed: _busy || _account == null ? null : () => _run(() async {
        await _call('stop', {'account': _account});
        if (mounted) setState(() => _message = '旧策略已撤销并保存阻断状态；解除系统接管需修改 MDM 配置。');
      }), child: const Text('停止转发')),
      FilledButton(onPressed: _busy || _account == null ? null : () => _run(_apply), child: const Text('应用策略')),
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭')),
    ],
  );
}
