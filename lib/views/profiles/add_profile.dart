import 'package:flclashx/common/common.dart';
import 'package:flclashx/pages/scan.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'receive_profile_dialog.dart';

Future<void> scanAndAddProfile(BuildContext context) async {
  if (system.isDesktop) {
    await globalState.appController.addProfileFormQrCode();
    return;
  }
  final url = await BaseNavigator.push<String>(
    context,
    const ScanPage(),
  );
  if (url != null && url.isNotEmpty) {
    await globalState.appController.addProfileFormURL(url);
  }
}

class AddProfileView extends StatelessWidget {
  const AddProfileView({
    super.key,
    required this.context,
  });
  final BuildContext context;

  Future<void> _handleAddProfileFormFile() async {
    await globalState.appController.addProfileFormFile();
  }

  Future<void> _handleAddProfileFormURL(String url) async {
    await globalState.appController.addProfileFormURL(url);
  }

  Future<void> _toScan() async {
    await scanAndAddProfile(context);
  }

  Future<void> _toAdd() async {
    final url = await globalState.showCommonDialog<String>(
      child: const URLFormDialog(),
    );
    if (url != null) {
      await _handleAddProfileFormURL(url);
    }
  }

  Future<void> _handleReceiveFromPhone() async {
  final url = await showDialog<String>(
    context: context,
    builder: (_) => const ReceiveProfileDialog(),
  );
  if (url != null && url.isNotEmpty) {
    await _handleAddProfileFormURL(url);
  }
}

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
      future: system.isAndroidTV,
      builder: (context, snapshot) {
        final isTV = snapshot.data ?? false;
        return ListView(
          children: [
            if (isTV)
              ListItem(
                leading: const Icon(Icons.tv_outlined),
                title: Text(appLocalizations.addFromPhoneTitle),
                subtitle: Text(appLocalizations.addFromPhoneSubtitle),
                onTap: _handleReceiveFromPhone,
              ),
            ListItem(
              leading: const Icon(Icons.qr_code_sharp),
              title: Text(appLocalizations.qrcode),
              subtitle: Text(appLocalizations.qrcodeDesc),
              onTap: _toScan,
            ),
            ListItem(
              leading: const Icon(Icons.upload_file_sharp),
              title: Text(appLocalizations.file),
              subtitle: Text(appLocalizations.fileDesc),
              onTap: _handleAddProfileFormFile,
            ),
            ListItem(
              leading: const Icon(Icons.cloud_download_sharp),
              title: Text(appLocalizations.url),
              subtitle: Text(appLocalizations.urlDesc),
              onTap: _toAdd,
            ),
          ],
        );
      },
    );
}

final RegExp _embeddedHttpUrlRegex = RegExp(
  r'''https?://[^\s"'<>`\u3000-\u303F\uFF00-\uFFEF\u4E00-\u9FFF]+''',
  caseSensitive: false,
);
final RegExp _trailingUrlPunctuationRegex = RegExp(r'[.,;!?，。；！？)）】\]}]+$');

/// Extracts a clean `http://` or `https://` subscription URL from raw input or
/// copied chat messages. Returns `null` if no valid HTTP(S) URL is present.
String? extractSubscriptionUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final match = _embeddedHttpUrlRegex.firstMatch(trimmed);
  if (match == null) return null;
  final candidate =
      match.group(0)!.replaceFirst(_trailingUrlPunctuationRegex, '').trim();
  final uri = Uri.tryParse(candidate);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return null;
  }
  return candidate;
}

class URLFormDialog extends StatefulWidget {
  const URLFormDialog({
    super.key,
    this.initialUrl,
    this.initialErrorText,
  });

  final String? initialUrl;
  final String? initialErrorText;

  @override
  State<URLFormDialog> createState() => _URLFormDialogState();
}

class _URLFormDialogState extends State<URLFormDialog> {
  late final TextEditingController urlController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    urlController = TextEditingController(text: widget.initialUrl ?? '');
    _errorText = widget.initialErrorText;
  }

  @override
  void dispose() {
    urlController.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final raw = urlController.text;
    if (raw.trim().isEmpty) {
      setState(() {
        _errorText = appLocalizations.subscriptionUrlEmptyError;
      });
      return;
    }
    final extracted = extractSubscriptionUrl(raw);
    if (extracted == null) {
      setState(() {
        _errorText = appLocalizations.subscriptionUrlInvalidError;
      });
      return;
    }
    Navigator.of(context).pop<String>(extracted);
  }

  Future<void> _handlePaste() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final rawText = clipboardData?.text;
    if (rawText == null || rawText.trim().isEmpty) {
      setState(() {
        _errorText = appLocalizations.subscriptionClipboardEmptyError;
      });
      return;
    }
    final extracted = extractSubscriptionUrl(rawText);
    final nextText = extracted ?? rawText.trim();
    urlController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
    setState(() {
      _errorText = extracted == null
          ? appLocalizations.subscriptionUrlInvalidError
          : null;
    });
  }

  @override
  Widget build(BuildContext context) => CommonDialog(
      title: appLocalizations.importFromURL,
      actions: [
        TextButton(
          key: const ValueKey('url-dialog-paste'),
          onPressed: _handlePaste,
          child: Text(appLocalizations.pasteFromClipboard),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: const ValueKey('url-dialog-confirm'),
          onPressed: _handleSubmit,
          child: Text(appLocalizations.confirm),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.only(top: 16.0),
        child: TextField(
          controller: urlController,
          keyboardType: TextInputType.url,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          onChanged: (_) {
            if (_errorText != null) {
              setState(() {
                _errorText = null;
              });
            }
          },
          onSubmitted: (_) => _handleSubmit(),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: appLocalizations.url,
            errorText: _errorText,
            errorMaxLines: 3,
          ),
        ),
      ),
    );
}
