import 'package:flclashx/providers/config.dart';
import 'package:flclashx/providers/network_automation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NetworkAutomationItem extends ConsumerWidget {
  const NetworkAutomationItem({super.key});
  static const labels = {'ethernet': '有线网络', 'wifi': '无线网络',
    'mobile': '移动网络', 'bluetooth': '蓝牙网络', 'other': '其他网络'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(networkAutomationProvider);
    return ListTile(title: const Text('网络环境自动切换'),
      subtitle: Text(settings.when(data: (value) => value.enabled ? '已启用' : '未启用',
        error: (_, __) => '规则读取失败', loading: () => '读取规则…')),
      trailing: const Icon(Icons.chevron_right),
      onTap: !settings.hasValue ? null : () async {
        var enabled = settings.requireValue.enabled;
        final selections = Map<String, String>.from(settings.requireValue.profiles);
        final profiles = ref.read(profilesProvider);
        var saving = false;
        String? error;
        await showDialog<void>(context: context, builder: (_) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(title: const Text('网络环境自动切换'),
            content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min, children: [
                SwitchListTile(title: const Text('自动选择配置'), value: enabled,
                  onChanged: saving ? null : (value) => setState(() => enabled = value)),
                const Text('网络稳定 2 秒后切换。多种网络共存时按下方顺序匹配；断网保持当前配置和代理运行。'),
                for (final type in NetworkAutomationSettings.priority)
                  DropdownButtonFormField<String>(
                    value: profiles.any((p) => p.id == selections[type]) ? selections[type] : '',
                    decoration: InputDecoration(labelText: labels[type]),
                    items: [const DropdownMenuItem(value: '', child: Text('保持当前配置')),
                      for (final profile in profiles) DropdownMenuItem(value: profile.id,
                        child: Text(profile.label ?? profile.id, overflow: TextOverflow.ellipsis))],
                    onChanged: saving ? null : (value) => setState(() {
                      if (value == null || value.isEmpty) { selections.remove(type); }
                      else { selections[type] = value; }
                    })),
                if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ]))), actions: [
              TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('取消')),
              FilledButton(onPressed: saving ? null : () async {
                setState(() { saving = true; error = null; });
                try {
                  // Remove deleted profile references before committing the rules.
                  selections.removeWhere((_, id) => !profiles.any((p) => p.id == id));
                  await ref.read(networkAutomationProvider.notifier).save(
                    NetworkAutomationSettings(enabled: enabled, profiles: selections));
                  if (context.mounted) Navigator.pop(context);
                } catch (_) {
                  if (context.mounted) setState(() { saving = false; error = '无法保存网络规则'; });
                }
              }, child: const Text('保存')),
            ])));
      });
  }
}
