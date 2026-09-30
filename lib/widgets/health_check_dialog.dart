import 'package:file_picker/file_picker.dart';
import 'package:flclashx/common/health_diagnostics.dart';
import 'package:flclashx/providers/config.dart';
import 'package:flclashx/providers/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HealthCheckDialog extends ConsumerStatefulWidget {
  const HealthCheckDialog({super.key});
  @override
  ConsumerState<HealthCheckDialog> createState() => _HealthCheckDialogState();
}

class _HealthCheckDialogState extends ConsumerState<HealthCheckDialog> {
  List<HealthCheckResult> _results = const [];
  bool _running = false;
  String? _message;
  static const _labels = {'profile_selected': '已选择配置', 'proxy_requested': '代理运行状态',
    'core_initialized': 'Core 初始化', 'core_memory_response': 'Core 内存接口',
    'core_traffic_response': 'Core 流量接口'};
  static const _statuses = {'passed': '正常', 'failed': '未满足', 'timeout': '超时', 'unavailable': '不可用'};

  @override
  void initState() { super.initState(); Future.microtask(_run); }

  Future<void> _run() async {
    if (!mounted || _running) return;
    setState(() { _running = true; _results = []; _message = null; });
    try {
      await HealthDiagnostics.run(
        hasProfile: ref.read(currentProfileIdProvider) != null,
        proxyRequested: ref.read(runTimeProvider) != null,
        onProgress: (results) { if (mounted) setState(() => _results = results); });
    } catch (_) {
      if (mounted) setState(() => _message = '检查正在其他窗口运行，请稍后重试');
    } finally { if (mounted) setState(() => _running = false); }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(title: const Text('健康检查'),
    content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('检查本地配置和控制接口。结果不代表严格 WFP 已启用，也不替代实际流量验收。导出不含配置、地址、凭据或原始日志。'),
      if (_running) const LinearProgressIndicator(),
      for (final result in _results) ListTile(dense: true,
        title: Text(_labels[result.check] ?? result.check),
        trailing: Text(_statuses[result.status] ?? result.status)),
      if (_message != null) Text(_message!),
    ])), actions: [
      TextButton(onPressed: _running ? null : _run, child: const Text('重新检查')),
      TextButton(onPressed: _running || _results.isEmpty ? null : () async {
        try {
          final destination = await FilePicker.platform.saveFile(
            dialogTitle: '导出脱敏诊断', fileName: 'freedomcloud-health.json',
            type: FileType.custom, allowedExtensions: ['json'],
            bytes: HealthDiagnostics.export(_results));
          if (mounted && destination != null) setState(() => _message = '诊断已导出');
        } catch (_) { if (mounted) setState(() => _message = '诊断导出失败'); }
      }, child: const Text('导出')),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
    ]);
}
