import 'package:flclashx/common/signed_update.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';

class SignedUpdateDialog extends StatefulWidget {
  const SignedUpdateDialog({super.key});
  @override
  State<SignedUpdateDialog> createState() => _SignedUpdateDialogState();
}

class _SignedUpdateDialogState extends State<SignedUpdateDialog> {
  final _updater = SignedUpdate();
  bool _busy = false;
  bool _ready = false;
  bool _rollback = false;
  double? _progress;
  String _status = '下载签名完整应用并预先准备回滚。更新会关闭代理和应用；完整安装器请求 Windows 提权，便携版保留并排版本，macOS 按需授权安装已验证网络核心。';

  @override
  void initState() {
    super.initState();
    if (_updater.unavailable != null) {
      _status = _updater.unavailable!;
    } else {
      _loadStatus();
    }
  }

  Future<void> _loadStatus() async {
    try {
      final available = await _updater.hasRollback();
      final result = await _updater.lastResult();
      if (mounted) setState(() {
        _rollback = available;
        if (result != null) _status = result;
      });
    } catch (error) {
      if (mounted) setState(() => _status = error.toString());
    }
  }

  Future<void> _prepare() async {
    setState(() { _busy = true; _ready = false; _progress = null; });
    try {
      final version = globalState.appVersionTag.isNotEmpty
          ? globalState.appVersionTag : globalState.packageInfo.version;
      final next = await _updater.prepare(version, (status, progress) {
        if (mounted) setState(() { _status = status; _progress = progress; });
      });
      if (mounted) setState(() {
        _ready = true;
        _status = '$next 已通过发布签名及完整文件校验，可以关闭代理并更新。';
      });
    } catch (error) {
      if (mounted) setState(() => _status = error.toString());
    } finally {
      if (mounted) setState(() { _busy = false; _progress = null; });
    }
  }

  Future<void> _apply(bool rollback) async {
    setState(() { _busy = true; _status = rollback ? '准备回滚并关闭应用' : '准备切换并关闭应用'; });
    try {
      await _updater.launch(rollback: rollback);
      await globalState.appController.handleExit();
    } catch (error) {
      if (mounted) setState(() { _busy = false; _status = error.toString(); });
    }
  }

  @override
  void dispose() { _updater.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('签名完整应用更新'),
      content: SizedBox(width: 480, child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_status),
          const SizedBox(height: 16),
          const Text('保留订阅、设置和用户数据。失败时恢复先前便携版本或重新安装已验证旧安装包；恢复失败会明确记录。macOS/Linux 更新需要 Python 3.9+ 与支持 CMS 的 OpenSSL；macOS 还须有效 Developer ID 签名及公证。'),
          if (_busy) ...[const SizedBox(height: 16), LinearProgressIndicator(value: _progress)],
        ],
      )),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('关闭')),
        if (_rollback) TextButton(onPressed: _busy ? null : () => _apply(true), child: const Text('回滚上一个版本')),
        if (_updater.unavailable == null)
          FilledButton(onPressed: _busy ? null : _ready ? () => _apply(false) : _prepare,
            child: Text(_ready ? '关闭代理并更新' : '检查并准备更新')),
      ],
    ),
  );
}
