import 'dart:convert';
import 'dart:io';
import 'package:flclashx/clash/core.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/config_diff.dart';
import 'package:flclashx/common/rule_edit_history.dart';
import 'package:flclashx/models/profile.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/pop_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RulesEditorView extends ConsumerStatefulWidget {
  const RulesEditorView({super.key});
  @override
  ConsumerState<RulesEditorView> createState() => _RulesEditorState();
}

class _RulesEditorState extends ConsumerState<RulesEditorView> {
  final _yaml = TextEditingController();
  Profile? _profile;
  String _saved = '', _baseline = '', _status = '';
  RuleEditHistory? _history;
  List<String> _rules = [];
  bool _busy = true;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _yaml.dispose(); super.dispose(); }
  Future<Map<String, dynamic>> _parse(String document) async {
    if (document.length > 4000000) throw StateError('配置超过 4 MB 编辑上限');
    // Use the same parser as profile loading without touching the live profile.
    final id = 'rule-editor-${utils.uuidV4}';
    final file = File(await appPath.getProfilePath(id));
    try {
      await file.writeAsString(document);
      return normalizeConfiguration(await globalState.getProfileConfig(id));
    } finally {
      if (await file.exists()) await file.delete();
    }
  }
  List<String> _readRules(Map<String, dynamic> value) {
    final rules = value['rules'];
    if (rules == null) return [];
    if (rules is! List || rules.any((r) => r is! String)) {
      throw const FormatException('rules 必须是字符串列表');
    }
    return rules.cast<String>();
  }
  Future<void> _load() async {
    await _run(() async {
      final profile = ref.read(currentProfileProvider);
      if (profile == null) throw StateError('请先选择配置');
      final document = await File(await appPath.getProfilePath(profile.id)).readAsString();
      final rules = _readRules(await _parse(document));
      if (!mounted) return;
      _profile = profile;
      _saved = _baseline = document;
      _yaml.text = document;
      _history = RuleEditHistory(document);
      _rules = rules;
    });
  }
  Future<void> _run(Future<void> Function() action) async {
    if (mounted) setState(() { _busy = true; _status = ''; });
    try { await action(); }
    catch (e) { if (mounted) _status = '操作失败：$e'; }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _sync() => _run(() async {
    final rules = _readRules(await _parse(_yaml.text));
    if (!mounted) return;
    _rules = rules;
    _history?.record(_yaml.text);
    _status = 'YAML 与规则列表已同步，尚未保存';
  });
  String _replaceRules(String document, List<String> rules) {
    if (document.trimLeft().startsWith('{')) {
      final value = jsonDecode(document);
      if (value is! Map<String, dynamic>) throw const FormatException('配置必须是对象');
      value['rules'] = rules;
      return const JsonEncoder.withIndent('  ').convert(value);
    }
    // Replace only the top-level rules block; unrelated YAML/comments survive.
    final lines = document.split('\n');
    final start = lines.indexWhere((l) => RegExp(r'''^(rules|"rules"|'rules')\s*:''').hasMatch(l));
    final block = ['rules:', ...rules.map((r) => '  - ${jsonEncode(r)}')];
    if (rules.isEmpty) block.replaceRange(0, block.length, ['rules: []']);
    if (start < 0) {
      return [...lines, ...block].join('\n');
    }
    var end = start + 1;
    while (end < lines.length) {
      final line = lines[end];
      if (line.trim().isNotEmpty && !line.startsWith(' ') &&
          !line.startsWith('\t') && !line.startsWith('-') && !line.startsWith('#')) break;
      end++;
    }
    return [...lines.take(start), ...block, ...lines.skip(end)].join('\n');
  }
  Future<void> _setRules(List<String> rules) => _run(() async {
    if (_history?.current != _yaml.text) {
      throw StateError('YAML 有未同步修改，请先点击“同步 YAML”');
    }
    final document = _replaceRules(_yaml.text, rules);
    final parsed = _readRules(await _parse(document));
    if (!mounted) return;
    _history?.record(document);
    _yaml.text = document;
    _rules = parsed;
  });
  Future<void> _edit([int? index]) async {
    final controller = TextEditingController(text: index == null ? '' : _rules[index]);
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: Text(index == null ? '添加规则' : '编辑规则'),
      content: TextField(controller: controller, autofocus: true,
        decoration: const InputDecoration(labelText: '完整 Mihomo 规则', hintText: 'DOMAIN-SUFFIX,example.com,DIRECT')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('确定'))]));
    controller.dispose();
    if (!mounted || value == null || value.isEmpty) return;
    final rules = [..._rules];
    if (index == null) { rules.add(value); } else { rules[index] = value; }
    await _setRules(rules);
  }
  Future<void> _historyMove(bool undo) => _run(() async {
    final history = _history;
    if (history == null) return;
    if (_yaml.text != history.current) history.record(_yaml.text);
    final document = undo ? history.undo() : history.redo();
    _yaml.text = document;
    _rules = _readRules(await _parse(document));
  });
  Future<void> _restore() => _run(() async {
    final parsed = _readRules(await _parse(_baseline));
    if (!mounted) return;
    _history?.record(_yaml.text);
    _history?.record(_baseline);
    _yaml.text = _baseline;
    _rules = parsed;
    _status = '已恢复打开时的内容，点击保存后写入';
  });
  Future<void> _save() => _run(() async {
    final profile = _profile;
    if (profile == null) return;
    final document = _yaml.text;
    final parsedRules = _readRules(await _parse(document));
    final message = await clashCore.validateConfig(document);
    if (message.isNotEmpty) throw StateError(message);
    final path = await appPath.getProfilePath(profile.id);
    if (await File(path).readAsString() != _saved) {
      throw StateError('配置已被订阅刷新或其他编辑器修改，未覆盖；请退出后重新打开');
    }
    final current = ref.read(profilesProvider).getProfile(profile.id);
    if (current == null) throw StateError('配置已被删除');
    if (current.autoUpdate && current.url.isNotEmpty) {
      final accepted = await globalState.showMessage(message: const TextSpan(
        text: '保存将关闭此订阅的自动更新，避免手动规则被覆盖。继续？'));
      if (accepted != true) return;
    }
    // Check again after the confirmation, which can remain open during refresh.
    if (await File(path).readAsString() != _saved) throw StateError('配置已改变，未覆盖');
    final latest = ref.read(profilesProvider).getProfile(profile.id);
    if (latest == null) throw StateError('配置已被删除');
    final saved = await latest.saveFileWithString(document);
    globalState.appController.setProfileAndAutoApply(saved.copyWith(autoUpdate: false));
    if (!mounted) return;
    _saved = document;
    _rules = parsedRules;
    _history?.record(document);
    _status = '配置已保存；当前配置将通过现有流程重新应用';
  });
  Future<void> _effectiveDiff() => _run(() async {
    final parsed = await _parse(_yaml.text);
    final runtime = await clashCore.clashInterface.getConfig('fcx://runtime');
    if (!runtime.isSuccess) throw StateError(runtime.message);
    final currentRules = normalizeConfiguration(Map<String, dynamic>.from(runtime.data as Map))['rules'];
    final changes = configurationDiff(currentRules, parsed['rules']);
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Text('实际 Core → 编辑规则'),
      content: SizedBox(width: 720, child: SingleChildScrollView(child: SelectableText(
        '此比较包含覆写、脚本与应用策略带来的差异；保存源配置后这些覆写仍然生效。\n\n${changes.isEmpty ? '没有差异' : changes.join('\n\n')}'))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))]));
  });
  @override
  Widget build(BuildContext context) => CommonPopScope(
    onPop: () async {
      if (_busy) return false;
      if (_yaml.text == _saved) return true;
      return await globalState.showMessage(message: const TextSpan(text: '有未保存的修改，丢弃并退出？')) == true;
    },
    child: DefaultTabController(length: 2, child: Column(children: [
    Padding(padding: const EdgeInsets.all(8), child: Wrap(spacing: 4, children: [
      TextButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.save), label: const Text('保存')),
      TextButton(onPressed: _busy ? null : _sync, child: const Text('同步 YAML')),
      TextButton(onPressed: _busy ? null : _effectiveDiff, child: const Text('生效差异')),
      IconButton(tooltip: '撤销', onPressed: _busy || !(_history?.canUndo == true || _history?.current != _yaml.text) ? null : () => _historyMove(true), icon: const Icon(Icons.undo)),
      IconButton(tooltip: '重做', onPressed: _busy || _history?.canRedo != true ? null : () => _historyMove(false), icon: const Icon(Icons.redo)),
      TextButton(onPressed: _busy ? null : _restore, child: const Text('恢复打开时内容')),
    ])),
    if (_busy) const LinearProgressIndicator(),
    if (_status.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: SelectableText(_status)),
    const TabBar(tabs: [Tab(text: '规则列表'), Tab(text: 'YAML')]),
    Expanded(child: TabBarView(children: [Column(children: [
      ListTile(title: Text('${_profile?.label ?? _profile?.id ?? "配置"} · ${_rules.length} 条源规则'),
        trailing: IconButton(tooltip: '添加规则', onPressed: _busy ? null : () => _edit(), icon: const Icon(Icons.add))),
      Expanded(child: ReorderableListView.builder(itemCount: _rules.length,
        onReorder: (oldIndex, newIndex) {
          if (_busy) return;
          final rules = [..._rules];
          if (newIndex > oldIndex) newIndex--;
          rules.insert(newIndex, rules.removeAt(oldIndex));
          _setRules(rules);
        }, itemBuilder: (context, index) => ListTile(key: ValueKey(index),
          title: Text(_rules[index]), onTap: _busy ? null : () => _edit(index),
          trailing: Padding(padding: const EdgeInsets.only(right: 36), child: IconButton(
            tooltip: '删除规则', onPressed: _busy ? null : () => _setRules([..._rules]..removeAt(index)), icon: const Icon(Icons.delete_outline)))))),
    ]), Padding(padding: const EdgeInsets.all(12), child: TextField(controller: _yaml,
      enabled: !_busy, expands: true, maxLines: null, minLines: null,
      onChanged: (_) => setState(() {}), style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
      decoration: const InputDecoration(border: OutlineInputBorder(), labelText: '完整配置 YAML（修改后同步或保存）'))),
    ])),
  ])));
}
