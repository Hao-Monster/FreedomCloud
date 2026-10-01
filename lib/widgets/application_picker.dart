import 'package:flclashx/common/application_discovery.dart';
import 'package:flclashx/views/connection/item.dart';
import 'package:flutter/material.dart';

class ApplicationPickerDialog extends StatefulWidget {
  const ApplicationPickerDialog({super.key, required this.recent});
  final List<ApplicationCandidate> recent;
  @override
  State<ApplicationPickerDialog> createState() => _ApplicationPickerDialogState();
}

class _ApplicationPickerDialogState extends State<ApplicationPickerDialog> {
  final _search = TextEditingController();
  late List<ApplicationCandidate> _applications = widget.recent;
  bool _loading = true;
  String? _warning;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _warning = null; });
    try {
      final result = await discoverApplications(widget.recent);
      if (mounted) setState(() { _applications = result.applications; _warning = result.warning; });
    } catch (_) {
      if (mounted) setState(() { _warning = '无法读取应用列表，可重试或手动选择。'; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = _applications.where((app) => query.isEmpty ||
        app.name.toLowerCase().contains(query) || app.executable.toLowerCase().contains(query)).toList(growable: false);
    return AlertDialog(
      title: const Text('选择应用'),
      content: SizedBox(width: 620, height: (MediaQuery.sizeOf(context).height * .6).clamp(220.0, 480.0).toDouble(),
        child: Column(children: [
          TextField(controller: _search, onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: '搜索名称或程序路径', prefixIcon: Icon(Icons.search))),
          if (_loading) const LinearProgressIndicator(),
          if (_warning != null) Row(children: [Expanded(child: Text(_warning!)),
            IconButton(onPressed: _loading ? null : _load, tooltip: '重试', icon: const Icon(Icons.refresh))]),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('最近联网包含真实子进程；列表仅用于选择，严格模式会重新校验程序身份。')),
          Expanded(child: visible.isEmpty
              ? Center(child: Text(_loading ? '正在发现已安装应用…' : '没有匹配项，请手动选择程序'))
              : ListView.builder(itemCount: visible.length, itemBuilder: (context, index) {
                  final app = visible[index];
                  return ListTile(
                    leading: ProcessIcon(process: app.name, processPath: app.executable, size: 32),
                    title: Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${app.source} · ${app.executable}', maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(context, app),
                  );
                })),
        ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(context, const ApplicationCandidate(name: '', executable: '', source: 'manual')),
          child: const Text('手动选择程序')),
      ],
    );
  }
}
