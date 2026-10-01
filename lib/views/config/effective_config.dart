import 'dart:convert';
import 'package:flclashx/models/common.dart';
import 'package:flclashx/clash/core.dart';
import 'package:flclashx/common/config_diff.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EffectiveConfigView extends ConsumerStatefulWidget {
  const EffectiveConfigView({super.key});
  @override
  ConsumerState<EffectiveConfigView> createState() => _EffectiveConfigState();
}

class _EffectiveConfigState extends ConsumerState<EffectiveConfigView> {
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _source, _submitted, _actual;
  DateTime? _captured;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { _busy = true; _error = null; });
    try {
      final profile = ref.read(currentProfileProvider);
      if (profile == null) throw StateError('请先选择配置');
      final source = await globalState.getProfileConfig(profile.id);
      final runtime = await clashCore.clashInterface.getConfig('fcx://runtime');
      if (!runtime.isSuccess) throw StateError(runtime.message);
      if (ref.read(currentProfileProvider)?.id != profile.id) {
        throw StateError('当前配置已改变，请刷新');
      }
      if (!mounted) return;
      setState(() {
        _source = normalizeConfiguration(source);
        final submitted = globalState.lastRuntimeProfileId == profile.id ? globalState.lastRuntimeConfig : null;
        _submitted = submitted == null ? null : normalizeConfiguration(submitted);
        _actual = normalizeConfiguration(Map<String, dynamic>.from(runtime.data as Map));
        _captured = DateTime.now();
      });
    } catch (e) {
      if (mounted) setState(() { _error = '无法读取配置：$e'; _source = null; _actual = null; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  Widget _text(String value) => SingleChildScrollView(
    padding: const EdgeInsets.all(16), child: SelectableText(value,
      style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12)));
  String _json(Object? value) => const JsonEncoder.withIndent('  ').convert(redactConfiguration(value));
  String _diff(Object? a, Object? b) {
    final changes = configurationDiff(redactConfiguration(a), redactConfiguration(b));
    return changes.isEmpty ? '没有差异' : changes.join('\n\n');
  }
  @override
  Widget build(BuildContext context) => DefaultTabController(length: 5, child: Column(children: [
    ListTile(title: const Text('生效配置差异'),
      subtitle: Text(_captured == null ? '从 Core 读取实际应用配置' : '快照：$_captured。覆写列是最近提交值；Core 列来自运行中的 Core。敏感字段已隐藏。'),
      trailing: IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh))),
    if (_busy) const LinearProgressIndicator(),
    if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
    const TabBar(isScrollable: true, tabs: [Tab(text: '订阅'), Tab(text: '覆写后提交'), Tab(text: '实际 Core'), Tab(text: '订阅 → Core'), Tab(text: '提交 → Core')]),
    Expanded(child: TabBarView(children: [
      _text(_json(_source)), _text(_submitted == null ? '没有本会话提交记录' : _json(_submitted)),
      _text(_json(_actual)), _text(_source == null ? '未读取' : _diff(_source, _actual)),
      _text(_submitted == null || _actual == null ? '未读取' : _diff(_submitted, _actual)),
    ])),
  ]));
}
