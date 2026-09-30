import 'package:flclashx/providers/pac.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PacSettingsItem extends ConsumerWidget {
  const PacSettingsItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(pacSettingsProvider);
    return ListTile(
      title: const Text('系统代理模式 / PAC'),
      subtitle: Text(settings.when(data: (value) => value.enabled
          ? 'PAC 自动配置（仅在系统代理开启时生效）' : '固定代理',
          error: (_, __) => '配置读取失败', loading: () => '读取配置…')),
      trailing: const Icon(Icons.chevron_right),
      onTap: settings.hasValue ? () async {
        final initial = settings.requireValue;
        final controller = TextEditingController(text: initial.url);
        var enabled = initial.enabled;
        var saving = false;
        String? error;
        try {
          await showDialog<void>(context: context, builder: (dialogContext) =>
            StatefulBuilder(builder: (context, setState) => AlertDialog(
              title: const Text('PAC 自动配置'),
              content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(title: const Text('使用 PAC'), value: enabled,
                    onChanged: saving ? null : (value) => setState(() => enabled = value)),
                  TextField(controller: controller, enabled: !saving,
                    decoration: InputDecoration(labelText: 'PAC 地址（HTTP / HTTPS）', errorText: error)),
                  const SizedBox(height: 12),
                  const Text('PAC 决定支持系统代理的应用如何连接，不替代严格分应用策略。请使用你信任的配置地址。'),
                ])),
              actions: [
                TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('取消')),
                FilledButton(onPressed: saving ? null : () async {
                  setState(() { saving = true; error = null; });
                  try {
                    await ref.read(pacSettingsProvider.notifier).save(
                      PacSettings(enabled: enabled, url: controller.text.trim()));
                    if (context.mounted) Navigator.pop(context);
                  } catch (_) {
                    if (context.mounted) setState(() { saving = false; error = '无法保存，请检查地址和存储权限'; });
                  }
                }, child: const Text('保存')),
              ],
            )));
        } finally { controller.dispose(); }
      } : null,
    );
  }
}
